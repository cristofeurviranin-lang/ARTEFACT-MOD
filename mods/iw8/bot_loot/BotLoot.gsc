// BotLoot - bots drop AR / SMG / sniper ammo and cash when they die (Warzone only).
// Kept apart from BotAI.gsc so a problem here never takes the bot AI down with it.
//
// settings:
//   bloot_enabled 1    turn the drops on/off
//   bloot_ammo 60      ammo per ammo type dropped
//   bloot_cash 300     cash dropped

init()
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

    iprintln( "^2BotLoot: " + names.size + " ammo types, cash: " + has_cash );
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
