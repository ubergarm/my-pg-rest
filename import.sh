#!/bin/bash
[[ $# -ne 1 ]] && echo WARNING - DESTRUCTIVE COMMAND. Usage: $0 to-import.sql && exit
docker run -it --rm -v `pwd`/$1:/import.sql --link mypgrest_db_1:postgres postgres psql -h postgres -U postgres -f /import.sql
