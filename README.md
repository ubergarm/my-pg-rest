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
If your database lives somewhere else, tunnel on in:

    # expose yourself to the world if necessary
    ssh -fNT -C -L 0.0.0.0:3306:127.0.0.1:3306 myuser@mysqldbhost.com

Edit the `docker-compose.yml` to suit your needs.

    docker-compose up

Open a `psql` connection with `./psql.sh` assuming default values used the password will be `foobar` of course.

Then open your browser to [http://localhost:3000](http://localhost:3000)

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
2. A schema in PostgreSQL is not just another word for database. It is kind of a namespace of which you can have multiple in a single database. This is handy for merging many remote tables into a database and handling permissions through a 'Role' that matches the schema. E.g. an unauthenticated user will by default have access only to the 'public' schema.

## Foreign Table
An example of how to create a foreign table from a MySQL database:

    -- connect to the 'test' database
    \c test

    -- load extensions after first time install
    CREATE EXTENSION mysql_fdw;

    -- create a server object for each server you have
    -- use actual db address or docker host ip if tunneling
    CREATE SERVER mysql_server
        FOREIGN DATA WRAPPER mysql_fdw
        OPTIONS (host '192.168.1.111', port '3306');

    -- create user mapping for each user you need
    CREATE USER MAPPING FOR postgres
        SERVER mysql_server
        OPTIONS (username 'my_user', password 'my_pass');

    -- create foreign tables for each table you want to federate
    -- pull in as many or few of the columns as you like
    CREATE FOREIGN TABLE users_1(
        id int,
        username varchar,
        passhash varchar,
        email varchar)
    SERVER mysql_server
        OPTIONS (dbname 'legacy_client', table_name 'legacy_users');

    -- optionally pull in similar data from a different database
    CREATE FOREIGN TABLE users_2(
        id int,
        username varchar,
        passhash varchar,
        email varchar)
    SERVER mysql_server
        OPTIONS (dbname 'legacy_client_other', table_name 'legacy_users');

    -- test it out
    SELECT * from users_1 limit 5;

## Federation
An example of how to create a federated view across many database tables:

    -- keep going for all the tables you want to merge
    -- the organization column is optional, your choice
    -- how to keep the data source information (columns/schemas)
    CREATE OR REPLACE VIEW "public".users AS(
        SELECT *,'client' AS organization FROM users_1
            UNION ALL
        SELECT *,'client_other' AS organization FROM users_2
    );

    SELECT * FROM "public".users;

## REST API
Create a schema containing views of resources to expose over the API:

    -- create version 1 api schema
    CREATE SCHEMA "1";

    -- expose resources as views attached to a schema
    CREATE OR REPLACE VIEW "1".users AS
        SELECT * FROM users;

    -- list all schemas and views
    SELECT schemaname, viewname FROM pg_catalog.pg_views
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY schemaname, viewname;

## Authentication
Setup some permissions and roles that match your various schemas:

    -- TODO: THIS SECTION IS NOT DONE YET!!!

    -- create anonymous (unauthenticated) role
    CREATE ROLE anonymous;

    -- allow anonymous access to everything for testing
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "1".users TO anonymous;

Now open your browser and try it at [http://localhost:3000/users](http://localhost:3000/users)

## CLI Testing
Test queries on the command line:

    curl -s http://localhost:3000/users | python -m json.tool

Or of you like `jq`:

    curl -s http://localhost:3000/users?id=lt.8 | jq .

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

## TODO
This example project isn't complete enough. A few nice to haves which I leave as an excercise to the reader.

1. Provide full authentication example
2. Show how to version and map API endpoints per authenticated role
3. Make my own slim [Alpine](https://www.alpinelinux.org/) based Docker Images
4. Handle database through [Sqitch](http://sqitch.org/)
5. Watch X-Files Season 5 _every episode_.
