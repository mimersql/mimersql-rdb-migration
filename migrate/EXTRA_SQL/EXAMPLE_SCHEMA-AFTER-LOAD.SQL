set echo off;
set output off;
-- Do operations that should be done after loading of data, for example adding
-- triggers and foreign keys we dropped before load.
-- alter table my_tab add constraint my_tab_fk foregin key (colx) references my_ref_tab (colx);
-- @
-- create trigger my_trigger
-- before insert on my_table
-- referencing new row as new
-- for each row
-- begin atomic  
--     if new.colx = '<unknown>' then
--         signal sqlstate 'UE111';
--     end if;
-- end
-- @
