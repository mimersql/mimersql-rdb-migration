$! Create schemas in Mimer SQL and load data
$!
$ MIMER_USER = "mimeruser"
$ MIMER_PASS = "gB7Xd92jLmWZ"
$ SYSPASS=""
$ OPERATION="ALL"
$ CLEAN="NO"
$ LOAD_LOG_STDERR="YES"
$ DATABANK_FILE=""
$ IF  P1 .nes. ""
$   THEN SYSPASS="''P1'"
$ ELSE
$   WRITE SYS$OUTPUT "Enter SYSADM password"
$   READ/TIMEOUT=20/PROMPT="Password: " SYS$COMMAND SYSPASS
$   IF SYSPASS .eqs. ""
$   THEN
$       WRITE SYS$OUTPUT "Timeout or empty password. Aborting"
$       EXIT 4
$   ENDIF
$ ENDIF
$
$ IF  P2 .nes. ""
$   THEN SCHEMA="''P2'"
$ ELSE
$   WRITE SYS$OUTPUT "Specify database schema to load into as parameter two"
$   EXIT 4
$ ENDIF
$ IF  P3 .nes. ""
$   THEN MIMER_USER="''P3'"
$ ENDIF
$ IF  P4 .nes. ""
$   THEN MIMER_PASS="''P4'"
$ ENDIF
$ IF  P5 .nes. ""
$   THEN OPERATION="''P5'"
$ ENDIF
$ IF  P6 .eqs. "DELETE"
$   THEN CLEAN="YES"
$ ENDIF
$ IF  P7 .nes. ""
$   THEN DATABANK_FILE="''P7'"
$ ELSE
$   DATABANK_FILE=''SCHEMA'_DB
$ ENDIF
$
$! Check that Mimer SQL is installed and started
$ CALL CHECK_MIMER
$
$! Check export directory
$ TABLE_DEFS = "[.UNLOAD_DATA]''SCHEMA'-TABLES-MIMER.TXT"
$ WRITE SYS$OUTPUT "Checking directory and files"
$ IF F$PARSE("[.UNLOAD_DATA]","","DIRECTORY") .EQS. ""
$ THEN
$   WRITE SYS$OUTPUT "There is no unloaded data to load, i.e., there is no directory [.UNLOAD_DATA]"
$   WRITE SYS$OUTPUT "present."
$   WRITE SYS$OUTPUT ""
$   WRITE SYS$OUTPUT "To unload data from an Rdb system you must first runt the command procedure"
$   WRITE SYS$OUTPUT "unload_rdb.com. It will create a directory [.UNLOAD_DATA] with all content"
$   WRITE SYS$OUTPUT "and information from Rdb required to perform a load into Mimer SQL. If the"
$   WRITE SYS$OUTPUT "unload was done on a different system, you must first transfer this directory"
$   WRITE SYS$OUTPUT "with all content to the system with Mimer SQL, before attempting a load."
$   EXIT 4
$ ELSE
$   TMP = F$SEARCH("[.UNLOAD_DATA]''SCHEMA'-SCHEMA-RDB.SQL")
$   IF TMP .EQS. ""
$   THEN
$       WRITE SYS$OUTPUT "[.UNLOAD_DATA]''SCHEMA'-SCHEMA-RDB.SQL not found"
$       EXIT 4
$   ENDIF
$ ENDIF
$ WRITE SYS$OUTPUT "Check done"
$
$ IF  OPERATION .EQS. "LOAD"
$   THEN GOTO LOAD_DATA
$ ENDIF
$ IF  OPERATION .EQS. "CONTINUE_LOAD"
$   THEN GOTO CONTINUE_LOAD
$ ENDIF
$! Create directory for log files or clear it if it exists
$ IF F$PARSE("[.LOG]","","DIRECTORY") .EQS. ""
$ THEN
$   CRE/DIR [.LOG]
$ ELSE
$   TMP = F$SEARCH("[.LOG]''SCHEMA'*.*;*")
$   IF TMP .NES. "" THEN DELETE [.LOG]'SCHEMA'*.*;*
$   TMP = F$SEARCH("[.LOG]*_''SCHEMA'*.*;*")
$   IF TMP .NES. "" THEN DELETE [.LOG]*_'SCHEMA'*.*;*
$ ENDIF
$! Create directory for generated files if it doesn't exist
$ IF F$PARSE("[.GEN_SQL]","","DIRECTORY") .EQS. ""
$ THEN
$   CRE/DIR [.GEN_SQL]
$ ELSE
$   TMP = F$SEARCH("[.GEN_SQL]''SCHEMA'-*.*;*")
$   IF TMP .NES. "" THEN DELETE [.GEN_SQL]'SCHEMA'-*.*;*
$   TMP = F$SEARCH("[.GEN_SQL]''SCHEMA'_*.*;*")
$   IF TMP .NES. "" THEN DELETE [.GEN_SQL]'SCHEMA'_*.*;*
$   TMP = F$SEARCH("[.GEN_SQL]*_''SCHEMA'.*;*")
$   IF TMP .NES. "" THEN DELETE [.GEN_SQL]*_'SCHEMA'*.*;*
$ ENDIF
$! Add Mimer SQL version information to main log file
$ define/user sys$output [.LOG]'SCHEMA'_MIMINFO.LOG
$ MIMINFO/VERSION
$! Create schema
$!
$! Translate the Rdb SQL dialect to Mimer SQL
$ WRITE SYS$OUTPUT "Translating database schema from Rdb to Mimer SQL, result in [.GEN_SQL]"
$ sqltranslator/rdb/script/nologo [.UNLOAD_DATA]'SCHEMA'-SCHEMA-RDB.SQL [.GEN_SQL]'SCHEMA'-SCHEMA-MIMER.SQL
$ WRITE SYS$OUTPUT "Creating database user and databank, log result to [.LOG]CREATE_USERS_''SCHEMA'.LOG"
$ OS_USER = "'" + f$edit(f$getjpi("","USERNAME"),"TRIM") + "'"
$ OPEN/WRITE OUTFILE [.GEN_SQL]CREATE_USERS_'SCHEMA'.SQL
$ WRITE OUTFILE "log input,output on '[.LOG]CREATE_USERS_''SCHEMA'.LOG';"
$ WRITE OUTFILE "WHENEVER ERROR CONTINUE;"
$ WRITE OUTFILE "create ident ''MIMER_USER' as user identified by '" + MIMER_PASS +"';"
$ WRITE OUTFILE "drop databank ''SCHEMA'_DB cascade;"
$ WRITE OUTFILE "alter ident ''MIMER_USER' add os_user ''OS_USER';"
$ WRITE OUTFILE "WHENEVER ERROR EXIT;"
$ WRITE OUTFILE "create databank ''SCHEMA'_DB IN '" + DATABANK_FILE +"';"
$ WRITE OUTFILE "grant schema to ''MIMER_USER';"
$ WRITE OUTFILE "grant table on ''SCHEMA'_DB to ''MIMER_USER';"
$ WRITE OUTFILE "grant sequence on ''SCHEMA'_DB to ''MIMER_USER';"
$ WRITE OUTFILE "EXIT;"
$ CLOSE OUTFILE
$ define/user sys$output [.LOG]'SCHEMA'_OUTPUT.LOG
$ bsql/username=SYSADM/password="''SYSPASS'"/query="read '[.GEN_SQL]CREATE_USERS_''SCHEMA'.SQL'"
$ WRITE SYS$OUTPUT "Creating ''SCHEMA' schema, log result to [.LOG]CREATE_SCHEMA_''SCHEMA'.LOG"
$ OPEN/WRITE OUTFILE [.GEN_SQL]create_schema_'SCHEMA'.SQL
$ WRITE OUTFILE "log input,output on '[.LOG]CREATE_SCHEMA_''SCHEMA'.LOG';"
$ WRITE OUTFILE "WHENEVER ERROR CONTINUE;"
$ WRITE OUTFILE "drop schema ''SCHEMA' cascade;"
$ WRITE OUTFILE "WHENEVER ERROR EXIT;"
$ WRITE OUTFILE "create schema ''SCHEMA';"
$ WRITE OUTFILE "set schema ''SCHEMA';"
$ WRITE OUTFILE "WHENEVER ERROR CONTINUE;"
$ WRITE OUTFILE "read '[.GEN_SQL]" + SCHEMA + "-SCHEMA-MIMER.SQL';"
$ WRITE OUTFILE "EXIT;"
$ CLOSE OUTFILE
$ define/user sys$output [.LOG]'SCHEMA'_OUTPUT.LOG
$ bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="read '[.GEN_SQL]CREATE_SCHEMA_''SCHEMA'.SQL'"
$ !Update statistics for SYSTEM
$ WRITE SYS$OUTPUT "Update statistics for SYSTEM"
$ bsql/username=SYSADM/password="''SYSPASS'"/query="update statistics for ident SYSTEM"
$ WRITE SYS$OUTPUT "Database schemas created"
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "Analyzing database, store results in [.GEN_SQL]''SCHEMA'_ANALYZED.SQL"
$ define/user sys$output [.GEN_SQL]'SCHEMA'_ANALYZED.SQL
$ dbanalyzer/username="''MIMER_USER'"/password="''MIMER_PASS'"/schema="''SCHEMA'"
$ WRITE SYS$OUTPUT "Optimizing database, log results to [.LOG]''SCHEMA'_ANALYZED.LOG"
$ OPEN/WRITE OUTFILE [.GEN_SQL]ANALYZE_SCHEMA_'SCHEMA'.SQL
$ WRITE OUTFILE "log input,output on '[.LOG]ANALYZE_SCHEMA_''SCHEMA'.LOG';"
$ WRITE OUTFILE "WHENEVER ERROR CONTINUE;"
$ WRITE OUTFILE "read '[.GEN_SQL]" + SCHEMA + "_ANALYZED.SQL';"
$ WRITE OUTFILE "EXIT;"
$ CLOSE OUTFILE
$ define/user sys$output [.LOG]'SCHEMA'_ANALYZED.LOG
$ bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="read '[.GEN_SQL]ANALYZE_SCHEMA_''SCHEMA'.SQL'"
$ TMP = F$SEARCH("[.EXTRA_SQL]''SCHEMA'-AFTER-CREATE.SQL")
$ IF TMP .NES. ""
$ THEN
$     WRITE SYS$OUTPUT "Executing extra SQL after create schema in [.EXTRA_SQL]''SCHEMA'-AFTER-CREATE.SQL"
$     WRITE SYS$OUTPUT "Log operations to [.LOG]''SCHEMA'-AFTER-CREATE-SQL.LOG"
$     OPEN/WRITE OUTFILE [.GEN_SQL]'SCHEMA'-AFTER-CREATE-SQL.SQL
$     WRITE OUTFILE "log input,output on '[.LOG]" + SCHEMA + "-AFTER-CREATE-SQL.LOG';"
$     WRITE OUTFILE "set output off;"
$     WRITE OUTFILE "set schema ''SCHEMA';"
$     WRITE OUTFILE "read '[.EXTRA_SQL]" + "''SCHEMA'-AFTER-CREATE.SQL';"
$     CLOSE OUTFILE
$     define/user sys$output [.LOG]'SCHEMA'-AFTER-CREATE-OUTPUT.LOG
$     bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="read '[.GEN_SQL]''SCHEMA'-AFTER-CREATE-SQL.SQL'"
$ ENDIF
$ TMP = F$SEARCH("[.EXTRA_SQL]''SCHEMA'-SYSTEM-AFTER-CREATE.SQL")
$ IF TMP .NES. ""
$ THEN
$     WRITE SYS$OUTPUT "Executing extra SQL as SYSADM user after create schema in [.EXTRA_SQL]''SCHEMA'-SYSTEM-AFTER-CREATE.SQL"
$     WRITE SYS$OUTPUT "Log operations to [.LOG]''SCHEMA'-SYSTEM-AFTER-CREATE-SQL.LOG"
$     OPEN/WRITE OUTFILE [.GEN_SQL]'SCHEMA'-SYSTEM-AFTER-CREATE-SQL.SQL
$     WRITE OUTFILE "log input,output on '[.LOG]" + SCHEMA + "-SYSTEM-AFTER-CREATE-SQL.LOG';"
$     WRITE OUTFILE "set output off;"
$     WRITE OUTFILE "read '[.EXTRA_SQL]" + "''SCHEMA'-SYSTEM-AFTER-CREATE.SQL';"
$     CLOSE OUTFILE
$     define/user sys$output [.LOG]'SCHEMA'-SYSTEM-AFTER-CREATE-OUTPUT.LOG
$     bsql/username=SYSADM/password="''SYSPASS'"/query="read '[.GEN_SQL]''SCHEMA'-SYSTEM-AFTER-CREATE-SQL.SQL'"
$ ENDIF
$ WRITE SYS$OUTPUT ""
$ IF  OPERATION .EQS. "CREATE"
$   THEN GOTO EXIT_OK
$ ENDIF
$ WRITE SYS$OUTPUT "Loading exported data into Mimer SQL"
$ WRITE SYS$OUTPUT "Log files for the load operations can be found in [.LOG]"
$ LOAD_DATA:
$   TMP = F$SEARCH("''TABLE_DEFS'")
$   IF TMP .NES. ""
$   THEN
$       DELETE 'TABLE_DEFS';*
$   ENDIF
$ WRITE SYS$OUTPUT "Retreiving tables to load"
$! Load tables in correct order so we don't violate foreign key constraints
$ OPEN/WRITE OUTFILE [.GEN_SQL]GET_TABLES_'SCHEMA'.SQL
$ WRITE OUTFILE "log output on '" + "''TABLE_DEFS'" + "';"
$ WRITE OUTFILE "set silence on;"
$ WRITE OUTFILE "select object_name from system.objects where object_type = 'BASE TABLE' "
$ WRITE OUTFILE "and object_schema = '" + SCHEMA + "' order by coalesce(object_altered, object_created);"
$ CLOSE OUTFILE
$ define/user sys$output [.LOG]get_tables_'SCHEMA'.LOG
$ bsql/username=SYSADM/password="''SYSPASS'"/query="read '[.GEN_SQL]GET_TABLES_''SCHEMA'.SQL'"
$ CONTINUE_LOAD:
$! Run any extra SQL before loading data
$ TMP = F$SEARCH("[.EXTRA_SQL]''SCHEMA'-BEFORE-LOAD.SQL")
$ IF TMP .NES. ""
$ THEN
$     WRITE SYS$OUTPUT "Executing extra SQL before load in [.EXTRA_SQL]''SCHEMA'-BEFORE-LOAD.SQL"
$     WRITE SYS$OUTPUT "Log operations to [.LOG]''SCHEMA'-BEFORE-LOAD-SQL.LOG"
$     OPEN/WRITE OUTFILE [.GEN_SQL]'SCHEMA'-BEFORE-LOAD-SQL.SQL
$     WRITE OUTFILE "log input,output on '[.LOG]" + SCHEMA + "-BEFORE-LOAD-SQL.LOG';"
$     WRITE OUTFILE "set output off;"
$     WRITE OUTFILE "set schema ''SCHEMA';"
$     WRITE OUTFILE "read '[.EXTRA_SQL]" + "''SCHEMA'-BEFORE-LOAD.SQL';"
$     CLOSE OUTFILE
$     define/user sys$output [.LOG]'SCHEMA'-BEFORE-LOAD-OUTPUT.LOG
$     bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="read '[.GEN_SQL]''SCHEMA'-BEFORE-LOAD-SQL.SQL'"
$ ENDIF
$ ! Open the file with tables
$ open/read table_file 'TABLE_DEFS'
$! In case the file was left open in an earlier attempt, close it and open it again
$ close table_file
$ open/read table_file 'TABLE_DEFS'
$ ! Loop over each line in the file
$ loop:
$   read/end_of_file=done table_file line
$   tab = f$edit(line, "TRIM")
$   IF tab .NES. ""
$   THEN
$       TMP = F$SEARCH("[.UNLOAD_DATA]''SCHEMA'-''tab'.TXT")
$       IF TMP .NES. ""
$       THEN
$           IF CLEAN .EQS. "YES"
$           THEN
$               write sys$output "Cleaning tab ''SCHEMA'.''tab'"
$               define/user sys$output [.LOG]'SCHEMA'_OUTPUT.LOG
$               bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="delete from ''SCHEMA'.''tab'"
$           ENDIF
$           write sys$output "Loading ''SCHEMA'.''tab'"
$           IF LOAD_LOG_STDERR .EQS. "YES"
$           THEN
$               LOAD_CMD = """" + "load from 'DELIM.DAT', '[.UNLOAD_DATA]" + SCHEMA + "-" + tab + ".TXT' as LATIN1 log stderr with bulk load insert into " + SCHEMA + "." + tab + """"
$           ELSE
$               LOAD_CMD = """" + "load from 'DELIM.DAT', '[.UNLOAD_DATA]" + SCHEMA + "-" + tab + ".TXT' as LATIN1 log '[.LOG]LOAD_" + SCHEMA + "-" + tab + ".LOG' with bulk load insert into " + SCHEMA + "." + tab + """"
$           ENDIF
$           START = F$CVTIME(,"ABSOLUTE")
$           mimload/user="''MIMER_USER'"/password="''MIMER_PASS'" 'LOAD_CMD'
$!       ELSE
$!           WRITE SYS$OUTPUT "Skipping ''tab'"
$       ENDIF
$   ENDIF
$   goto loop
$
$ ! Close the file and exit
$ done:
$   close table_file
$
$ WRITE SYS$OUTPUT ""
$
$ TMP = F$SEARCH("[.EXTRA_SQL]''SCHEMA'-AFTER-LOAD.SQL")
$ IF TMP .NES. ""
$ THEN
$     WRITE SYS$OUTPUT "Executing extra SQL after load in [.EXTRA_SQL]''SCHEMA'-AFTER-LOAD.SQL"
$     WRITE SYS$OUTPUT "Log operations to [.LOG]''SCHEMA'-AFTER-LOAD-SQL.LOG"
$     OPEN/WRITE OUTFILE [.GEN_SQL]'SCHEMA'-AFTER-LOAD-SQL.SQL
$     WRITE OUTFILE "log input,output on '[.LOG]" + SCHEMA + "-AFTER-LOAD-SQL.LOG';"
$     WRITE OUTFILE "set output off;"
$     WRITE OUTFILE "set schema ''SCHEMA';"
$     WRITE OUTFILE "read '[.EXTRA_SQL]" + "''SCHEMA'-AFTER-LOAD.SQL';"
$     CLOSE OUTFILE
$     define/user sys$output [.LOG]'SCHEMA'-AFTER-LOAD-OUTPUT.LOG
$     bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="read '[.GEN_SQL]''SCHEMA'-AFTER-LOAD-SQL.SQL'"
$ ENDIF
$ WRITE SYS$OUTPUT "Updating statistics"
$ bsql/username=SYSADM/password="''SYSPASS'"/query="update statistics for ident SYSTEM"
$ bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="update statistics for schema ''SCHEMA'"
$ WRITE SYS$OUTPUT "Finished loading data into Mimer SQL using the database user ''MIMER_USER' and database schema ''SCHEMA'"
$ EXIT_OK:
$ EXIT
$
$! Checks that the Mimer SQL environment is correct
$ CHECK_MIMER: SUBROUTINE
$ IF ''F$TRNLNM("MIMER_DATABASE")' .EQS. ""
$ THEN
$   WRITE SYS$OUTPUT "MIMER_DATABASE not defined"
$   GOTO EXIT_ERR
$ ENDIF
$ WRITE SYS$OUTPUT "Using Mimer SQL database ''F$TRNLNM("MIMER_DATABASE")'. Mimer SQL version information:"
$ MIMINFO/VERSION
$ MIMCONTROL/STATUS/DCL
$ IF F$ELEMENT(0,",",MIMER_STATUS) .NES. "Running"
$ THEN
$   WRITE SYS$OUTPUT "Mimer SQL is not running"
$   GOTO EXIT_ERR
$ ENDIF
$ WRITE SYS$OUTPUT "Mimer SQL environment is ok"
$ WRITE SYS$OUTPUT ""
$ EXIT 1
$!
$ EXIT_ERR:
$ WRITE SYS$OUTPUT "Mimer SQL environment error"
$ EXIT 4
$ ENDSUBROUTINE
