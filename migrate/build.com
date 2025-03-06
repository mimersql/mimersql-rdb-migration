$! Run SQL Translator, Embedded SQL pre-processor, and build the Cobol programs
$! The SQL Translator will convert the Rdb .SCO files to Mimer SQL .ECO files
$! The .ECO files will be the new main source where further development will be done
$! If no program name is give as the first parameter, build all files
$ DEFINE PGCOCA$LIB "SYS$DISK:[]"
$ BUILD_DIR = "[.build]"
$ NEW_SRC_DIR = "[.new_source]"
$ WRITE SYS$OUTPUT "Convert, compile and link Cobol programs"
$ WRITE SYS$OUTPUT ""
$ CUR_DIR = "SYS$DISK:[]"
$! Create build directory for intermediate files
$ IF F$PARSE(BUILD_DIR,"","DIRECTORY") .EQS. "" THEN CRE/DIR 'BUILD_DIR'
$! Create directory to hold the new .ECO files. These are the new main source
$ IF F$PARSE(NEW_SRC_DIR,"","DIRECTORY") .EQS. "" THEN CRE/DIR 'NEW_SRC_DIR'
$!
$ WRITE SYS$OUTPUT "Convert the Rdb .SCO files to Mimer SQL .ECO file and build the programs"
$ WRITE SYS$OUTPUT "The new .ECO files are located in ''NEW_SRC_DIR' and are the new main source"
$ WRITE SYS$OUTPUT ""
$! Define the list of files to process
$ IF  P1 .nes. ""
$   THEN PROG_LIST = "''P1',"
$ ELSE
$   WRITE SYS$OUTPUT "Give a list programs without extension as parameter one, for example PROG1,PROG2,PROG2"
$   EXIT 1
$ ENDIF
$! Set debug mode
$ IF  P2 .eqs. "DEBUG"
$ THEN
$   WRITE SYS$OUTPUT "Using debug"
$   COBFLAG="DEBUG=ALL/NOOPTIMIZE/"
$   LNKFLAG="DEBUG/"
$ ELSE
$   LNKFLAG=""
$   COBFLAG=""
$ ENDIF
$! Initialize index for the loop
$ INDEX = 0
$! Loop over each file in the list
$ LOOP:
$   PROG_FILE = F$ELEMENT(INDEX, ",", PROG_LIST)
$   IF (PROG_FILE .EQS. "") .OR. (PROG_FILE .EQS. ",") THEN GOTO END_LOOP
$   INDEX = INDEX + 1
$   PROG_FILE_ECO = PROG_FILE + ".eco"
$   PROG_FILE_COB = PROG_FILE + ".cob"
$   PROG_FILE_SCO = PROG_FILE + ".sco"
$   PROG_FILE_OBJ = PROG_FILE + ".OBJ"
$   WRITE SYS$OUTPUT "Converting ''PROG_FILE_SCO' to ''NEW_SRC_DIR'''PROG_FILE_ECO' and build ''BUILD_DIR'''PROG_FILE'"
$   sqltranslator/rdb/cobol/nologo/format=terminaL 'PROG_FILE_SCO' 'NEW_SRC_DIR''PROG_FILE_ECO'
$   esql/cobol/nologo/format=terminal 'NEW_SRC_DIR''PROG_FILE_ECO' 'BUILD_DIR''PROG_FILE_COB'
$   cobol/'COBFLAG'noansi/include='CUR_DIR'/object='BUILD_DIR''PROG_FILE_OBJ' 'BUILD_DIR''PROG_FILE_COB'
$   link/'LNKFLAG'EXECUTABLE='BUILD_DIR''PROG_FILE' 'BUILD_DIR''PROG_FILE_OBJ',mimer$lib:mimer$sql/opt
$   GOTO LOOP
$ END_LOOP:
$ WRITE SYS$OUTPUT ""
$
