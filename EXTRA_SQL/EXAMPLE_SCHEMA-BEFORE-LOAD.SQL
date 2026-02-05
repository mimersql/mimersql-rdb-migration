set echo off;
set output off;
-- Do operations that should be done before loading of data, for example dropping
-- triggers and foreign key constraint that we create again after load.
-- alter table my_tab drop constraint my_tab_fk;
-- drop trigger my_trigger;
