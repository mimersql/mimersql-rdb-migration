set echo off;
set output off;
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
