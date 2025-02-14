$! Create schemas in Mimer SQL and load data
$!
$ MIMER_USER = "mimeruser"
$ MIMER_PASS = "mimerpass"
$ IF  P1 .nes. ""
$   THEN SYSPASS="''P1'" 
$ ELSE
$   SYSPASS=""
$   WRITE SYS$OUTPUT "Enter SYSADM password"
$   READ/TIMEOUT=20/PROMPT="Password: " SYS$COMMAND SYSPASS
$   IF SYSPASS .eqs. ""
$   THEN
$       WRITE SYS$OUTPUT "Timeout or empty password, using default SYSADM password"
$       SYSPASS="SYSADM"
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
$! Check export directory
$ WRITE SYS$OUTPUT "Checking directory and files"
$ IF F$PARSE("[.unload_data]","","DIRECTORY") .EQS. ""
$ THEN
$   WRITE SYS$OUTPUT "The directory [.unload_data] with unloaded data not found"
$   WRITE SYS$OUTPUT "Run @unload_rdb on the machine that have Rdb first."
$   WRITE SYS$OUTPUT "If different machines are being used, transer the [.unload_data]"
$   WRITE SYS$OUTPUT "directory to the machine running Mimer SQL."
$   EXIT 4
$ ELSE
$   TMP = F$SEARCH("[.unload_data]''SCHEMA'-TABLES.TXT")
$   IF TMP .EQS. ""
$   THEN
$       WRITE SYS$OUTPUT "[.unload_data]''SCHEMA'-TABLES.TXT not found"
$       EXIT 4
$   ENDIF
$   TMP = F$SEARCH("[.unload_data]''SCHEMA'-SCHEMA-RDB.SQL")
$   IF TMP .EQS. ""
$   THEN
$       WRITE SYS$OUTPUT "[.unload_data]''SCHEMA'-SCHEMA-RDB.SQL not found"
$       EXIT 4
$   ENDIF
$ ENDIF
$ WRITE SYS$OUTPUT "Check done"
$ TABLE_DEFS = "[.unload_data]''SCHEMA'-TABLES.TXT"
$
$! Create directory for log files or clear it if it exists
$ IF F$PARSE("[.log]","","DIRECTORY") .EQS. ""
$ THEN
$   CRE/DIR [.log]
$ ELSE
$   TMP = F$SEARCH("[.log]*.*;*")
$   IF TMP .NES. "" THEN DELETE [.log]*.*;*
$ ENDIF
$! Create directory for generated files scripts or clear it if it exists
$ IF F$PARSE("[.gen_sql]","","DIRECTORY") .EQS. ""
$ THEN
$   CRE/DIR [.gen_sql]
$ ELSE
$   TMP = F$SEARCH("[.gen_sql]*.*;*")
$!   IF TMP .NES. "" THEN DELETE [.gen_sql]*.*;*
$ ENDIF
$! Create schema
$!
$! Translate the Rdb SQL dialect to Mimer SQL
$ WRITE SYS$OUTPUT "Translating database schema from Rdb to Mimer SQL, result in [.gen_sql]"
$ sqltranslator/rdb/script/nologo [.unload_data]'SCHEMA'-SCHEMA-RDB.SQL [.gen_sql]'SCHEMA'-SCHEMA-MIMER.SQL
$ WRITE SYS$OUTPUT "Creating database user and databank, log result to [.log]create_users_''SCHEMA'.log"
$ OS_USER = "'" + f$edit(f$getjpi("","USERNAME"),"TRIM") + "'"
$ OPEN/WRITE OUTFILE [.gen_sql]create_users_'SCHEMA'.sql
$ WRITE OUTFILE "log input,output on '[.log]create_users_''SCHEMA'.log';"
$ WRITE OUTFILE "WHENEVER ERROR CONTINUE;"
$ WRITE OUTFILE "create ident ''MIMER_USER' as user identified by '" + MIMER_PASS +"';"
$ WRITE OUTFILE "drop databank ''SCHEMA'_DB cascade;"
$ WRITE OUTFILE "alter ident ''MIMER_USER' add os_user ''OS_USER'"
$ WRITE OUTFILE "WHENEVER ERROR EXIT;"
$ WRITE OUTFILE "create databank ''SCHEMA'_DB;"
$ WRITE OUTFILE "grant schema to ''MIMER_USER';"
$ WRITE OUTFILE "grant table on ''SCHEMA'_DB to ''MIMER_USER';"
$ WRITE OUTFILE "grant sequence on ''SCHEMA'_DB to ''MIMER_USER';"
$ WRITE OUTFILE "EXIT;"
$ CLOSE OUTFILE
$ define/user sys$output [.log]tmp_output.log
$ bsql/username=SYSADM/password="''SYSPASS'"/query="read '[.gen_sql]create_users_''SCHEMA'.sql'"
$ WRITE SYS$OUTPUT "Creating ''SCHEMA' schema, log result to [.log]create_schema_''SCHEMA'.log"
$ OPEN/WRITE OUTFILE [.gen_sql]create_schema_'SCHEMA'.sql
$ WRITE OUTFILE "log input,output on '[.log]create_schema_''SCHEMA'.log';"
$ WRITE OUTFILE "WHENEVER ERROR CONTINUE;"
$ WRITE OUTFILE "drop schema ''SCHEMA' cascade;"
$ WRITE OUTFILE "WHENEVER ERROR EXIT;"
$ WRITE OUTFILE "create schema ''SCHEMA';"
$ WRITE OUTFILE "set schema ''SCHEMA';"
$ WRITE OUTFILE "WHENEVER ERROR CONTINUE;"
$ WRITE OUTFILE "read '[.gen_sql]" + SCHEMA + "-SCHEMA-MIMER.SQL';"
$ WRITE OUTFILE "EXIT;"
$ CLOSE OUTFILE
$ define/user sys$output [.log]tmp_output.log
$ bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="read '[.gen_sql]create_schema_''SCHEMA'.sql'"
$ !Update statistics for SYSTEM
$ WRITE SYS$OUTPUT "Update statistics for SYSTEM"
$ bsql/username=SYSADM/password="''SYSPASS'"/query="update statistics for ident SYSTEM"
$ WRITE SYS$OUTPUT "Database schemas created"
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "Analyzing database, store results in [.gen_sql]''SCHEMA'_analyze.sql"
$ define/user sys$output [.gen_sql]'SCHEMA'_analyze.sql
$ dbanalyzer/username="''MIMER_USER'"/password="''MIMER_PASS'"
$ WRITE SYS$OUTPUT "Optimizing database, log results to [.log]''SCHEMA'_analyze.log"
$ OPEN/WRITE OUTFILE [.gen_sql]analyze_schema_'SCHEMA'.sql
$ WRITE OUTFILE "log input,output on '[.log]analyze_schema_''SCHEMA'.log';"
$ WRITE OUTFILE "WHENEVER ERROR CONTINUE;"
$ WRITE OUTFILE "read '[.gen_sql]" + SCHEMA + "_analyze.sql';"
$ WRITE OUTFILE "EXIT;"
$ CLOSE OUTFILE
$ define/user sys$output [.log]'SCHEMA'_analyze.log
$ bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="read '[.gen_sql]analyze_schema_''SCHEMA'.sql'"
$ WRITE SYS$OUTPUT ""
$ WRITE SYS$OUTPUT "Loading exported data into Mimer SQL"
$! Load tables in correct order so we don't violate foreign key constraints
$ OPEN/WRITE OUTFILE [.gen_sql]get_tables_'SCHEMA'.sql
$ WRITE SYS$OUTPUT "Log files for the load operations can be found in [.log]"
$ WRITE OUTFILE "log output on '[.unload_data]get_tables_''SCHEMA'.txt';"
$ WRITE OUTFILE "set silence on;"
$ WRITE OUTFILE "select object_name from system.objects where object_type = 'BASE TABLE' "
$ WRITE OUTFILE "and object_schema = '" + SCHEMA + "' order by coalesce(object_altered, object_created);"
$ CLOSE OUTFILE
$ define/user sys$output [.log]get_tables_'SCHEMA'.log
$ bsql/username=SYSADM/password="''SYSPASS'"/query="read '[.gen_sql]get_tables_''SCHEMA'.sql'"
$!
$ ! Open the file with tables
$ open/read table_file [.unload_data]get_tables_'SCHEMA'.txt
$
$ ! Loop over each line in the file
$ loop:
$   read/end_of_file=done table_file line
$   tab = f$edit(line, "TRIM")
$   IF tab .NES. ""
$   THEN
$       TMP = F$SEARCH("[.unload_data]''SCHEMA'-''tab'.TXT")
$       IF TMP .NES. ""
$       THEN
$           write sys$output "Loading ''tab'"
$           LOAD_CMD = """" + "load from 'delim.dat', '[.unload_data]" + SCHEMA + "-" + tab + ".txt' as LATIN1 log '[.log]LOAD_" + SCHEMA + "-" + tab + ".log' insert into " + SCHEMA + "." + tab + """"
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
$ WRITE SYS$OUTPUT "Updating statitics"
$ bsql/username=SYSADM/password="''SYSPASS'"/query="update statistics for ident SYSTEM"
$ bsql/username="''MIMER_USER'"/password="''MIMER_PASS'"/query="update statistics for schema cierren"
$ WRITE SYS$OUTPUT "Finished loading data into Mimer SQL using the database user ''MIMER_USER' and database schema ''SCHEMA'"
$ WRITE SYS$OUTPUT "The password for the ''MIMER_USER' can be changed with the SQL statement ""alter ident ''MIMER_USER' identified by '<new password>'"""
