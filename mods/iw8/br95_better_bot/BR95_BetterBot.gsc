// BR95 BETTER BOT - one mod for everything bots in BR95 / IW8 Warzone:
//   combat AI, waves of bots on you, 90 m leash, weapons, ammo on kills, loot drops
//   and the addbot / removebot / botdifficulty console commands.
// Replaces BotAI.gsc, BotLoot.gsc and Bots.gsc: never load it alongside them.

init()
{
    // commands first so their dvars exist, then the AI (it forces botdifficulty 3), then loot
    botcommands_init();
    botai_init();
    botloot_init();
}

// ======================================================================
// combat AI, waves, 90 m leash, weapons, kill ammo (was BotAI.gsc)
// ======================================================================

// combat AI; botdifficulty 0-3 (from the commands section) also sets the skill tier here.
//
// settings:
//   bai_enabled 1      turn the combat AI on/off
//   bai_aggression 80  0-100, how readily bots push instead of falling back
//   bai_botdamage 15   % of damage a bot keeps when another bot shoots it (humans always take 100%)
//   bai_hunt_range 250 metres within which a bot with nobody in sight goes after the nearest enemy
//   bai_radius 90    bots farther than this many metres from every human are moved back around them
//   bai_kill_ammo 60   reserve ammo added to every gun of a human who kills a bot
//   bai_wave 1        periodic rush on a human player
//   bai_wave_time 30   seconds between rushes
//   bai_wave_size 3    bots sent per rush

botai_init()
{
    // forced on every load so the default is veteran whatever the commands section initialised it to
    setdvar( "botdifficulty", 3 );
    setdvarifuninitialized( "bai_enabled", 1 );
    setdvarifuninitialized( "bai_aggression", 80 );
    setdvarifuninitialized( "bai_botdamage", 15 );
    setdvarifuninitialized( "bai_hunt_range", 250 );
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
    iprintln( "^2BR95 BETTER BOT loaded" );
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

    // don't wait for "spawned_player": some resurgence spawns never send it
    watchdog_started = 0;

    if ( isbot( self ) )
    {
        self thread life_watchdog();
        watchdog_started = 1;
    }

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

        self keep_gun_ready();

        // a pistol alone doesn't count: the bot gets two real guns
        if ( self count_main_guns() > 0 )
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

    // run even with the combat AI off: the killer still gets ammo, the bot still holds a loaded gun
    self thread reward_killer();
    self thread bot_weapon_keeper();
    self thread bot_damage_shield();

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

// 4 times a second: never let the bot fight with its fists or an empty gun
// (same idea as the old iw10 bot_ammo_manager, which worked in this build)
bot_weapon_keeper()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    for (;;)
    {
        wait 0.25;

        if ( self isparachuting() || self isskydiving() )
            continue;

        self keep_gun_ready();
    }
}

keep_gun_ready()
{
    current = self getcurrentweapon();

    if ( !isdefined( current ) || !isdefined( current.basename ) || current.basename == "none" )
        return;

    if ( !is_main_gun( current ) )
    {
        // fists, knife or pistol in hand: take out a main gun if the bot has one
        weapons = self getweaponslistprimaries();

        foreach ( weapon in weapons )
        {
            if ( is_main_gun( weapon ) )
            {
                self scripts\cp_mp\utility\inventory_utility::_switchtoweaponimmediate( weapon );
                return;
            }
        }

        return;
    }

    // bots fire non-stop: keep their reserve full so they never run dry and put the gun away,
    // and make them reload for real (with the animation) when the clip runs low
    clip_size = weaponclipsize( current );

    if ( self getweaponammostock( current ) < clip_size )
        self givemaxammo( current );

    if ( self getweaponammoclip( current ) <= int( clip_size * 0.15 ) )
        self botpressbutton( "reload" );
}

// bots hurt each other very little so squads don't wipe in seconds; humans still take full damage
bot_damage_shield()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "bai_stop" );
    level endon( "game_ended" );

    for (;;)
    {
        self waittill( "damage", amount, attacker );

        if ( !isdefined( attacker ) || attacker == self || !isdefined( attacker.sessionstate ) || !isbot( attacker ) )
            continue;

        if ( !isalive( self ) || !isdefined( self.maxhealth ) )
            continue;

        kept = clamp_int( getdvarint( "bai_botdamage", 15 ), 0, 100 );
        heal = int( amount * ( 100 - kept ) / 100 );

        if ( heal > 0 )
            self.health = clamp_int( self.health + heal, 1, self.maxhealth );
    }
}

count_main_guns()
{
    count = 0;
    weapons = self getweaponslistprimaries();

    foreach ( weapon in weapons )
    {
        if ( is_main_gun( weapon ) )
            count++;
    }

    return count;
}

// a real gun that isn't a pistol
is_main_gun( weapon )
{
    name = weapon;

    if ( !isstring( weapon ) && isdefined( weapon.basename ) )
        name = weapon.basename;

    if ( !isstring( name ) || issubstr( name, "_pi_" ) )
        return 0;

    return is_real_gun( name );
}

// guns only: fists, knives and other melee items don't count
is_real_gun( weapon )
{
    name = weapon;

    if ( !isstring( weapon ) && isdefined( weapon.basename ) )
        name = weapon.basename;

    if ( !isstring( name ) )
        return 0;

    tags = [ "_ar_", "_sm_", "_sn_", "_lm_", "_sh_", "_sg_", "_mr_", "_pi_", "_dm_" ];

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

        if ( now < next_move )
            continue;

        // nobody in sight: hunt the nearest enemy instead of standing around
        if ( !isdefined( enemy ) )
        {
            next_move = now + 1500;
            prey = self nearest_enemy( getdvarint( "bai_hunt_range", 250 ) * 39.37 );

            if ( isdefined( prey ) )
                self hunt( prey );

            continue;
        }

        aggression = getdvarint( "bai_aggression", 80 );
        dist = distance( self.origin, enemy.origin );
        hp = self health_fraction();

        if ( hp < 0.25 && now > self.bai_next_retreat && randomint( 100 ) >= aggression )
        {
            if ( self retreat_from( enemy ) )
            {
                retreat_until = now + randomintrange( 2000, 3000 );
                self.bai_next_retreat = now + 12000;
                continue;
            }
        }

        // always on the move: strafe up close, close the distance otherwise
        next_move = now + randomintrange( 700, 1300 );

        if ( dist < 600 )
        {
            if ( randomint( 100 ) < 60 )
                strafe_dir = strafe_dir * -1;

            self strafe_around( enemy, strafe_dir );

            if ( dist < 300 && randomint( 100 ) < 12 )
                self botpressbutton( "jump" );
        }
        else
        {
            self push_toward( enemy );
        }
    }
}

nearest_enemy( max_dist )
{
    best = undefined;
    best_sq = max_dist * max_dist;

    foreach ( player in level.players )
    {
        if ( !self is_enemy( player ) )
            continue;

        d = distancesquared( self.origin, player.origin );

        if ( d < best_sq )
        {
            best = player;
            best_sq = d;
        }
    }

    return best;
}

// sprint to where the prey is and tell the bot about it, so it engages as soon as it gets there
hunt( prey )
{
    point = botgetclosestnavigablepoint( prey.origin, 400 );

    if ( !isdefined( point ) )
        return;

    self botsetflag( "force_sprint", 1 );
    self botgetimperfectenemyinfo( prey, prey.origin );
    self set_goal( point, 200, "objective" );
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

// ======================================================================
// ammo and cash dropped by dead bots (was BotLoot.gsc)
// ======================================================================

// BotLoot - bots drop AR / SMG / sniper ammo and cash when they die (Warzone only).
// Kept apart from BotAI.gsc so a problem here never takes the bot AI down with it.
//
// settings:
//   bloot_enabled 1    turn the drops on/off
//   bloot_ammo 60      ammo per ammo type dropped
//   bloot_cash 300     cash dropped

botloot_init()
{
    setdvarifuninitialized( "bloot_enabled", 1 );
    setdvarifuninitialized( "bloot_ammo", 60 );
    setdvarifuninitialized( "bloot_cash", 300 );

    level thread find_loot_names();
    level thread loot_watch_connections();
}

loot_watch_connections()
{
    level endon( "game_ended" );

    for (;;)
    {
        level waittill( "connected", player );
        player thread watch_deaths();
    }
}

watch_deaths()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    for (;;)
    {
        self waittill( "death" );

        if ( !isbot( self ) || getdvarint( "bloot_enabled", 1 ) == 0 )
            continue;

        level thread drop_loot( self.origin );
    }
}

// reads the Warzone loot table once and keeps only item names the map really knows
find_loot_names()
{
    level endon( "game_ended" );

    timeout = gettime() + 60000;

    while ( !isdefined( level.br_lootiteminfo ) && gettime() < timeout )
        wait 1;

    if ( !isdefined( level.br_lootiteminfo ) )
        return;

    names = [];
    cash = undefined;
    table = "mp/loot/br/default/loot_item_defs.csv";
    rows = tablelookupgetnumrows( table );

    if ( !isdefined( rows ) )
        rows = 0;

    for ( i = 0; i < rows; i++ )
    {
        if ( i % 50 == 0 )
            waitframe();

        name = tablelookupbyrow( table, i, 1 );

        if ( !isdefined( name ) || !isdefined( level.br_lootiteminfo[ name ] ) )
            continue;

        if ( issubstr( name, "brloot_ammo_" ) && !issubstr( name, "rocket" ) && !issubstr( name, "12g" ) )
            names[ names.size ] = name;
        else if ( !isdefined( cash ) && issubstr( name, "plunder_cash" ) )
            cash = name;
    }

    level.bloot_names = names;
    level.bloot_cash = cash;

    has_cash = "no";

    if ( isdefined( cash ) )
        has_cash = "yes";

    iprintln( "^2BR95 BETTER BOT loot: " + names.size + " ammo types, cash: " + has_cash );
}

drop_loot( origin )
{
    if ( !isdefined( level.bloot_names ) )
        return;

    ammo = getdvarint( "bloot_ammo", 60 );

    foreach ( name in level.bloot_names )
    {
        spawn_item( name, origin, ammo );
        waitframe();
    }

    if ( isdefined( level.bloot_cash ) )
        spawn_item( level.bloot_cash, origin, getdvarint( "bloot_cash", 300 ) );
}

spawn_item( name, origin, count )
{
    point = spawnstruct();
    point.origin = origin + ( randomintrange( -40, 40 ), randomintrange( -40, 40 ), 8 );
    point.angles = ( 0, randomint( 360 ), 0 );

    scripts\mp\gametypes\br_pickups::spawnpickup( name, point, count, 1 );
}

// ======================================================================
// addbot / removebot / botdifficulty console commands (was Bots.gsc)
// ======================================================================

botcommands_init()
{
    setdvarifuninitialized( "removebot", 0);
    setdvarifuninitialized( "addbot", 0 );
    setdvarifuninitialized( "botdifficulty", 0 );
    // bots added on their own at the start of every match (0 = off)
    setdvarifuninitialized( "bai_autofill", 45 );

    level thread monitoraddbot();

    level thread monitorremovebot();

    level thread bot_autofill();
}

// tops the match up to bai_autofill bots once it has started, so nobody has to type addbot in game
bot_autofill()
{
    level endon( "game_ended" );

    // let the map load and the players spawn first
    wait 10;

    target = getdvarint( "bai_autofill", 45 );

    if ( target <= 0 )
        return;

    bots = 0;

    foreach ( player in level.players )
    {
        if ( isdefined( player ) && isbot( player ) )
            bots++;
    }

    needed = target - bots;

    // anything typed with "set addbot N" in the menu is already in the match, so only the difference is added
    if ( needed > 0 )
        setdvar( "addbot", getdvarint( "addbot", 0 ) + needed );

    // report how many really joined: the game may cap the match below what was asked
    wait 15;

    bots = 0;

    foreach ( player in level.players )
    {
        if ( isdefined( player ) && isbot( player ) )
            bots++;
    }

    iprintln( "^3BR95 BETTER BOT: " + bots + " bots in match (asked " + target + ") sv_maxclients "
        + getdvarint( "sv_maxclients", 0 ) + " party_maxplayers " + getdvarint( "party_maxplayers", 0 ) );
}

monitoraddbot()
{
    level endon( "game_ended" );
    for (;;)
    {
        wait 1;
        var_0 = getdvarint( "addbot", 0 );
        if ( var_0 > 0 )
        {
            var_1 = getdvarint( "botdifficulty", 0 );
            var_2 = "Recruit";
            var_3 = "^5";
            switch ( var_1 )
            {
                case 0:
                    var_2 = "Recruit";
                    var_3 = "^5";
                    break;
                case 1:
                    var_2 = "Regular";
                    var_3 = "^2";
                    break;
                case 2:
                    var_2 = "Hardened";
                    var_3 = "^3";
                    break;
                case 3:
                    var_2 = "Veteran";
                    var_3 = "^1";
                    break;
                default:
                    var_2 = "Recruit";
                    var_3 = "^5";
                    break;
            }
            level thread scripts\mp\bots\bots::spawn_bots( var_0, "autoassign", undefined, undefined, undefined, var_2 );
            var_4 = "bots";
            if ( var_0 == 1 )
                var_4 = "bot";
            iprintlnbold( "^'added ^*" + var_0 + " " + var_3 + var_2 + " ^'" + var_4 );
            setdvar( "addbot", 0 );
        }
    }
}

monitorremovebot()
{
    level endon( "game_ended" );
   
    for( ;; )
    {
        wait 1;
       
        var_0 = getdvarint( "removebot", 0 );
       
        if( var_0 > 0 )
        {
            var_1 = [];
           
            foreach( var_2 in level.players )
            {
                if( isdefined( var_2 ) && isbot( var_2 ) && var_2.connected )
                {
                    var_1[ var_1.size ] = var_2;
                }
            }
           
            var_3 = var_0;
            var_4 = 0;
           
            for( i = var_1.size - 1; i >= 0; i-- )
            {
                wait 0.1;
                if( var_3 <= 0 )
                    break;
               
                if( isdefined( var_1[i] ) )
                {
                    var_1[i] thread bot_drop();
                    var_4++;
                    var_3--;
                }
            }
           
            var_5 = "bots";
            if( var_4 == 1 )
                var_5 = "bot";
           
            iprintlnbold( "^1removed ^*" + var_4 + " ^1" + var_5 );
           
            setdvar( "removebot", 0 );
        }
    }
}

bot_drop()
{
    level endon( "game_ended" );
    if( !isdefined( self ) || !isbot( self ) )
        return;
   
    kick( self.entity_number, "EXE/PLAYERKICKED" );
    wait 1;
}
