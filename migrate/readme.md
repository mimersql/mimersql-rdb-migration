# Rdb Migration

These OpenVMS DCL scripts are used to migrate an Rdb database to Mimer SQL.

## Environment Requirements

Relevant privileges to run Rdb RMU are needed.

## Mimer SQL

`MIMER_DATABASE` needs to be defined, and the Mimer SQL database server must be started:

```dcl
DEFINE MIMER_DATABASE mimerdb
MIMCONTROL/START
```

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

The migration process will unload the SQL schema and all tables with data from Rdb, then translate the schema to Mimer SQL and load the data, and then optionally
execute some custom SQL.

First, run:

```dcl
@unload_rdb <path to database> <schema>
```

The last argument is used as the schema name in Mimer SQL and to prefix the different generated files in the unload process. In `[.unload_data]`, there will be one SQL schema file that creates all database objects and one text file for each Rdb table containing data.

When the unload is finished, the migration and loading of the schema and data into Mimer SQL is performed by running:

```dcl
@load_mimer <SYSADM password> <schema> [<Mimer SQL user> <Mimer SQL> password] [operation]
```

- `<SYSADM password>` can be an empty string, in which case you will be prompted for the password.
- `<schema>` should be the same as `<name of database>` in the unload step.
- `<Mimer SQL user>` is a database user that will be created if it does not exist. If left out, a default user called "mimeruser" is used.
- `<Mimer SQL password>` is the password for `<Mimer SQL user>`
- `operation`: If specified only do part of the migration and valid values are ALL, CREATE, LOAD, and CONTINUE_LOAD

For the specified Mimer SQL user, a schema will be created, and all database objects will be created within that schema. Multiple Rdb databases can be unloaded and loaded using the same Mimer SQL user but with different schema names. The schema corresponds to the name given by the “declare alias” statement used with the Rdb database.
To handle objects that need to be manually migrated or to execute other custom SQL, the load_mimer.com script will look for a files in `[.extra_sql]`. This can be used, for example, to create triggers that could not be automatically converted to Mimer SQL. There are different files for different stages of the migration:

- [.extra_sql]<schema>-SYSTEM-AFTER-CREATE.SQL
  - Executed as SYSADM after the schema is created. This can be for example changing the size of a databank.
- [.extra_sql]<schema>-AFTER-CREATE.SQL
  - Executed as the specified specified user in the schema created. This can be manually changed index or other optimizations.
- [.extra_sql]<schema>-AFTER-LOAD.SQL
  - Executed as the specified user after data is loaded. An example of SQL to put here is manyally created triggers.
If the files are found they are executed, otherwise ignored.


The `load_mimer.com` script will perform the following steps when running in default mode (i.e without `operaton`):

1. Run `sqltranslator` on the Rdb SQL schema to make it compatible with Mimer SQL.
2. Create the Mimer SQL user if it does not exist.
3. Create a databank where database objects will be stored.
4. Create the Mimer SQL schema for the migrated Rdb database.
5. Execute the translated SQL schema file using Mimer SQL.
6. Run `dbanalyzer` and apply the suggested changes on the created schema to optimize the database structure.
7. Load each table that contains data.
8. If the file `[.extra_sql]<schema>.sql` exists, execute it to run custom SQL, such as manually converted triggers.
9. Update database statistics for the Mimer SQL database to ensure efficient query execution.

The entire migration can be performed on a single machine that has both Mimer SQL and Rdb installed, or it can be done on separate machines. If using separate machines, run `unload_rdb.com` on the machine with Rdb, transfer the entire directory to the machine with Mimer SQL installed, and then run `load_mimer.com`.

Using the `operation` parameter with `load_mimer.com`it is possible to divide the migration steps into different part and only run the translation, creation, and optimization or loading of data seperately. This is usefull for example to experiment with the schema creation and optimize it before loading data. The default is to run all steps (the same as specifying ALL). Valid operations are:

- `CREATE`: Only translate, create, and optimize the schema, do not load any data
- `LOAD`: Only load data into an already created schema
- `CONTINUE_LOAD`: Continue the load after an aborted load operation.

When running `@load_mimer "" <SCHEMA> <USER> <PASSWORD> LOAD`
the scripts look in the database to see what tables to load data into and in what order. The tables to load are stored in [.UNLOAD_DATA]<schema>-TABLES-MIMER.TXT. If the load is aborted before all tables have been loaded it is possible to check the log files for each table loaded in the [.log] directory to see what tables have been succesfully load. The log files are named LOAD<schema>-<tablename>.LOG. To continue the load, remove the tables that have been successfully loaded from [.UNLOAD_DATA]<schema>-TABLES-MIMER.TXT, and then run the load again, but now with `CONTINUE_LOAD` instead of `LOAD`.
To avoid duplicate errors and speed up the load, delete all rows in tables that have been partially loaded.
Note that [.UNLOAD_DATA]<schema>-TABLES-MIMER.TXT can contain more tables than you have exported data for, but tables that do not have a export data file (.ie `[.unload_data]<schema>-<table>.txt`) are ignored.
