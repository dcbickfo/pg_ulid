# pg_ulid - PostgreSQL ULID Extension

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-blue.svg)](https://www.postgresql.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A PostgreSQL extension that implements the [ULID](https://github.com/ulid/spec) (Universally Unique Lexicographically Sortable Identifier) data type.

## What is ULID?

ULID is a 128-bit identifier designed to be:
- **Sortable**: Lexicographically sortable by timestamp
- **Compact**: 26-character string representation (vs 36 for UUID)
- **URL-safe**: Uses Crockford's Base32 encoding
- **Monotonic**: Sortable within the same millisecond

Format: `01ARZ3NDEKTSV4RRFFQ69G5FAV`
- First 10 characters: 48-bit timestamp (milliseconds since Unix epoch)
- Last 16 characters: 80 bits of randomness

## Features

- Native PostgreSQL data type with full operator support
- B-tree and hash indexing support
- Optimized sorting with abbreviated key support
- Binary send/receive for efficient client-server communication
- Thread-safe random ULID generation

## Installation

### Building from Source

This is the standard way to install the extension into your existing PostgreSQL database.

#### Requirements
- PostgreSQL 12+ (tested with PostgreSQL 12-18)
- PostgreSQL development headers (`postgresql-server-dev-all` on Debian/Ubuntu)
- `pg_config` in your PATH
- C compiler (gcc or clang)

#### Build and Install

```bash
# Install build dependencies (Debian/Ubuntu)
sudo apt-get install build-essential postgresql-server-dev-all

# Build and install the extension
make
sudo make install
```

#### Enable the Extension

Connect to your database and run:

```sql
CREATE EXTENSION pg_ulid;
```

### Manual Installation

If you need to install the extension files manually without using `make install`:

```bash
# 1. Build the shared library
make

# 2. Find your PostgreSQL directories
PG_LIBDIR=$(pg_config --pkglibdir)
PG_SHAREDIR=$(pg_config --sharedir)

# 3. Copy files to PostgreSQL directories
sudo cp ulid.so $PG_LIBDIR/
sudo cp pg_ulid.control $PG_SHAREDIR/extension/
sudo cp pg_ulid--0.1.0.sql $PG_SHAREDIR/extension/

# 4. Verify installation
ls -l $PG_LIBDIR/ulid.so
ls -l $PG_SHAREDIR/extension/pg_ulid*
```

Then connect to your database and run:
```sql
CREATE EXTENSION pg_ulid;
```

### Running PostgreSQL with Docker

For development or testing, you can run a PostgreSQL instance with pg_ulid pre-installed:

```bash
# Build the Docker image
docker build -t postgres-pg_ulid .

# Run PostgreSQL with the extension available
docker run -d -p 5432:5432 postgres-pg_ulid

# Connect and create the extension
psql -h localhost -U postgres -c "CREATE EXTENSION pg_ulid;"
```

## Usage

### Generate ULIDs

```sql
-- Generate a random ULID
SELECT gen_random_ulid();
-- Output: 01HN64YSHFEB58ZAH8AV4HTTBT

-- Use as default value
CREATE TABLE users (
    id ulid PRIMARY KEY DEFAULT gen_random_ulid(),
    username TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Parse and Store ULIDs

```sql
-- Insert ULID from string
INSERT INTO users (id, username)
VALUES ('01HN64YSHFEB58ZAH8AV4HTTBT'::ulid, 'alice');

-- ULIDs are sortable by creation time
SELECT id, username
FROM users
ORDER BY id ASC;
```

### Indexing

```sql
-- B-tree index (supports <, <=, =, >=, >)
CREATE INDEX idx_users_id ON users (id);

-- Hash index (supports = only)
CREATE INDEX idx_users_id_hash ON users USING HASH (id);
```

### Operators

All standard comparison operators are supported:

```sql
SELECT * FROM users WHERE id < '01HN64YSHFEB58ZAH8AV4HTTBT'::ulid;
SELECT * FROM users WHERE id = '01HN64YSHFEB58ZAH8AV4HTTBT'::ulid;
SELECT * FROM users WHERE id >= '01HN64YSHFEB58ZAH8AV4HTTBT'::ulid;
SELECT * FROM users WHERE id <> '01HN64YSHFEB58ZAH8AV4HTTBT'::ulid;
```

## Testing

```bash
# Run regression tests using Docker
./test.sh

# Run code quality checks (requires clang-format and clang-tidy)
make -f Makefile.lint check
```

## How It Works

### String Encoding
ULIDs use Crockford's Base32 encoding (case-insensitive, excludes I, L, O, U to avoid confusion):
```
0123456789ABCDEFGHJKMNPQRSTVWXYZ
```

### Internal Representation
Stored as 16 bytes (128 bits):
- Bytes 0-5: 48-bit timestamp (milliseconds)
- Bytes 6-15: 80 bits of cryptographic randomness

### Performance
- Uses PostgreSQL's `pg_strong_random()` for cryptographically secure random generation
- Abbreviated key optimization for fast sorting
- Efficient `memcmp`-based comparison

## Upgrading

### Version Compatibility

This extension follows semantic versioning. Upgrade paths between versions:

- **0.1.x → 0.2.x**: Planned minor version upgrades will provide automatic migration scripts
- Future upgrade scripts will be named: `ulid--0.1.0--0.2.0.sql`

### How to Upgrade

```sql
-- Check current version
SELECT extversion FROM pg_extension WHERE extname = 'pg_ulid';

-- Upgrade to latest version
ALTER EXTENSION pg_ulid UPDATE;

-- Upgrade to specific version
ALTER EXTENSION pg_ulid UPDATE TO '0.2.0';
```

### Downgrade Policy

Downgrades are **not supported**. Always backup your database before upgrading.

## Attribution

This extension builds upon ideas and patterns from several sources:

- **PostgreSQL Core**: Data type implementation patterns, sort support strategies, and indexing structures
  (PostgreSQL License, Copyright PostgreSQL Global Development Group)
- **ULID Specification**: https://github.com/ulid/spec
- **Crockford Base32**: Encoding/decoding inspired by public domain ULID implementations,
  including https://github.com/skeeto/ulid-c (Unlicense)

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please ensure:
1. All tests pass (`./test.sh`)
2. Code follows PostgreSQL C coding conventions
3. New features include regression tests

## Links

- **Source Code**: https://github.com/dcbickfo/pg_ulid
- **Issue Tracker**: https://github.com/dcbickfo/pg_ulid/issues
- **Documentation**: [doc/ulid.md](doc/ulid.md)

## References

- [ULID Specification](https://github.com/ulid/spec)
- [Crockford Base32](https://www.crockford.com/base32.html)
- [PostgreSQL Extension Documentation](https://www.postgresql.org/docs/current/extend-extensions.html)
