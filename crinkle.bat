cl -Os /MD /GS- /Oi /fp:fast /QIfist -DCRINKLE -c play_all.cpp 
crinkler play_all.obj kernel32.lib user32.lib msvcrt_old.lib /SUBSYSTEM:console /OUT:play_all.exe
dir play_all.exe


