# MimerJMigrate - Database Migration Tool for Mimer SQL

MimerJMigrate migrates databases to Mimer SQL from any JDBC-accessible source. It can migrate the full schema — tables, primary keys, foreign keys, indexes, and sequences — as well as the data, or any combination of the two. It is designed for migrating from Oracle Rdb on OpenVMS to Mimer SQL, but works with any source database that has a JDBC driver and any OS.

## Features

- Copies data from any JDBC source to Mimer SQL
- Optional schema migration: creates tables, primary keys, foreign keys, indexes and sequences automatically from source JDBC metadata
- Schema-only mode: create and verify the target schema before committing to a full data load
- Migrate one schema, multiple schemas, or all schemas in a single run
- Automatic FK-aware table ordering: tables are loaded parent-first to avoid constraint violations
- Supports Mimer SQL LOAD mode for fast bulk inserts
- Batch processing with configurable batch and fetch sizes
- Handles all standard SQL data types including LOBs
- Progress reporting with row counts and timing
- Skips rows that fail (e.g., constraint violations) and continues

## Prerequisites

- Java 8 or later
- Mimer SQL JDBC driver
- JDBC driver for your source database

### OpenVMS Setup

1. Install OpenJDK for OpenVMS and run:
   ```
   @SYS$STARTUP:OPENJDK$SETUP.COM
   ```

2. If migrating from Rdb, install the Rdb JDBC driver and run:
   ```
   @<rdb-jdbc-path>RDBJDBC_STARTUP.COM
   ```
## Installation

Download `mimerjmigrate.jar`.

### OpenVMS JAVA$CLASSPATH

On OpenVMS, use `JAVA$CLASSPATH` (not `CLASSPATH`) to specify JAR files. The paths must be comma-separated:

```
DEFINE JAVA$CLASSPATH MIMER$LIB:MIMJDBC3.JAR, RDB$JDBC_HOME:RDBNATIVEV8.JAR, SYS$DISK:[]MIMERJMIGRATE.JAR
```


## Configuration

Create a properties file (e.g., `jdbc.properties`) with connection details:

```properties
# Source database
source.driver=oracle.rdb.jdbc.rdbNative.Driver
source.url=jdbc:rdbNative:DKA100:[RDBEXA.MF_PERSONNEL]MF_PERSONNEL
source.username=
source.password=

# Target database (Mimer SQL)
target.url=jdbc:mimer://localhost:1360/personnel
target.username=<Mimer SQL user>
target.password=<Mimer SQL password>

# Use Mimer LOAD mode for faster inserts (default: true)
target.mimerload=true

# Rows per batch insert (default: 1000)
batch.size=1000

# Rows fetched from source per round-trip (default: 1000)
fetch.size=1000

# Output options
verbose=true
debug=false
timing=true
```

### Properties Reference

| Property | Description | Default |
|----------|-------------|---------|
| `source.driver` | JDBC driver class for source database | (required) |
| `source.url` | JDBC URL for source database | (required) |
| `source.username` | Source database username (empty for OS auth) | |
| `source.password` | Source database password | |
| `target.url` | JDBC URL for Mimer SQL target | (required) |
| `target.username` | Mimer SQL username | (required) |
| `target.password` | Mimer SQL password | (required) |
| `target.mimerload` | Use LOAD mode for bulk inserts | true |
| `batch.size` | Number of rows per batch insert | 1000 |
| `fetch.size` | Rows fetched from source per round-trip | 1000 |
| `verbose` | Show progress information | false |
| `debug` | Show debug output | false |
| `timing` | Show timing information | false |

### About LOAD Mode

Mimer SQL LOAD mode (`target.mimerload=true`) provides faster bulk inserts. However:

- LOAD mode cannot be used for tables containing LOB columns (BLOB, CLOB). MimerJMigrate automatically falls back to regular inserts for such tables.
- The program will try to use "BULK LOAD". "BULK LOAD" is faster but requires exclusive access to the target table and that the table is empty.
If it fails, it falls back to regular LOAD mode.

## Usage

### Copy a Single Table
Both sides must be fully qualified with schema and table name:

```
java MimerJMigrate -s SOURCE_SCHEMA.TABLE -t TARGET_SCHEMA.TABLE -c jdbc.properties
```

Example:
```
java MimerJMigrate -s HR.EMPLOYEES -t HR.EMPLOYEES -c jdbc.properties
```

### Copy Multiple Tables from a File

Create a table file listing the tables to copy, one per line:

```
# tablefile.txt - lines starting with # are comments
EMPLOYEES
DEPARTMENTS
JOBS
```


Run with:
```
java MimerJMigrate -f tablefile.txt -c jdbc.properties
```

### Copy to a Target Schema

Use `-t` to specify a target schema. All tables will be placed in that schema on the target:

```
java MimerJMigrate -f tablefile.txt -t MF_PERSONNEL -c jdbc.properties
```
### Migrate a Full Schema

Use `-s <schema>` to enumerate all tables in a schema. Add `-schema` to also create the target
schema objects (tables, sequences, primary keys, foreign keys, indexes). Migration runs in three phases:

1. **Create sequences and tables** — CREATE SEQUENCE for auto-increment columns, then CREATE TABLE with columns, primary key, and DEFAULT NEXT VALUE FOR (no FK or indexes yet)
2. **Copy data** — migrate all rows using batch inserts
3. **Add foreign keys and indexes** — applied after data is loaded to avoid constraint violations during migration

```
java MimerJMigrate -schema -s MF_PERSONNEL -c jdbc.properties
```

To migrate into a different target schema:
```
java MimerJMigrate -schema -s MF_PERSONNEL -t HR -c jdbc.properties
```

To migrate a single table including its schema:
```
java MimerJMigrate -schema -s MF_PERSONNEL.EMPLOYEES -t MF_PERSONNEL.EMPLOYEES -c jdbc.properties
```

### Migrate Multiple Schemas

Specify several schemas as a comma-separated list or by repeating `-s`:

```
java MimerJMigrate -schema -s HR,SALES,FINANCE -c jdbc.properties
java MimerJMigrate -schema -s HR -s SALES -s FINANCE -c jdbc.properties
```

Each schema is migrated to the same name on the target. The `-t` flag is ignored when
multiple schemas are specified.

### Migrate All Schemas

Omit `-s` entirely (requires `-schema` or `-schema-only`) to migrate every schema found on
the source database. System and internal schemas are excluded automatically based on the
source database type:

| Source database | Automatically excluded schemas |
|-----------------|-------------------------------|
| All databases | `INFORMATION_SCHEMA` |
| Mimer SQL | `MIMER`, `SYSTEM`, `BUILTIN` |
| Oracle Database | `SYS`, `SYSTEM`, `OUTLN`, `DBSNMP`, `APPQOSSYS`, `CTXSYS`, `DVSYS`, `MDSYS`, `ORDSYS`, `WMSYS`, `XDB`, and others |
| Oracle Rdb | `RDB$SCHEMA`, `RDBRDB` (Rdb typically has no schemas; all tables are enumerated directly) |
| MySQL / MariaDB | `mysql`, `performance_schema`, `sys` |
| Microsoft SQL Server | `sys`, `guest` |
| PostgreSQL | `pg_catalog`, `pg_toast` |
| IBM DB2 | `SYSIBM`, `SYSCAT`, `SYSSTAT`, `SYSPUBLIC`, `SYSIBMADM` |

```
java MimerJMigrate -schema -c jdbc.properties
```

Use `-x` to exclude additional schemas by name (comma-separated or repeated):

```
java MimerJMigrate -schema -x LEGACY,ARCHIVE -c jdbc.properties
java MimerJMigrate -schema -x LEGACY -x ARCHIVE -c jdbc.properties
```

#### Schema-only mode

Use `-schema-only` to create the target schema without copying any data. This is useful for
verifying that the generated DDL is correct before committing to a potentially long data load.

```
java MimerJMigrate -schema-only -s MF_PERSONNEL -c jdbc.properties
```

Once you are satisfied with the schema, load the data using the same `-s <schema>` argument
but without `-schema-only`:

```
java MimerJMigrate -s MF_PERSONNEL -c jdbc.properties
```

> **Note:** When foreign keys already exist on the target, MimerJMigrate automatically sorts
> tables in FK dependency order (parents before children) so the load succeeds without
> constraint violations.

#### What schema migration covers

| Object | Supported |
|--------|-----------|
| Columns (all standard SQL types) | Yes |
| Primary keys | Yes |
| Foreign keys | Yes |
| Indexes (unique and non-unique) | Yes |
| Sequences (auto-increment) | Yes |
| Check constraints | No — not available through standard JDBC metadata |
| Vendor-specific types | Partial — unknown types fall back to `VARCHAR(255)` with a warning |

> **Note:** Schema migration uses standard JDBC `DatabaseMetaData`. Vendor-specific column
> types that the driver does not map to a standard JDBC type are substituted with `VARCHAR(255)`
> and a warning is printed to stderr. The affected columns need manual review after migration.

### Command Line Options

| Option | Description |
|--------|-------------|
| `-s <schema\|table>` | Source schema name(s) or `schema.table` (single mode). Comma-separated or repeated for multiple schemas. Omit with `-schema`/`-schema-only` to migrate all schemas. |
| `-x <schema>` | Exclude schema(s) when enumerating all schemas. Comma-separated or repeated. |
| `-t <schema\|table>` | Target table (single mode) or target schema (enumerate mode, optional). Ignored when migrating multiple schemas. |
| `-f <file>` | File containing table names, one per line |
| `-c <file>` | Configuration/properties file (default: jdbc.properties) |
| `-u <user>` | Target database username (overrides config file) |
| `-p <pass>` | Target database password (overrides config file) |
| `-schema` | Enable schema migration (create tables, sequences, FKs, indexes) |
| `-schema-only` | Create schema only, skip data copy (implies `-schema`) |

## Table Name Formats

MimerJMigrate supports various table name formats:

- `TABLE` - Simple table name
- `SCHEMA.TABLE` - Schema-qualified name
- `CATALOG.SCHEMA.TABLE` - Fully qualified name

Catalog and schema are concatenated with underscore (e.g., `CATALOG.SCHEMA.TABLE` becomes `CATALOG_SCHEMA.TABLE`).



## Example: Migrate the Rdb MF_PERSONNEL example database

### With schema migration (recommended)

The simplest approach: let MimerJMigrate discover and create the schema automatically.

1. Create `jdbc.properties`:
   ```properties
   source.driver=oracle.rdb.jdbc.rdbNative.Driver
   source.url=jdbc:rdbNative:DKA100:[RDBEXA.MF_PERSONNEL]MF_PERSONNEL
   source.username=
   source.password=

   target.url=jdbc:mimer://localhost:1360/personnel
   target.username=SYSADM
   target.password=secret

   target.mimerload=true
   verbose=true
   timing=true
   ```

2. Run:
   ```
   java MimerJMigrate -schema -s MF_PERSONNEL -c jdbc.properties
   ```

To migrate all schemas in the source database at once:
   ```
   java MimerJMigrate -schema -c jdbc.properties
   ```

### Without schema migration

If the target tables already exist (e.g., created by `-schema-only` or a separate DDL script):

1. Create `tables.txt` listing tables to migrate:
   ```
   DEPARTMENTS
   COLLEGES
   CANDIDATES
   WORK_STATUS
   EMPLOYEES
   JOBS
   JOB_HISTORY
   SALARY_HISTORY
   DEGREES
   RESUMES
   ```

2. Run the migration:
   ```
   java MimerJMigrate -f tables.txt -c jdbc.properties
   ```

