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

The migration process will unload the SQL schema and all tables with data from Rdb, then translate the schema to Mimer SQL and load the data.

First, run:

```dcl
@unload_rdb <path to database> <schema>
```

The last argument is used as the schema name in Mimer SQL and to prefix the different generated files in the unload process. In `[.unload_data]`, there will be one SQL schema file that creates all database objects and one text file for each Rdb table containing data.

When the unload is finished, the migration and loading of the schema and data into Mimer SQL is performed by running:

```dcl
@load_mimer <SYSADM password> <schema> [<Mimer SQL user>]
```

- `<SYSADM password>` can be an empty string, in which case you will be prompted for the password.
- `<schema>` should be the same as `<name of database>` in the unload step.
- `<Mimer SQL user>` is a database user that will be created if it does not exist. If left out, a default user called "mimeruser" is used.

For the specified Mimer SQL user, a schema will be created, and all database objects will be created within that schema. Multiple Rdb databases can be unloaded and loaded using the same Mimer SQL user but with different schema names. The schema corresponds to the name given by the “declare alias” statement used with the Rdb database.

The `load_mimer.com` script will perform the following steps:

1. Run `sqltranslator` on the Rdb SQL schema to make it compatible with Mimer SQL.
2. Create the Mimer SQL user if it does not exist.
3. Create a databank where database objects will be stored.
4. Create the Mimer SQL schema for the migrated Rdb database.
5. Execute the translated SQL schema file using Mimer SQL.
6. Run `dbanalyzer` and apply the suggested changes on the created schema to optimize the database structure.
7. Load each table that contains data.
8. Update database statistics for the Mimer SQL database to ensure efficient query execution.

The entire migration can be performed on a single machine that has both Mimer SQL and Rdb installed, or it can be done on separate machines. If using separate machines, run `unload_rdb.com` on the machine with Rdb, transfer the entire directory to the machine with Mimer SQL installed, and then run `load_mimer.com`.

