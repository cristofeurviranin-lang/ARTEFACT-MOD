init()
{
    setdvarifuninitialized( "removebot", 0);
    setdvarifuninitialized( "addbot", 0 );
    setdvarifuninitialized( "botdifficulty", 0 );

    level thread monitoraddbot();

    level thread monitorremovebot();
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