---------------------------------------------------------------------
-- Federated MySQL Database JWT authorization support with PostgREST
-- Adapted from:
-- https://github.com/robconery/pg-auth
-- https://github.com/begriffs/postgrest/blob/master/schema-templates/blog.sql

-- clean up old database
drop database if exists fedauth;

-- start clean
create database fedauth;

-- connect to database
\c fedauth

-- private schema to store federated auth tables/views
CREATE SCHEMA private;

-- load extensions after first time install
CREATE EXTENSION IF NOT EXISTS mysql_fdw;

-- create server object
-- Assuming 'mysqldb' host available from docker links
CREATE SERVER mysql_server
    FOREIGN DATA WRAPPER mysql_fdw
    OPTIONS ( host 'mysqldb' , port '3306' );

-- create user mapping
-- Have a user on your MySQL server with access to all desired databases:
-- CREATE USER 'fedauth'@'%' IDENTIFIED BY 'mypass';
-- GRANT SELECT on `project\_%`.* to 'fedauth'@'%' IDENTIFIED BY 'mypass';
CREATE USER MAPPING FOR postgres
    SERVER mysql_server
    OPTIONS (username 'fedauth', password 'mypass');

-- create an common table from which all foreign tables can inherit
CREATE TABLE private.users (
    id int,
    name varchar,
    email varchar,
    passhash varchar,
    custom int
);

-- create a foreign tables for each database to federate
CREATE FOREIGN TABLE private.users_0() INHERITS (private.users)
SERVER mysql_server
    OPTIONS (dbname 'project_0', table_name 'users');

CREATE FOREIGN TABLE private.users_1() INHERITS (private.users)
SERVER mysql_server
    OPTIONS (dbname 'project_1', table_name 'users');

CREATE FOREIGN TABLE private.users_2() INHERITS (private.users)
SERVER mysql_server
    OPTIONS (dbname 'project_2', table_name 'users');

-------------------------------------------------------------------------------
-- JWT AUTHENTICATION STUFF

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP ROLE IF EXISTS anon;
CREATE ROLE anon;
DROP ROLE IF EXISTS authorized;
CREATE ROLE authorized;
DROP ROLE IF EXISTS authenticator;
CREATE ROLE authenticator noinherit;
GRANT anon, authorized to authenticator;


-- We put things inside the jwt_auth schema to hide
-- them from public view. Certain public procs/views will
-- refer to helpers and tables inside.
CREATE SCHEMA IF NOT EXISTS jwt_auth;

-- create federated view across all tables above to match JWT auth expectations
--jwt_auth.users (
--  email    text primary key check ( email ~* '^.+@.+\..+$' ),
--  pass     text not null check (length(pass) < 512),
--  role     name not null check (length(role) < 512),
--  verified boolean not null default false
--  -- If you like add more columns, or a json column
--);

-- if you want to do more than just JWT auth like provide some common
-- views exposed over PostgREST you can:
-- 1) make more federated views like in specific schemas
-- 2) create roles that can access those schemas
-- 3) assign those roles to users that authenticate from a given source (org)
--   (the example here simply assigns everyone to the 'authorized' role)
CREATE OR REPLACE VIEW jwt_auth.users AS(
    SELECT email, passhash as pass,text 'authorized' as role,
           text 'project_0' as org, True as verified,
           custom FROM private.users_0
        UNION ALL
    SELECT email, passhash as pass,text 'authorized' as role,
           text 'project_1' as org, True as verified,
           custom FROM private.users_1
        UNION ALL
    SELECT email, passhash as pass,text 'authorized' as role,
           text 'project_2' as org, True as verified,
           custom FROM private.users_2
);

-- Utility functions
create or replace function
jwt_auth.clearance_for_role(u name) returns void as
$$
declare
  ok boolean;
begin
  select exists (
    select rolname
      from pg_authid
     where pg_has_role(current_user, oid, 'member')
       and rolname = u
  ) into ok;
  if not ok then
    raise invalid_password using message =
      'current user not member of role ' || u;
  end if;
end
$$ LANGUAGE plpgsql;


create or replace function
jwt_auth.check_role_exists() returns trigger
  language plpgsql
  as $$
begin
  if not exists (select 1 from pg_roles as r where r.rolname = new.role) then
    raise foreign_key_violation using message =
      'unknown database role: ' || new.role;
    return null;
  end if;
  return new;
end
$$;

-- Login helper
create or replace function
jwt_auth.user_role(email text, pass text, org text) returns name
  language plpgsql
  as $$
begin
  return (
  select role from jwt_auth.users
   where users.email = user_role.email
     and users.pass = crypt(user_role.pass, users.pass)
     and users.org = user_role.org
  );
end;
$$;

create or replace function
jwt_auth.current_email() returns text
  language plpgsql
  as $$
begin
  return current_setting('postgrest.claims.email');
exception
  -- handle unrecognized configuration parameter error
  when undefined_object then return '';
end;
$$;


-------------------------------------------------------------------------------
-- Public functions (in current schema, not jwt_auth)
drop type if exists jwt_auth.jwt_claims cascade;
create type
jwt_auth.jwt_claims AS (role text, email text, org text, v int, iat int, exp int, custom int);

-- the login function sets up all the JWT claims and returns them
-- PostGREST encodes the token and takes care of all that
-- Add anything you want here which would be useful to your systems
-- Check out OpenID Connect JWT Spec for some ideas
-- https://firebase.google.com/docs/auth/server/create-custom-tokens
-- https://github.com/firebase/php-jwt
-- http://openid.net/specs/openid-connect-core-1_0.html
create or replace function
login(email text, pass text, org text) returns jwt_auth.jwt_claims
  language plpgsql
  as $$
declare
  _role name;
  _v int;      -- version, set to 0
  _iat int;    -- issued at, unix epoch time in seconds UTC
  _exp int;    -- expires at, unix epoch time in seconds UTC
  _custom int;
  result jwt_auth.jwt_claims;
begin
  select jwt_auth.user_role(email, pass, org) into _role;
  -- kick out if the password does not match
  if _role is null then
    raise invalid_password using message = 'invalid user/password/org combo';
  end if;
  -- TODO; check verified flag if you care whether users have validated emails
  -- now build and return additional claims
  select 0 into _v;
  select extract(epoch from now()) into _iat;
  -- set token to expire in 24 hours
  select ( _iat + 86400) into _exp;
  select custom from jwt_auth.users
    where users.email = login.email
      and users.org = login.org into _custom;

  select _role as role,
         login.email as email,
         login.org as org,
         _v as v,
         _iat as iat,
         _exp as exp,
        _custom as custom
            into result;
  return result;
end;
$$;

-------------------------------------------------------------------------------
-- User management

create or replace view users as
select actual.role as role,
       '***'::text as pass,
       actual.email as email,
       actual.verified as verified
from jwt_auth.users as actual,
     (select rolname
        from pg_authid
       where pg_has_role(current_user, oid, 'member')
     ) as member_of
where actual.role = member_of.rolname
  and (
    actual.role <> 'authorized'
    or email = jwt_auth.current_email()
  );


-------------------------------------------------------------------------------
-- Permissions

grant select on table pg_authid, jwt_auth.users to anon;
grant execute on function
  login(text,text,text)
  to anon;

grant select, insert, update, delete
  on jwt_auth.users to anon, authorized;

grant usage on schema public, jwt_auth to anon, authorized;
