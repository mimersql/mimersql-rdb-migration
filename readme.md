# Rdb Migration

These OpenVMS DCL scripts are used to migrate an Rdb database to Mimer SQL.

## Environment Requirements

Before starting the environment must be configured:

### Rdb

- Relevant privileges to run Rdb RMU are needed.
- The Rdb JDBC drivers must be installed (not needed if file based migration is used, see below for more information).

### Mimer SQL

Mimer SQL must be installed, `MIMER_DATABASE` needs to be defined, and the Mimer SQL database server must be started:

```dcl
DEFINE MIMER_DATABASE mimerdb
MIMCONTROL/START
```

### Java and JDBC configuration

This section only applies to the default direct data migration. It can be skipped if file based migration is used, see below for more information.

OpenJDK 8 or later must be installed and initialized, and the Rdb JDBC driver must be activated:

```dcl
@SYS$STARTUP:OPENJDK$SETUP.COM
@<rdb-jdbc-path>RDBJDBC_STARTUP.COM
```

`RDB$JDBC_HOME` must point to the Rdb JDBC installation. If `JAVA$CLASSPATH` is not defined, `load_mimer.com` defines it as `MIMER$LIB:MIMJDBC3.JAR`, `RDB$JDBC_HOME:RDBNATIVEV8.JAR` and `SYS$DISK:[]MIMERJMIGRATE.JAR`. If `JAVA$CLASSPATH` is already defined, it is used as is, but `load_mimer.com` checks that it contains `MIMJDBC3.JAR` and `MIMERJMIGRATE.JAR`, and warns if no Rdb JDBC driver is found.

The source and target databases are configured in a property file in the `[.CONF]` directory, named `<schema>.properties`. See below for a description of `<schema>`. An example, `jdbc.properties`, is included. Copy it to `<schema>.properties` and specify `source.driver`, `source.url`, `source.username`, `source.password`, and `target.url`, where `source.*` configures how to access the Rdb database and `target.url` how to access the Mimer SQL database. How these should be configured depends on where you run the data migration step (i.e. loading of data). The database name in `target.url` should be the same as `MIMER_DATABASE`, otherwise `load_mimer.com` gives a warning. The Mimer SQL user and password given to `@load_mimer` below are passed to MimerJMigrate and override `target.username` and `target.password` in the property file. See "readme_mimerjmigrate.md" for more information.

## Directory Structure

In the root directory, there are two scripts: `unload_rdb.com` and `load_mimer.com`, which handle the migration. `mimerjmigrate.jar` is used for direct data migration, and `DELIM.DAT` describes the format of the exported data files used by file based migration. `DELIM.DAT` must be in the current directory when file based migration is used.

When the command procedures are executed, several directories are created:

- `[.unload_data]`
  - Contains the unloaded data from Rdb.
- `[.gen_sql]`
  - Stores the generated SQL files for Mimer SQL.
- `[.log]`
  - Holds log files.

## Performing the Migration

The migration can be done in two ways and both are handled by the provided DCL scripts:

1. Direct migration using the included MimerJMigrate that will migrate data directly from Rdb to Mimer SQL without intermediate files. This is the default method.
2. File based data migration by exporting all data from Rdb into files using `RMU` and then loading the data into Mimer SQL.

Both migration methods will extract the SQL schema from Rdb, translate the schema to Mimer SQL and create it in the Mimer SQL database, load the data into Mimer SQL, and then optionally execute some custom SQL.


First, run:

```dcl
@unload_rdb <path to database> <schema> [ALL|SCHEMA]
```

The second argument, `<schema>`, is used as the schema name in Mimer SQL and to prefix the different generated files in the unload process. The result of this operation is put in `[.unload_data]`. The third argument determines if direct migration of data or exported files will be used. The default when left out is `SCHEMA`.

- When direct migration is used only the SQL schema is extracted from Rdb and the resulting SQL file is put in `[.unload_data]`. No data files are created.
- When file based migration is used (by specifying `ALL`), the same SQL schema extraction is done, but in addition each table with data will be exported into a text file in `[.unload_data]`.


When the unload operation is finished, the migration and loading of the schema and data into Mimer SQL is performed by running:

```dcl
@load_mimer <SYSADM password> <schema> [<Mimer SQL user> <Mimer SQL password>] [operation] [databank file]
```

- `<SYSADM password>` can be an empty string, in which case you will be prompted for the password.
- `<schema>` should be the same as `<schema>` in the unload step.
- `<Mimer SQL user>` is a database user that will be created if it does not exist. If left out, a default user called "mimeruser" is used.
- `<Mimer SQL password>` is the password for `<Mimer SQL user>`.
- `operation`: If specified, only do part of the migration. Valid values are ALL, CREATE, LOAD, RMULOAD, CONTINUE_LOAD, CONTINUE_RMULOAD, see below.
- `databank file` is used to specify the file for the databank `<schema>_DB` where the schema objects are stored. If not specified, the file name `<schema>_DB` is used.


For the specified Mimer SQL user, a schema will be created, and all database objects will be created within that schema. Multiple Rdb databases can be unloaded and loaded using the same Mimer SQL user but with different schema names. The schema corresponds to the name given by the “declare alias” statement used with the Rdb database.

To handle objects that need to be manually migrated or to execute other custom SQL, the load_mimer.com script will look for sql files in `[.extra_sql]`. This can be used, for example, to create triggers that could not be automatically converted to Mimer SQL or to drop constraints you don't want active during the load. There are different files for different stages of the migration:

- [.extra_sql]<schema>-BEFORE-CREATE.SQL
  - Executed as the specified user after the schema name is created, but before the translated schema is read. This can be used for objects that could not be translated automatically and are used in many places later in the schema, for example domains.
- [.extra_sql]<schema>-SYSTEM-AFTER-CREATE.SQL
  - Executed as SYSADM after the schema is created. This can be for example changing the size of a databank.
- [.extra_sql]<schema>-AFTER-CREATE.SQL
  - Executed as the specified user in the schema created. This can be manually changed index or other optimizations.
- [.extra_sql]<schema>-BEFORE-LOAD.SQL
  - Executed just before loading data into the tables. An example of SQL to put here is temporarily drop indexes, triggers or constraints
- [.extra_sql]<schema>-AFTER-LOAD.SQL
  - Executed as the specified user after data is loaded. An example of SQL to put here is manually created triggers and objects temporarily dropped before load.
If the files are found they are executed, otherwise ignored.


The `load_mimer.com` script will perform the following steps when running in default mode (i.e. without `operation`):

1. Run `sqltranslator` on the Rdb SQL schema to make it compatible with Mimer SQL.
2. Create the Mimer SQL user if it does not exist.
3. Create a databank where database objects will be stored.
4. Create the Mimer SQL schema for the migrated Rdb database.
5. If [.extra_sql]<schema>-before-create.sql exists, execute it to create objects that the translated schema depends on, such as domains.
6. Execute the translated SQL schema file using Mimer SQL.
7. Run `dbanalyzer` and apply the suggested changes on the created schema to optimize the database structure.
8. If [.extra_sql]<schema>-after-create.sql or [.extra_sql]<schema>-system-after-create.sql exists, execute them (in that order) to run custom SQL, such as changing table or databank definitions.
9. Set the TRANSACTION option on the databank during the load.
10. If [.extra_sql]<schema>-before-load.sql exists, execute it, for example to drop constraints or indexes during the load.
11. Load each table into Mimer SQL using either MimerJMigrate for direct migration or the exported data files for file based migration.
12. If [.extra_sql]<schema>-after-load.sql exists, execute it to run custom SQL, such as creating manually converted triggers.
13. Set the LOG option on the databank again.
14. Update database statistics for the Mimer SQL database to ensure efficient query execution.

The entire migration can be performed on a single machine that has both Mimer SQL and Rdb installed, or it can be done on separate machines. If using separate machines, run `unload_rdb.com` on the machine with Rdb, transfer the entire directory to the machine with Mimer SQL installed, and then run `load_mimer.com`. The target Mimer SQL database can also be a remote server. This way you can for example run the entire migration from the source machine and create the schema and load the data directly into a Mimer SQL database located on a different machine. This way you can move from Rdb on IA64 to Mimer SQL on x86 without moving any files.

Using the `operation` parameter with `load_mimer.com` it is possible to divide the migration steps into different parts and only run the translation, creation, and optimization or loading of data separately. This is useful for example to experiment with the schema creation and optimize it before loading data. The default is to run all steps (the same as specifying ALL). Valid operations are:

- `CREATE`: Only translate, create, and optimize the schema, do not load any data
- `LOAD`: Only load data into an already created schema using the direct migration with MimerJMigrate.
- `RMULOAD`: Only load data into an already created schema using the exported data files.
- `CONTINUE_LOAD`: Continue the load after an aborted load operation using the direct data migration with MimerJMigrate.
- `CONTINUE_RMULOAD`: Continue the load after an aborted load operation using the exported data files.

When running `@load_mimer "" <SCHEMA> <USER> <PASSWORD> LOAD|RMULOAD` the scripts look in the database to see what tables to load data into and in what order. The tables to load are stored in [.UNLOAD_DATA]<schema>-TABLES-MIMER.TXT. If the load is aborted before all tables have been loaded, check the output to see what tables have been successfully loaded:

By default the load output is written to the terminal. To also get log files, set `LOAD_LOG_STDERR` to `"NO"` at the beginning of `load_mimer.com`:

- Direct migration (`LOAD`): MimerJMigrate writes a log file named `[.LOG]<schema>-<operation>.LOG`, for example `[.LOG]<schema>-LOAD.LOG`. The output is still shown on the terminal as well.
- File based migration (`RMULOAD`): one log file per table, named `[.LOG]LOAD_<schema>-<tablename>.LOG`, is written instead of the terminal output.

To continue the load, remove the tables that have been successfully loaded from [.UNLOAD_DATA]<schema>-TABLES-MIMER.TXT, and then run the load again, but now with `CONTINUE_LOAD|CONTINUE_RMULOAD` instead of `LOAD|RMULOAD`.

To avoid duplicate errors, delete all rows in tables that have been partially loaded before continuing the load.

## Migrating Embedded SQL Programs

Programs written in COBOL or Fortran with Rdb Embedded SQL can be converted to Mimer SQL Embedded SQL and built with the command procedures `build_cobol.com` and `build_fortran.com`:

```dcl
@build_cobol <PROG1,PROG2,...> [DEBUG]
@build_fortran <PROG1,PROG2,...> [DEBUG]
```

The first parameter is a comma separated list of program names without file extension. The source files must be in the current directory. If `DEBUG` is given as the second parameter, the programs are compiled and linked with debug information and without optimization.

For each program the following steps are performed:

| Step | COBOL | Fortran |
|------|-------|---------|
| 1. Translate Rdb Embedded SQL to Mimer SQL with `sqltranslator` | `<prog>.SCO` → `[.new_source]<prog>.ECO` | `<prog>.SFO` → `[.new_source]<prog>.EFO` |
| 2. Run the Mimer SQL Embedded SQL preprocessor `esql` | `[.build]<prog>.COB` | `[.build]<prog>.FOR` |
| 3. Compile | `[.build]<prog>.OBJ` | `[.build]<prog>.OBJ` |
| 4. Link with `MIMER$LIB:MIMER$SQL/OPT` | `[.build]<prog>.EXE` | `[.build]<prog>.EXE` |

The translated `.ECO` and `.EFO` files in `[.new_source]` are the new main source. Further development should be done in these files. Note that the build procedures always start from the Rdb source files, so once development has moved to the new source, build it with `esql` and the compiler directly.

The `MIMER_DATABASE` logical name must be defined, and the Mimer SQL Embedded SQL preprocessor and the COBOL or Fortran compiler must be installed.

### Connecting to Mimer SQL

The statement used to connect to Mimer SQL is not valid in Rdb Embedded SQL. Instead, the connect is placed in the file `MIMER_CONNECT.INC`, which is included in the program where the connection should be made:

```cobol
    EXEC SQL INCLUDE MIMER_CONNECT.INC END-EXEC.
```

`MIMER_CONNECT.INC` connects to the database given by `MIMER_DATABASE` and stops the program if the connect fails. Edit the user name and password in the file before building the programs. The file must be in the current directory when the programs are built.

### Demo program

`DEMO.SCO` is a small COBOL program with Rdb Embedded SQL that shows how a program is built and run. It connects to Mimer SQL using `MIMER_CONNECT.INC`, drops the table `TAB1` if it exists, creates it, inserts three rows, and then selects and prints them. Errors are reported with `SQLCODE`.

```dcl
@build_cobol DEMO
run [.build]DEMO
```

The output is:

```
Connecting
Dropping table TAB1 if it exists
Creating table TAB1
Inserting rows
Selecting rows from TAB1

       ID  NAME                     AMOUNT
---------  --------------------  ---------
        1  Apple                       120
        2  Banana                       75
        3  Cherry                      -10

        3 rows selected
Disconnecting
```

`TAB1` is created in the schema with the same name as the user in `MIMER_CONNECT.INC`, so that schema must exist. A user created by `load_mimer.com` is created without a schema of its own.
