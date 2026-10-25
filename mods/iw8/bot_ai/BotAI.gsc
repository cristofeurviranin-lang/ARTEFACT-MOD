// BotAI - combat AI for bots. Adding/removing bots stays in Bots.gsc
// (addbot / removebot / botdifficulty); botdifficulty 0-3 also sets the skill tier here.
//
// settings:
//   bai_enabled 1      turn the combat AI on/off
//   bai_aggression 50  0-100, how readily bots push instead of falling back
//   bai_radius 90    bots farther than this many metres from every human are moved back around them
//   bai_kill_ammo 60   reserve ammo added to every gun of a human who kills a bot
//   bai_wave 1        periodic rush on a human player
//   bai_wave_time 30   seconds between rushes
//   bai_wave_size 3    bots sent per rush

init()
{
    // forced on every load so the default is veteran whatever Bots.gsc initialised it to
    setdvar( "botdifficulty", 3 );
    setdvarifuninitialized( "bai_enabled", 1 );
    setdvarifuninitialized( "bai_aggression", 50 );
    setdvarifuninitialized( "bai_radius", 90 );
    setdvarifuninitialized( "bai_kill_ammo", 60 );
    setdvarifuninitialized( "bai_wave", 1 );
    setdvarifuninitialized( "bai_wave_time", 30 );
    setdvarifuninitialized( "bai_wave_size", 3 );

    level thread watch_connections();
    level thread leash_loop();
    level thread wave_loop();
    level thread announce_loaded();
}

announce_loaded()
{
    level endon( "game_ended" );

    wait 10;
    iprintln( "^2BotAI loaded" );
}

// ---------------------------------------------------------------- 120 m ring + rushes

leash_loop()
{
    level endon( "game_ended" );

    for (;;)
    {
        wait 2;

        humans = get_humans();

        if ( humans.size == 0 )
            continue;

        max_dist = getdvarint( "bai_radius", 90 ) * 39.37;

        foreach ( bot in level.players )
        {
            if ( !isdefined( bot ) || !isbot( bot ) || !isalive( bot ) || !bot isonground() )
                continue;

            human = nearest_to( bot.origin, humans );

            if ( distance( bot.origin, human.origin ) <= max_dist )
                continue;

            bot place_around( human, max_dist );
            wait 0.05;
        }
    }
}

// put the bot somewhere on the navmesh inside the ring
place_around( human, max_dist )
{
    for ( tries = 0; tries < 6; tries++ )
    {
        angle = randomfloat( 360 );
        dist = randomfloatrange( max_dist * 0.4, max_dist * 0.9 );
        target = human.origin + ( cos( angle ) * dist, sin( angle ) * dist, 0 );
        point = botgetclosestnavigablepoint( target, 1500 );

        if ( !isdefined( point ) || distance2d( point, human.origin ) > max_dist )
            continue;

        self setorigin( point );
        self clear_goal();
        return;
    }
}

wave_loop()
{
    level endon( "game_ended" );

    for (;;)
    {
        interval = clamp_int( getdvarint( "bai_wave_time", 30 ), 5, 600 );
        wait interval;

        if ( getdvarint( "bai_wave", 1 ) == 0 || getdvarint( "bai_enabled", 1 ) == 0 )
            continue;

        humans = get_humans();

        if ( humans.size == 0 )
            continue;

        target = humans[ randomint( humans.size ) ];
        free = [];

        foreach ( bot in level.players )
        {
            if ( isdefined( bot ) && isbot( bot ) && isalive( bot ) && isdefined( bot.bai_rush_until ) && gettime() >= bot.bai_rush_until )
                free[ free.size ] = bot;
        }

        sent = 0;
        wanted = getdvarint( "bai_wave_size", 3 );

        while ( free.size > 0 && sent < wanted )
        {
            pick = randomint( free.size );
            free[ pick ] thread rush( target );

            rest = [];

            for ( i = 0; i < free.size; i++ )
            {
                if ( i != pick )
                    rest[ rest.size ] = free[ i ];
            }

            free = rest;
            sent++;
        }

        if ( sent > 0 )
            iprintln( "^1" + sent + " bot(s) coming for " + target.name );
    }
}

rush( target )
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    self.bai_rush_until = gettime() + 25000;

    self botsetflag( "force_sprint", 1 );
    self botgetimperfectenemyinfo( target, target.origin );
    self botsetattacker( target );

    while ( gettime() < self.bai_rush_until && isalive( target ) )
    {
        if ( distance( self.origin, target.origin ) < 500 )
            break;

        self set_goal( target.origin, 128, "critical" );
        wait 1;
    }

    self.bai_rush_until = 0;
    self clear_goal();
}

get_humans()
{
    humans = [];

    foreach ( player in level.players )
    {
        if ( !isdefined( player ) || isbot( player ) || !isalive( player ) )
            continue;

        if ( isdefined( player.sessionstate ) && player.sessionstate != "playing" )
            continue;

        humans[ humans.size ] = player;
    }

    return humans;
}

nearest_to( origin, players )
{
    best = players[ 0 ];
    best_sq = distancesquared( origin, best.origin );

    for ( i = 1; i < players.size; i++ )
    {
        d = distancesquared( origin, players[ i ].origin );

        if ( d < best_sq )
        {
            best = players[ i ];
            best_sq = d;
        }
    }

    return best;
}

// ---------------------------------------------------------------- per-bot lifecycle

watch_connections()
{
    level endon( "game_ended" );

    for (;;)
    {
        level waittill( "connected", player );
        player thread bot_lifecycle();
    }
}

bot_lifecycle()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    if ( isdefined( self.bai_started ) )
        return;

    self.bai_started = 1;
    self.bai_rush_until = 0;

    if ( isbot( self ) && isalive( self ) )
        self start_ai();

    watchdog_started = 0;

    for (;;)
    {
        self waittill( "spawned_player" );

        if ( !isbot( self ) )
            return;

        if ( !watchdog_started )
        {
            self thread life_watchdog();
            watchdog_started = 1;
        }

        self start_ai();
    }
}

// lives as long as the bot is connected (survives deaths):
// - restarts the AI on respawns the game doesn't announce with "spawned_player" (resurgence redeploys)
// - re-arms the bot whenever it stands on the ground without a real gun
life_watchdog()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    was_dead = 0;
    attempts = 0;

    for (;;)
    {
        wait 0.5;

        if ( !isalive( self ) )
        {
            was_dead = 1;
            continue;
        }

        if ( was_dead )
        {
            was_dead = 0;
            attempts = 0;
            self start_ai();
        }

        if ( self isparachuting() || self isskydiving() || !self isonground() )
            continue;

        if ( self count_real_primaries() > 0 )
            continue;

        // alternate blueprint guns and plain guns in case one way fails for some weapon
        self arm_random( attempts % 2 == 0 );
        attempts++;
        wait 2;
    }
}

start_ai()
{
    self notify( "bai_stop" );

    self.bai_goal_active = 0;
    self.bai_goal_time = 0;
    self.bai_next_retreat = 0;
    self.bai_rush_until = 0;
    self.bai_enemy = undefined;
    self.bai_last_attacker = undefined;

    // runs even with the combat AI off: the killer still gets ammo
    self thread reward_killer();

    if ( getdvarint( "bai_enabled", 1 ) == 0 )
        return;

    self thread apply_skill();
    self thread combat_loop();
    self thread fire_loop();
    self thread damage_reaction();
    self thread unstick_loop();
}

arm_random( use_blueprint )
{
    pool = [ "iw8_ar_mcharlie", "iw8_ar_sierra552", "iw8_ar_galima", "iw8_ar_t9british", "iw8_sm_mpapa5", "iw8_sm_mpapa7", "iw8_sm_t9standard", "s4_ar_stango44", "s4_ar_chotel41", "s4_sm_mpapa40", "s4_sm_ppapa41" ];

    first = pool[ randomint( pool.size ) ];
    second = pool[ randomint( pool.size ) ];

    while ( second == first )
        second = pool[ randomint( pool.size ) ];

    if ( use_blueprint )
        self arm_with( build_weapon( first ), build_weapon( second ) );
    else
        self arm_with( getcompleteweaponname( first ), getcompleteweaponname( second ) );
}

// a human who kills a bot gets extra reserve ammo for every gun they carry
reward_killer()
{
    self endon( "disconnect" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    self thread track_attacker();
    self waittill( "death" );

    killer = self.bai_last_attacker;

    if ( !isdefined( killer ) || !isdefined( killer.sessionstate ) || isbot( killer ) || !isalive( killer ) )
        return;

    if ( gettime() - self.bai_last_attacker_time > 5000 )
        return;

    amount = getdvarint( "bai_kill_ammo", 60 );
    weapons = killer getweaponslistprimaries();

    foreach ( weapon in weapons )
    {
        if ( !is_real_gun( weapon ) )
            continue;

        killer setweaponammostock( weapon, killer getweaponammostock( weapon ) + amount );
    }
}

arm_with( weapon_1, weapon_2 )
{
    if ( !isdefined( weapon_1 ) || !isdefined( weapon_2 ) )
        return;

    self takeallweapons();
    self scripts\cp_mp\utility\inventory_utility::_giveweapon( weapon_1 );
    self scripts\cp_mp\utility\inventory_utility::_giveweapon( weapon_2 );
    waitframe();
    self scripts\cp_mp\utility\inventory_utility::_switchtoweaponimmediate( weapon_1 );
    scripts\mp\weapons::fixupplayerweapons( self, weapon_1 );
    scripts\mp\weapons::fixupplayerweapons( self, weapon_2 );
    self givemaxammo();
}

build_weapon( base )
{
    variant = randomintrange( 1, 15 );
    attachments = scripts\mp\utility\weapon::weaponattachcustomtoidmap( base, variant );

    if ( !isdefined( attachments ) || attachments.size == 0 )
    {
        attachments = [];
        variant = -1;
    }

    return scripts\mp\class::buildweapon_attachmentidmap( base, attachments, "none", "none", variant, undefined, undefined, 0 );
}

track_attacker()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    for (;;)
    {
        self waittill( "damage", amount, attacker );

        if ( !isdefined( attacker ) )
            continue;

        self.bai_last_attacker = attacker;
        self.bai_last_attacker_time = gettime();
    }
}

count_real_primaries()
{
    count = 0;
    weapons = self getweaponslistprimaries();

    foreach ( weapon in weapons )
    {
        if ( is_real_gun( weapon ) )
            count++;
    }

    return count;
}

// guns only: fists, knives and other melee items don't count
is_real_gun( weapon )
{
    name = weapon;

    if ( !isstring( weapon ) && isdefined( weapon.basename ) )
        name = weapon.basename;

    if ( !isstring( name ) )
        return 0;

    tags = [ "_ar_", "_sm_", "_sn_", "_lm_", "_sh_", "_mr_", "_pi_", "_dm_" ];

    foreach ( tag in tags )
    {
        if ( issubstr( name, tag ) )
            return 1;
    }

    return 0;
}

apply_skill()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );

    // let the game finish its own difficulty setup first
    wait 0.5;

    skill = clamp_int( getdvarint( "botdifficulty", 2 ), 0, 3 );
    names = [ "recruit", "regular", "hardened", "veteran" ];
    react = [ 650, 420, 260, 160 ];
    inacc = [ 3.0, 2.0, 1.2, 0.7 ];

    // each bot keeps its own spread for the whole match so they don't feel identical
    if ( !isdefined( self.bai_trait ) )
        self.bai_trait = randomfloatrange( 0.8, 1.25 );

    self scripts\mp\bots\bots_util::bot_set_difficulty( names[ skill ] );

    min_inacc = inacc[ skill ] * self.bai_trait;

    self botsetdifficultysetting( "reactionTime", int( react[ skill ] * self.bai_trait ) );
    self botsetdifficultysetting( "minInaccuracy", min_inacc );
    self botsetdifficultysetting( "maxInaccuracy", min_inacc + 1.0 );
    self botsetdifficultysetting( "meleeReactAllowed", 1 );

    // no pauses between bursts
    self botsetdifficultysetting( "minTimeBetweenBursts", 0 );
    self botsetdifficultysetting( "maxTimeBetweenBursts", 0 );
}

// holds the trigger while an enemy is in sight so the bot doesn't fire in short bursts
fire_loop()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    for (;;)
    {
        wait 0.1;

        enemy = self.bai_enemy;

        if ( !isdefined( enemy ) || !isalive( enemy ) || gettime() - self.bai_enemy_time > 600 )
            continue;

        self botpressbutton( "attack" );
    }
}

combat_loop()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    strafe_dir = 1;
    next_move = 0;
    retreat_until = 0;
    lost_since = 0;

    // spread the scans so every bot doesn't trace on the same frame
    wait randomfloat( 0.3 );

    for (;;)
    {
        wait 0.3;
        now = gettime();

        enemy = self get_visible_enemy( 2200 );

        if ( isdefined( enemy ) )
        {
            self.bai_enemy = enemy;
            self.bai_enemy_time = now;
        }

        if ( now < retreat_until || now < self.bai_rush_until )
            continue;

        if ( retreat_until > 0 )
        {
            retreat_until = 0;
            self clear_goal();
        }

        aggression = getdvarint( "bai_aggression", 50 );

        if ( !isdefined( enemy ) )
        {
            if ( self.bai_goal_active && lost_since == 0 )
                lost_since = now;

            if ( lost_since > 0 && now - lost_since > 2000 )
            {
                self clear_goal();
                lost_since = 0;
            }

            continue;
        }

        lost_since = 0;
        dist = distance( self.origin, enemy.origin );
        hp = self health_fraction();

        if ( hp < 0.4 && now > self.bai_next_retreat && randomint( 100 ) >= aggression )
        {
            if ( self retreat_from( enemy ) )
            {
                retreat_until = now + randomintrange( 2500, 4000 );
                self.bai_next_retreat = now + 9000;
                continue;
            }
        }

        if ( now < next_move )
            continue;

        next_move = now + randomintrange( 1200, 2400 );

        if ( dist < 700 )
        {
            if ( randomint( 100 ) < 60 )
                strafe_dir = strafe_dir * -1;

            self strafe_around( enemy, strafe_dir );

            if ( dist < 300 && randomint( 100 ) < 12 )
                self botpressbutton( "jump" );
        }
        else if ( hp > 0.6 && randomint( 100 ) < aggression )
        {
            self push_toward( enemy );
        }
    }
}

damage_reaction()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    for (;;)
    {
        self waittill( "damage", amount, attacker );

        if ( !isdefined( attacker ) || !self is_enemy( attacker ) )
            continue;

        if ( gettime() < self.bai_rush_until )
            continue;

        if ( isdefined( self get_visible_enemy( 2200 ) ) )
            continue;

        // still inside the 4s retreat window, don't turn around
        if ( gettime() < self.bai_next_retreat - 5000 )
            continue;

        point = botgetclosestnavigablepoint( attacker.origin, 300 );

        if ( !isdefined( point ) )
            continue;

        self set_goal( point, 128, "objective" );
        self thread clear_goal_after( 4 );
    }
}

unstick_loop()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    last_origin = self.origin;

    for (;;)
    {
        wait 2;

        if ( self.bai_goal_active && gettime() - self.bai_goal_time > 2500 && distance( self.origin, last_origin ) < 30 )
        {
            self botsetstance( "stand" );
            self botpressbutton( "jump" );
            self clear_goal();
        }

        last_origin = self.origin;
    }
}

// ---------------------------------------------------------------- movement helpers

retreat_from( enemy )
{
    away = self.origin - enemy.origin;
    away = vectornormalize( ( away[ 0 ], away[ 1 ], 0 ) );

    point = botgetclosestnavigablepoint( self.origin + away * 700, 500 );

    if ( !isdefined( point ) )
        return 0;

    self botsetflag( "force_sprint", 1 );
    self set_goal( point, 96, "critical" );
    return 1;
}

strafe_around( enemy, dir )
{
    angles = vectortoangles( enemy.origin - self.origin );
    right = anglestoright( angles );

    point = botgetclosestnavigablepoint( self.origin + right * dir * randomintrange( 120, 260 ), 150 );

    if ( isdefined( point ) )
        self set_goal( point, 32, "objective" );
}

push_toward( enemy )
{
    point = botgetclosestnavigablepoint( enemy.origin, 300 );

    if ( isdefined( point ) )
        self set_goal( point, 200, "objective" );
}

set_goal( point, radius, priority )
{
    self botsetscriptgoal( point, radius, priority );
    self.bai_goal_active = 1;
    self.bai_goal_time = gettime();
}

clear_goal()
{
    if ( !self.bai_goal_active )
        return;

    self botclearscriptgoal();
    self botsetflag( "force_sprint", 0 );
    self.bai_goal_active = 0;
}

clear_goal_after( seconds )
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    self notify( "bai_damage_goal" );
    self endon( "bai_damage_goal" );

    wait seconds;
    self clear_goal();
}

// ---------------------------------------------------------------- queries

// the bot's own target: the engine sets self.enemy when it has one in sight
get_visible_enemy( max_dist )
{
    enemy = self.enemy;

    if ( !isdefined( enemy ) || !self is_enemy( enemy ) )
        return undefined;

    if ( distancesquared( self.origin, enemy.origin ) > max_dist * max_dist )
        return undefined;

    return enemy;
}

is_enemy( player )
{
    if ( !isdefined( player ) || player == self || !isalive( player ) )
        return 0;

    if ( isdefined( player.sessionstate ) && player.sessionstate != "playing" )
        return 0;

    if ( isdefined( level.teambased ) && level.teambased )
        return player.team != self.team;

    return 1;
}

health_fraction()
{
    if ( !isdefined( self.maxhealth ) || self.maxhealth <= 0 )
        return 1;

    return self.health / self.maxhealth;
}

clamp_int( value, low, high )
{
    if ( value < low )
        return low;

    if ( value > high )
        return high;

    return value;
}
