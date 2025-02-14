$ IF  P1 .nes. ""
$   THEN DB="''P1'" 
$ ELSE
$   WRITE SYS$OUTPUT "Specify database path as parameter one"
$   EXIT 4
$ ENDIF
$ IF  P2 .nes. ""
$   THEN DBNAME="''P2'" 
$ ELSE
$   WRITE SYS$OUTPUT "Specify database used as parameter one"
$   WRITE SYS$OUTPUT "This will be used as schema in Mimer SQL"
$   EXIT 4
$ ENDIF
$ WRITE SYS$OUTPUT "Checking directory and files"
$ IF F$PARSE("[.unload_data]","","DIRECTORY") .EQS. ""
$ THEN
$   WRITE SYS$OUTPUT "Creating [.unload_data] directory"
$   CRE/DIR [.unload_data]
$ ELSE
$   TMP = F$SEARCH("[.unload_data]''DBNAME'-TABLES.TXT")
$   IF TMP .NES. ""
$   THEN
$       WRITE SYS$OUTPUT "Deleting [.unload_data]''DBNAME'-TABLES.TXT"
$       DELETE [.unload_data]'DBNAME'-TABLES.TXT;*
$   ENDIF
$ ENDIF
$ WRITE SYS$OUTPUT "Check done"
$ DEFINE/NOLOG EXPORT_DB 'DB'
$ TABLE_DEFS = "[.unload_data]''DBNAME'-TABLES.TXT"
$ 
$ WRITE SYS$OUTPUT "Extracting database schema"
$ RMU/EXTRACT/Output=[.unload_data]'DBNAME'-SCHEMA-RDB.SQL 'DB'
$ define/user sys$output 'TABLE_DEFS'
$run sql$
attach 'f EXPORT_DB';
set heading off;
set feedback off;
SELECT trim(rdb$relation_name) FROM RDB$RELATIONS where RDB$RELATION_NAME NOT LIKE 'RDB$%' and RDB$CARDINALITY > 0;
EXIT;
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "Fetched table names from ''DB' into ''TABLE_DEFS'"
$ ! Unload data
$
$ ! Open the file for reading
$ open/read input_chan 'TABLE_DEFS'
$
$ ! Loop over each line in the file
$ loop:
$   read/end_of_file=done input_chan line
$   tab = f$edit(line, "TRIM")
$   write sys$output "Unloading ''tab'"
$   rmu/unload/RECORD_DEFINITION=(FORMAT=DELIMITED_TEXT, PREFIX="", SUFFIX="", separator="|", null="\-") 'DB' 'tab' [.unload_data]'DBNAME'-'tab'.txt
$   goto loop
$
$ ! Close the file and exit
$ done:
$   close input_chan
$   exit