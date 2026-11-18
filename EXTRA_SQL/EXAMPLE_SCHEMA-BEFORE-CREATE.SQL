set echo off;
set output off;
-- Do operations that should be done before the translated schema is read, for example
-- creating objects that could not be translated automatically and that are used in many
-- places later in the schema, like domains.
-- create domain my_name_domain as varchar(30) default '' check (value is not null);
