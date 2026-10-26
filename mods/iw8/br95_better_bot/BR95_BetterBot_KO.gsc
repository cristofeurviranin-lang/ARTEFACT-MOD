// BR95 BETTER BOT - KO timer: anyone downed (bots and players) dies after bai_ko_time seconds
// unless revived first. Kept in its own file on purpose: if this build has no suicide(),
// only this part fails to load and the rest of BR95 BETTER BOT keeps working.
//
// settings:
//   bai_ko_time 3      seconds before a downed player dies (0 = game default)

init()
{
    setdvarifuninitialized( "bai_ko_time", 3 );
    level thread ko_timer();
}

ko_timer()
{
    level endon( "game_ended" );

    for (;;)
    {
        wait 0.25;

        limit = getdvarint( "bai_ko_time", 3 ) * 1000;

        if ( limit <= 0 )
            continue;

        now = gettime();

        foreach ( player in level.players )
        {
            if ( !isdefined( player ) || !isalive( player ) )
                continue;

            // same last stand fields the old iw10 mod read
            if ( !istrue( player.inlaststand ) && !istrue( player.laststand ) )
            {
                player.bai_down_since = undefined;
                continue;
            }

            if ( !isdefined( player.bai_down_since ) )
            {
                player.bai_down_since = now;
                continue;
            }

            if ( now - player.bai_down_since >= limit )
            {
                player.bai_down_since = undefined;
                player suicide();
            }
        }
    }
}
