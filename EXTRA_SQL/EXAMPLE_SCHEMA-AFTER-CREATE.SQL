set echo off;
set output off;
-- Do operations that should be done after creation of the schema like manual optimizations
-- As an example, if we have a table without primary key but with a unique index and you know
-- there are no columns with NULL then you can replace the unique index with a primary key
-- defined on the same columns
-- drop index my_unique_dix
-- alter table my_tab add constraint my_tab_pk primary key(col1,col2);