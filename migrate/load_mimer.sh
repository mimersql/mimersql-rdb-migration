#!/bin/bash
# Create schemas in Mimer SQL and load data

MIMER_USER="mimeruser"
MIMER_PASS="gB7Xd92jLmWZ"
SYSADM_PASS=""
ENCODING="latin1"
usage()
{
cat << EOF
usage: $0 options

Translate RDB schema, create schemas in Mimer SQL, optimize the database and load data

OPTIONS:
   -p      SYSADM password
   -s      Schema
   -u      Mimer SQL user, default is ${MIMER_USER}
   -P      Password for Mimer SQL user, default is ${MIMER_PASS}
   -e      Encoding of the input files, default is latin1
EOF
}

fix_vms_names()
{
# Declare associative arrays for latest versions
declare -A latest
declare -A latest_file

# List all files with version numbers
for file in ${1}; do
    # Extract base name (before the semicolon) and version number
    base_name="${file%%;*}"
    version="${file##*;}"
    
    # Skip files without a valid version part (e.g., FILE.TXT without ";<version>")
    if [[ "$base_name" == "$file" ]]; then
        continue
    fi
    
    # Check if version is numeric
    if [[ "$version" =~ ^[0-9]+$ ]]; then
        #echo "base_name: ${base_name}, version=${version}"
        # Store the latest version for each base name
        if [[ ! -v latest["${base_name}"] || ${version} -gt ${latest["${base_name}"]} ]]; then
            latest["$base_name"]=$version
            latest_file["$base_name"]=$file
        fi
    fi
done

# Process the latest files
for base_name in "${!latest_file[@]}"; do
    latest_version_file="${latest_file[$base_name]}"
    # Rename the latest version to the base name
    # Check if there is a version using lower case, and use that if so
    if [ -e ${base_name,,} ]; then
        mv "$latest_version_file" "${base_name,,}"
    else
        mv "$latest_version_file" "$base_name"
    fi
    rm -f ${base_name}\;*
done
}

# Checks that the Mimer SQL environment is correct
check_mimer()
{
    if ! command -v bsql &> /dev/null; then
        echo "Mimer SQL is not installed"
        exit 1
    fi

    if ! command -v sqltranslator &> /dev/null; then
        echo "SQL Translator is not installed"
        exit 1
    fi

    if [ "$MIMER_DATABASE" = "" ]; then
        echo "MIMER_DATABASE is not set"
        exit 1
    else
        echo "Using Mimer SQL database $MIMER_DATABASE"
    fi

    status=$(mimcontrol -c -b)
    if [[ $status != Running,* ]]; then
        echo "Mimer SQL is not running"
        exit 1
    fi
}


while getopts ":p:s:u:P:e:" OPTION
do
     case $OPTION in
         'p')
             SYSADM_PASS=${OPTARG}
             ;;
         's')
             SCHEMA=${OPTARG^^}
             ;;
         'u')
             MIMER_USER=${OPTARG}
             ;;
         'P')
            MIMER_PASS=${OPTARG}
             ;;
         'e')
            ENCODING=${OPTARG,,}
             ;;             
          ?)
             usage
             exit 0
             ;;
     esac
done

if [ "${SYSADM_PASS}" = "" ]; then
    echo "Enter SYSADM password: "
    read mim_env
fi

if [ "${SCHEMA}" = "" ]; then
    echo "Enter schema: "
    read SCHEMA
    SCHEMA=${SCHEMA^^}
fi


# Check that Mimer SQL is installed and started
check_mimer
fix_vms_names "./UNLOAD_DATA/*"
fix_vms_names "*"

# Check export directory
TABLE_DEFS="./UNLOAD_DATA/${SCHEMA}-TABLES-MIMER.TXT"
echo "Checking directory and files"
if [ ! -e ./UNLOAD_DATA ]; then
  echo "The directory ./UNLOAD_DATA/ with unloaded data not found"
  echo "Run @unload_rdb on the machine that have Rdb first."
  echo "If different machines are being used, transer the ./UNLOAD_DATA/"
  echo "directory to the machine running Mimer SQL."
  exit
else
  if [ -e ${TABLE_DEFS} ]; then
    rm ${TABLE_DEFS}
  fi
  if [ ! -e ./UNLOAD_DATA/${SCHEMA}-SCHEMA-RDB.SQL ]; then
    echo "./UNLOAD_DATA/${SCHEMA}-SCHEMA-RDB.SQL not found"
    exit
  fi
fi
echo "Check done"

# Create directory for log files or clear it if it exists
if [ ! -d ./LOG ]; then
  mkdir ./LOG
else
  rm -f ./LOG/*
fi
# Create directory for generated files scripts or clear it if it exists
if [ ! -d ./GEN_SQL ]; then
  mkdir ./GEN_SQL
else
  rm -f ./GEN_SQL/*
fi
# Create schema
#
# Translate the Rdb SQL dialect to Mimer SQL
echo "Translating database schema from Rdb to Mimer SQL, result in ./GEN_SQL"
sqltranslator --rdb --script --nologo --${ENCODING} ./UNLOAD_DATA/${SCHEMA}-SCHEMA-RDB.SQL ./GEN_SQL/${SCHEMA}-SCHEMA-MIMER.SQL
echo "Creating database user and databank, log result to ./LOG/CREATE_USERS_${SCHEMA}.LOG"
OS_USER=$USERNAME
echo "log input,output on './LOG/CREATE_USERS_${SCHEMA}.LOG';" > ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "WHENEVER ERROR CONTINUE;" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "create ident ${MIMER_USER} as user identified by '${MIMER_PASS}';" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "drop databank ${SCHEMA}_DB cascade;" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "alter ident ${MIMER_USER} add os_user '${OS_USER}';" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "WHENEVER ERROR EXIT;" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "create databank ${SCHEMA}_DB;" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "grant schema to ${MIMER_USER};" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "grant table on ${SCHEMA}_DB to ${MIMER_USER};" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "grant sequence on ${SCHEMA}_DB to ${MIMER_USER};">> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
echo "EXIT;" >> ./GEN_SQL/CREATE_USERS_${SCHEMA}.SQL
bsql --username=SYSADM --password=${SYSADM_PASS} --query="read './GEN_SQL/CREATE_USERS_${SCHEMA}.SQL'" ${MIMER_DATABASE} >> ./LOG/TMP_OUTPUT.LOG 2>&1

echo "Creating ${SCHEMA} schema, log result to ./LOG/CREATE_SCHEMA_${SCHEMA}.LOG"
echo "log input,output on './LOG/CREATE_SCHEMA_${SCHEMA}.LOG';" > ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
echo "WHENEVER ERROR CONTINUE;" >> ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
echo "drop schema ${SCHEMA} cascade;"  >> ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
echo "WHENEVER ERROR EXIT;"  >> ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
echo "create schema ${SCHEMA};"  >> ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
echo "set schema ${SCHEMA};"  >> ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
echo "WHENEVER ERROR CONTINUE;"  >> ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
echo "read './GEN_SQL/${SCHEMA}-SCHEMA-MIMER.SQL';"  >> ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
echo "EXIT;" >> ./GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL
bsql --username=${MIMER_USER} --password=${MIMER_PASS} --query="read './GEN_SQL/CREATE_SCHEMA_${SCHEMA}.SQL'" ${MIMER_DATABASE} >> ./LOG/TMP_OUTPUT.LOG 2>&1

#Update statistics for SYSTEM
echo "Update statistics for SYSTEM"
bsql --username=SYSADM --password=${SYSADM_PASS} --query="update statistics for ident SYSTEM"
echo "Database schemas created"
echo ""
echo "Analyzing database, store results in ./GEN_SQL/${SCHEMA}_ANALYZE.SQL"
dbanalyzer --username=${MIMER_USER} --password=${MIMER_PASS} ${MIMER_DATABASE} > ./GEN_SQL/${SCHEMA}_ANALYZE.SQL
echo "Optimizing database, log results to ./LOG/${SCHEMA}_ANALYZE.LOG"
echo "log input,output on './LOG/ANALYZE_SCHEMA_${SCHEMA}.LOG';" > ./GEN_SQL/ANALYZE_SCHEMA_${SCHEMA}.SQL
echo "WHENEVER ERROR CONTINUE;" >> ./GEN_SQL/ANALYZE_SCHEMA_${SCHEMA}.SQL
echo "read './GEN_SQL/${SCHEMA}_ANALYZE.SQL';" >> ./GEN_SQL/ANALYZE_SCHEMA_${SCHEMA}.SQL
echo "EXIT;" >> ./GEN_SQL/ANALYZE_SCHEMA_${SCHEMA}.SQL
bsql --username=${MIMER_USER} --password=${MIMER_PASS} --query="read './GEN_SQL/ANALYZE_SCHEMA_${SCHEMA}.SQL'" ${MIMER_DATABASE} >> ./LOG/TMP_OUTPUT.LOG 2>&1
echo ""
echo "Loading exported data into Mimer SQL"
echo "Log files for the load operations can be found in ./LOG/"
# Load tables in correct order so we don't violate foreign key constraints
echo "log output on '${TABLE_DEFS}';" > ./GEN_SQL/GET_TABLES_${SCHEMA}.SQL
echo "set silence on;" >> ./GEN_SQL/GET_TABLES_${SCHEMA}.SQL >> ./GEN_SQL/GET_TABLES_${SCHEMA}.SQL
echo "select object_name from system.objects where object_type = 'BASE TABLE' " >> ./GEN_SQL/GET_TABLES_${SCHEMA}.SQL
echo "and object_schema = '${SCHEMA}' order by coalesce(object_altered, object_created);" >> ./GEN_SQL/GET_TABLES_${SCHEMA}.SQL
bsql --username=SYSADM --password=${SYSADM_PASS} --query="read './GEN_SQL/GET_TABLES_${SCHEMA}.SQL'" ${MIMER_DATABASE} >> ./LOG/TMP_OUTPUT.LOG 2>&1
#

#Open the file with tables
while IFS= read -r line; do
    tab=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
    if [ "$tab" != "" ]; then
        if [ -e ./UNLOAD_DATA/${SCHEMA}-${tab}.TXT ]; then
            echo "Loading $tab"
            LOAD_CMD="load from 'DELIM.DAT', './UNLOAD_DATA/${SCHEMA}-${tab}.TXT' as ${ENCODING} log './LOG/LOAD_${SCHEMA}-${tab}.LOG' insert into ${SCHEMA}.${tab}"
            mimload --username=${MIMER_USER} --password=${MIMER_PASS} "${LOAD_CMD}" ${MIMER_DATABASE}
#        else
#            echo "Skipping $tab, no data file found"
        fi
    fi
done < ${TABLE_DEFS}
echo "Finished loading data"
echo ""
echo "Updating statistics"
bsql --username=SYSADM --password=${SYSADM_PASS} --query="update statistics for ident SYSTEM" ${MIMER_DATABASE}
bsql --username=${MIMER_USER} --password=${MIMER_PASS} --query="update statistics for schema ${SCHEMA}" ${MIMER_DATABASE}
echo "Finished loading data into Mimer SQL using the database user ${MIMER_USER} and database schema ${SCHEMA}"
echo "The password for the Mimer SQL user ${MIMER_USER} can be changed with the SQL statement ""alter ident ${MIMER_USER} identified by '<new password>'"""
exit

