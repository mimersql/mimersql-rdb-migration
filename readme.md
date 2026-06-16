# Rdb Migration

These OpenVMS DCL scripts are used to migrate an Rdb database to Mimer SQL.

## Environment Requirements

Before starting the environment must be configured:

### Rdb

- Relevant privileges to run Rdb RMU are needed.
- The Rdb JDBC drivers must be installed (not needed if file based migration is used, see below for more information )

### Mimer SQL

Mimer SQL must be installed, `MIMER_DATABASE` needs to be defined, and the Mimer SQL database server must be started:

```dcl
DEFINE MIMER_DATABASE mimerdb
MIMCONTROL/START
```

### JDBC configuraiton

When the default direct data migration is used, a property file `CONF` directory is used to configure the source and target database. The file should be named as
`<schema>.properties`. See below for a description about `<schema>`. An example `jdbc.properties` is included. Edit this file to specify `source.driver`, `source.url`, `source.username`, `source.password`, `target.url`, `target.user`, and `target.password` where `source.*` configures how to access the Rdb database and `target.*` how to access the Mimer SQL database. How these should be configured depends on where you run the data migration step (i.e . loading of data). The `target.user` and `target.password` must be the same as you use in the `@load_mimer` command below.
This step can be skipped if file based migration is used, see below for more information. See "readme_mimerjmigrate.md" for more information.

The OpenJDK 8 Java runtime environmnet must be installed.

## Directory Structure

In the root directory, there are two scripts: `unload_rdb.com` and `load_mimer.com`, which handle the migration.

When the command procedures are executed, several directories are created:

- `[.unload_data]`
  - Contains the unloaded data from Rdb.
- `[.gen_sql]`
  - Stores the generated SQL files for Mimer SQL.
- `[.log]`
  - Holds log files.

## Performing the Migration

The migration can be done in two ways and both are handled by the provided `DCL`scripts:

1. Direct migration using the included MimerJMigrate that will migrate data directly from Rdb to Mimer SQL without intermediate files. This is the default method.
2. File base data migration by exporting all data from Rdb into files using `RMU` and then loading the data into Mimer SQL.

Both migration methods will extract the SQL schema from Rdb, translate the schema to Mimer SQL and create it in the Mimer SQL databasen, load the data into Mimer SQL, and then optionally execute some custom SQL.


First, run:

```dcl
@unload_rdb <path to database> <schema> [ALL|SCHEMA]
```

The last argument is used as the schema name in Mimer SQL and to prefix the different generated files in the unload process. The result of this operation are put in `[.unload_data]`. The third argument determines if direct migration of data or extraced files will be used. The default when left out is `SCHEMA`.

- When direct migration is used only the SQL schema is extracted from Rdb and the resulting SQL files is put in `[.unload_data]`. No data files are created.
- When file based migration is used (by specifying `ALL`), the same SQL schema extraction is done, but in addition each table with data will be exported into a text file in `[.unload_data]`.


When the unload operation is finished, the migration and loading of the schema and data into Mimer SQL is performed by running:

```dcl
@load_mimer <SYSADM password> <schema> [<Mimer SQL user> <Mimer SQL password] [operation] [delete] [databank file]
```

- `<SYSADM password>` can be an empty string, in which case you will be prompted for the password.
- `<schema>` should be the same as `<name of database>` in the unload step.
- `<Mimer SQL user>` is a database user that will be created if it does not exist. If left out, a default user called "mimeruser" is used.
- `<Mimer SQL password>` is the password for `<Mimer SQL user>`
- `operation`: If specified only do part of the migration and valid values are ALL, CREATE, LOAD, RMULOAD, CONTINUE_LOAD, CONTINUE_RMULOAD
- `delete` can be specified to delete all rows in the tables before loading. Can be used together with continue_load.
- `databank file`is used to specify what the main databank file will be for the schema. If not specified, SCHEMA_NAME.DBF in the database home directory is used.


For the specified Mimer SQL user, a schema will be created, and all database objects will be created within that schema. Multiple Rdb databases can be unloaded and loaded using the same Mimer SQL user but with different schema names. The schema corresponds to the name given by the “declare alias” statement used with the Rdb database.
To handle objects that need to be manually migrated or to execute other custom SQL, the load_mimer.com script will look for sql files in `[.extra_sql]`. This can be used, for example, to create triggers that could not be automatically converted to Mimer SQL. There are different files for different stages of the migration:

- [.extra_sql]<schema>-SYSTEM-AFTER-CREATE.SQL
  - Executed as SYSADM after the schema is created. This can be for example changing the size of a databank.
- [.extra_sql]<schema>-AFTER-CREATE.SQL
  - Executed as the specified user in the schema created. This can be manually changed index or other optimizations.
- [.extra_sql]<schema>-BEFORE-LOAD.SQL
  - Executed just before loading data into the tables. An example of SQL to put here is temporarily drop indexes, triggers or constraints
- [.extra_sql]<schema>-AFTER-LOAD.SQL
  - Executed as the specified user after data is loaded. An example of SQL to put here is manually created triggers and objects temporarily dropped before load.
If the files are found they are executed, otherwise ignored.


The `load_mimer.com` script will perform the following steps when running in default mode (i.e without `operaton`):

1. Run `sqltranslator` on the Rdb SQL schema to make it compatible with Mimer SQL.
2. Create the Mimer SQL user if it does not exist.
3. Create a databank where database objects will be stored.
4. Create the Mimer SQL schema for the migrated Rdb database.
5. Execute the translated SQL schema file using Mimer SQL.
6. Run `dbanalyzer` and apply the suggested changes on the created schema to optimize the database structure.
7. If [.extra_sql]< schema >-system-after-create.sql or [.extra_sql]< schema>-after-create.sql exists, execute them to run custom SQL, such as changing table or databank definitions.
8. Load each table into Mimer SQL using either MimerJMigrate for direct migration or the exported data files for file based migration.
9. If [.extra_sql]<schema >-after-load.sql exists, execute it to run custom SQL, such as creating manually converted triggers.
10. Update database statistics for the Mimer SQL database to ensure efficient query execution.

The entire migration can be performed on a single machine that has both Mimer SQL and Rdb installed, or it can be done on separate machines. If using separate machines, run `unload_rdb.com` on the machine with Rdb, transfer the entire directory to the machine with Mimer SQL installed, and then run `load_mimer.com`. Alternatively, if the DCL scripts are on the target machine, transfer only the `[.unload_data]` directory from the source machine to the target machine before running `load_mimer.com`.

Using the `operation` parameter with `load_mimer.com`it is possible to divide the migration steps into different part and only run the translation, creation, and optimization or loading of data seperately. This is usefull for example to experiment with the schema creation and optimize it before loading data. The default is to run all steps (the same as specifying ALL). Valid operations are:

- `CREATE`: Only translate, create, and optimize the schema, do not load any data
- `LOAD`: Only load data into an already created schema using the direct migration with MimerJMigrate.
- `RMULOAD`: Only load data into an already created schema using the exported data files.
- `CONTINUE_LOAD`: Continue the load after an aborted load operation using the direct data migration with MimerJMigrate.
- `CONTINUE_RMULOAD`: Continue the load after an aborted load operation using the exported data files.

It is also possible to pass `DELETE` as an extra 6:th argument when running `CONTINUE_LOAD`. This will delete all rows in the tables that are being reloaded.

When running `@load_mimer "" <SCHEMA> <USER> <PASSWORD> LOAD|RMULOAD` the scripts look in the database to see what tables to load data into and in what order. The tables to load are stored in [.UNLOAD_DATA]<schema>-TABLES-MIMER.TXT. If the load is aborted before all tables have been loaded it is possible to check the log files for each table loaded in the [.log] directory to see what tables have been succesfully load. The log files are named LOAD<schema>-<tablename>.LOG. To continue the load, remove the tables that have been successfully loaded from [.UNLOAD_DATA]<schema>-TABLES-MIMER.TXT, and then run the load again, but now with `CONTINUE_LOAD|CONTINUE_RMULOAD` instead of `LOAD|RMULOAD`.

To avoid duplicate errors and speed up the load, pass `DELETE` as the 6:th argument to delete all rows in tables that have been partially loaded, or delete them manually. Note that the `DELETE` operation can take some time if a lot of data have been copied.
