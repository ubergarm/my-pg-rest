my-pg-rest
===
Add the REST API of your dreams to existing MySQL database(s) leveraging
PostgreSQL and PostgREST to bring them all and in the darkness bind them.

## Motivation
Add _another_ database you say?!? Yes! Here are a few use cases:

1. You want a common single endpoint for JSON Web Token authentication, so just to wrap those old user/credential database tables into a single federated view!

2. Migrate a legacy LAMP stack app without breaking existing features by maintaining the old data model while building out a true platform on which those new mobile scalable multitenant apps can stand.

3. The new kid keeps raving about RethinkDB, Changefeeds, Reactivity and similar buzzwords. You want to let her build cool new things but access the results in a familiar way from the same place as the rest of your data.

4. Finally, an excuse to get work to pay to learn you some Haskell!

5. PostgreS all the things!

## Alternatives
>If your only tool is a Hammer, then every problem looks like an EAV model.

Just _kidding_: I'd suggest you pick up a sledge hammer in that case.

Really though, if you already have a solid data model and a few resource views in mind for quick REST endpoints, check out these other possible solutions as well:

* [sandman2](https://github.com/jeffknupp/sandman2) - The one liner REST API in a box. Great developers tool for testing and debugging locally.
* [php-crud-api](https://github.com/mevdschee/php-crud-api) - Drop in one php file and _boom_ a fully Swagger documented API pops out of `curl`.  Also nicely handles embedding resources client or serverside.
* [Eve](http://python-eve.org/) - Great if you like python and need profesional looking full featured HATEOAS with rate limiting and have time to customize configuration.

## Moving Parts
The moving parts of this stack include:

* PostgreSQL database
* MySQL Foreign Data Wraper (FDW)
* PostgREST service layer
* One or more existing MySQL databases and credentials

Optionally:

* Choose among the many other FDW's including NoSQL or flat CSV file support!
* `ssh` provides secure plumbing from your dev box to your DB server

## Quick Start
Do some configuration:

1. Edit the `docker-compose.yml` and configure it to tunnel into MySQL server.
2. Edit the `foreign-federated-auth.sql` and update:
  * Credentials and target database server.
  * Make sure you have a valid user on the target databases.
  * Match up the `project_0` databases to actual names.
  * Make the inheritable table match your actual table columns.

Now start up the stack:

    # start up all the containers
    docker-compose up
    # reload the `fedauth` database
    ./import.sh foreign-federated-auth.sql
    # command line database access
    ./psql.sh

## Basic Commands
`psql` is the command line postgres tool similar to `mysql`.  Usage examples:

    $ ./psql.sh
    postgres=# \l          # list databases
    postgres=# \c test     # connect to database
    postgres=# \d          # list tables
    postgres=# \d my_table # describe table
    postgres=# \q          # quit

## Concepts
PostgreSQL has a two important concepts to grok for this example:

1. A 'Foreign Table' makes external databases available as if they were a local tables or view.
2. A schema in PostgreSQL is not just another word for database. It is kind of a namespace of which you can have multiple in a single database. This is handy for merging many remote tables into a database and handling permissions through a 'role' that matches the schema. E.g. an unauthenticated user will by default have access only to the 'public' schema.

## CLI Testing
Test queries on the command line using pretty printing or not:


    curl -s -H "Content-Type: application/json" -X POST -d '{"email":"customer@myapp.com","pass":"bigsecret","org":"legacy"}' http://localhost:3000/rpc/login
    curl -s -H "Content-Type: application/json" -X POST -d '{"email":"customer@myapp.com","pass":"bigsecret","org":"legacy"}' http://localhost:3000/rpc/login| python -m json.tool
    curl -s -H "Content-Type: application/json" -X POST -d '{"email":"customer@myapp.com","pass":"bigsecret","org":"legacy"}' http://localhost:3000/rpc/login | jq .

Paste the resulting token into [JSON Web Token](http://jwt.io) to decode and confirm the `secret` matches.

    {
        "email": "customer@myapp.com",
        "org": "legacy",
        "exp": 1467921516,
        "role": "authorized",
        "iat": 1467835116,
        "custom": 18,
        "v": 0
    }

To use the token do access your API with an authorized role:

    curl -X POST -H "Authorization: Bearer PASTETOKENHERE" http://localhost:3000

## Development Staging
To stage the api _insecurely_ over http directly use a reverse ssh tunnel:

    # local_ip:local_port:remote_ip:remote_port
    ssh -fNT -C -R 3000:0.0.0.0:3000 myuser@apiserver.com

Exposing port to external sources requires `/etc/ssh/sshd_config` to have a section like:

    Match User mytestuser
        GatewayPorts yes

Otherwise reverse proxy it from NGINX and an SSL Certificate for `https` etc.

## Shout-outs

* [David Watson](https://github.com/davidthewatson/postgrest_python_requests_client) - Thanks for gently guiding me in the right directsion as I maniacally grope the interwebs for reasonable solutions.
* [Ron Duplain](https://github.com/rduplain) - For planting PostgreSQL seeds in my brain a while back.

## References

* [PostgreSQL](https://www.postgresql.org/)
* [PostgREST](https://github.com/begriffs/postgrest)
* [RethinkDB](https://www.rethinkdb.com/)
* [JWT](https://jwt.io/)
* [Haskell](https://begriffs.com/posts/2015-10-24-learning-haskell-incrementally.html)
* [EAV](https://en.wikipedia.org/wiki/Entity%E2%80%93attribute%E2%80%93value_model)
* [FDW](https://wiki.postgresql.org/wiki/Foreign_data_wrappers)
* [schema](http://www.postgresqlforbeginners.com/2010/12/schema.html)
* [PostGREST Introduction](http://blog.jonharrington.org/postgrest-introduction/)
* [Good Example including Authentication](https://www.compose.io/articles/your-sql-schema-is-your-json-api-with-postgrest/)
* [General Examples](https://begriffs.gitbooks.io/postgrest/content/examples.html)

## BUGS

* This stuff if quite untested in its exact form.
* PostgreSQL container somtimes hangs during autovacuuming sometimes... Ugh...
* Comment out ssh tunnel server references from `docker-compose.yml` if not working.

You can setup a manual tunnel as well e.g.

    # expose docker host to the world
    ssh -fNT -C -L 0.0.0.0:3306:127.0.0.1:3306 myuser@mydbserver.com
    # use your docker host ip address inside any config now

## FEATURES
It'd be nice to show more examples including a writable federated view as well as:

1. Make slim [Alpine](https://www.alpinelinux.org/) based Docker Images
2. Handle database through [Sqitch](http://sqitch.org/)
3. Watch X-Files Season 5 _every episode_.
