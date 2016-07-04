#!/bin/bash
docker run -it --rm --link mypgrest_db_1:postgres postgres psql -h postgres -U postgres
