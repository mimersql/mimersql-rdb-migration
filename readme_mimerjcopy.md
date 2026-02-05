# MimerJCopy - Migrate Table Data to Mimer SQL

MimerJCopy copies table data from Rdb to Mimer SQL.

## Features

- Copies data from Rdb to Mimer SQL
- Supports Mimer SQL LOAD mode for fast bulk inserts
- Batch processing with configurable batch and fetch sizes
- Handles all standard SQL data types including LOBs
- Progress reporting with row counts
- Skips rows that fail (e.g., constraint violations) and continues

## Prerequisites

- Java 8 or later
- Mimer SQL JDBC driver
- Rdb JDBC driver

### OpenVMS Setup

1. Install OpenJDK for OpenVMS and run:
   ```
   @SYS$STARTUP:OPENJDK$SETUP.COM
   ```

2. Install the Rdb JDBC driver and run:
   ```
   @<rdb-jdbc-path>RDBJDBC_STARTUP.COM
   ```

### OpenVMS JAVA$CLASSPATH

On OpenVMS, use `JAVA$CLASSPATH` (not `CLASSPATH`) to specify JAR files. The paths must be comma-separated:

```
DEFINE JAVA$CLASSPATH MIMER$LIB:MIMJDBC3.JAR, RDB$JDBC_HOME:RDBNATIVEV8.JAR, SYS$DISK:[]MIMERJCOPY.JAR
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

- LOAD mode cannot be used for tables containing LOB columns (BLOB, CLOB). MimerJCopy automatically falls back to regular inserts for such tables.
- The program will try to use "BULK LOAD". "BULK LOAD" is faster but requires exclusive access to the target table and that the table is empty.
If it fails, it falls back to regular LOAD mode.

## Usage

### Copy a Single Table

```
java MimerJCopy -s SOURCE_TABLE -t TARGET_TABLE -p jdbc.properties
```

Example:
```
java MimerJCopy -s EMPLOYEES -t HR.EMPLOYEES -p jdbc.properties
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
java MimerJCopy -f tablefile.txt -p jdbc.properties
```

### Copy to a Target Schema

Use `-t` to specify a target schema. Tables will be created with the same name in that schema:

```
java MimerJCopy -f tablefile.txt -t MF_PERSONNEL -p jdbc.properties
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-p <file>` | Properties file (required) |
| `-s <table>` | Source table name |
| `-t <table>` | Target table or schema |
| `-f <file>` | File containing table mappings |
| `-v` | Verbose output |
| `-version` | Show version information |

## Table Name Formats

MimerJCopy supports various table name formats:

- `TABLE` - Simple table name
- `SCHEMA.TABLE` - Schema-qualified name
- `CATALOG.SCHEMA.TABLE` - Fully qualified name

Catalog and schema are concatenated with underscore (e.g., `CATALOG.SCHEMA.TABLE` becomes `CATALOG_SCHEMA.TABLE`).



## Example: Migrate the Rdb MF_PERSONNEL example database

To do this, the Mimer SQL migration package used to migrate from Rdb to Mimer SQL
on OpenVMS should be used. Using that package, this program will be run automatically
as part of the migration. In that case the table file is automatically created and
the schema and all the target tables are created in Mimer SQL as part of the process.

However, to run it manually, follow these steps:

1. Create the target tables in Mimer SQL with matching structure.

2. Create `jdbc.properties`:
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

3. Create `tables.txt` listing tables to migrate:
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

4. Run the migration:
   ```
   java MimerJCopy -f tables.txt -p jdbc.properties
   ```

