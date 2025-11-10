# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a PostgreSQL extension that implements the ULID (Universally Unique Lexicographically Sortable Identifier) data type. ULIDs are 128-bit identifiers with embedded timestamps that are lexicographically sortable, encoded as 26-character Crockford Base32 strings.

## Build System

This project uses **PGXS** (PostgreSQL Extension Build System). The `Makefile` is the authoritative build configuration.

### Common Build Commands

```bash
# Build the extension
make

# Install to PostgreSQL (requires superuser)
sudo make install

# Run regression tests (Docker-based, recommended)
./test.sh

# Test with specific PostgreSQL version
PG_VERSION=15 ./test.sh

# Run tests without Docker (requires PostgreSQL already running)
make installcheck

# Clean build artifacts
make clean
./test.sh clean

# Create PGXN distribution package
make dist

# Check version info
make version
```

### Code Quality

```bash
# Format C code (requires clang-format)
make -f Makefile.lint format

# Check if formatting is needed
make -f Makefile.lint format-check

# Run static analysis (requires clang-tidy)
make -f Makefile.lint lint

# Run all code quality checks
make -f Makefile.lint check
```

## Architecture

### Core Data Type Implementation

The extension defines a native PostgreSQL data type stored as 16 bytes (128 bits):
- **Bytes 0-5**: 48-bit timestamp (milliseconds since Unix epoch)
- **Bytes 6-15**: 80 bits of cryptographic randomness

### Key Components

**`src/ulid.h`** - Header file containing:
- `pg_ulid_t` struct definition (16-byte fixed size)
- Crockford Base32 encoding/decoding tables
- Inline helper functions for datum conversion
- `ulid_internal_cmp()` - Fast memcmp-based comparison

**`src/ulid.c`** - Implementation containing:
- I/O functions: `ulid_in()`, `ulid_out()` - String parsing and formatting
- Binary I/O: `ulid_recv()`, `ulid_send()` - Network protocol support
- Generator: `gen_random_ulid()` - Thread-safe random ULID generation using `pg_strong_random()`
- Comparison operators: `ulid_eq()`, `ulid_lt()`, `ulid_gt()`, etc.
- `ulid_cmp()` - Main comparison function for B-tree indexing
- Sort support: `ulid_sortsupport()` with abbreviated key optimization
- Hash support: `ulid_hash()`, `ulid_hash_extended()` for hash indexing

**`pg_ulid--0.1.0.sql`** - SQL DDL that defines:
- The `ulid` data type with I/O functions
- All comparison operators (`<`, `<=`, `=`, `>=`, `>`, `<>`)
- B-tree operator class (with sort support for fast ORDER BY)
- Hash operator class (for hash indexes and joins)
- `gen_random_ulid()` function

### Version Compatibility

Supports PostgreSQL 12-18 with conditional compilation:
- Pre-PostgreSQL 13: Uses `access/hash.h` for hash functions
- PostgreSQL 13+: Uses `common/hashfn.h`
- Pre-PostgreSQL 15: Provides custom `ssup_datum_unsigned_cmp()`

## Testing

Tests follow PGXN standard structure:
- **test/sql/ulid.sql** - Input SQL test cases
- **test/expected/ulid.out** - Expected output
- **out/** - Generated test results (gitignored except .gitkeep)

The `test.sh` script uses the `pgxn/pgxn-tools` Docker image for reproducible testing across PostgreSQL versions.

### Testing a Single PostgreSQL Version

```bash
# Default (PostgreSQL 18)
./test.sh

# Specific version
PG_VERSION=12 ./test.sh
```

### Adding New Tests

1. Add test SQL to `test/sql/ulid.sql`
2. Run `./test.sh` to generate output
3. Review `out/ulid.out` for correctness
4. Copy to `test/expected/ulid.out` if output is correct

## PostgreSQL Extension Conventions

### Function Declarations
All C functions exposed to SQL must have:
- `PG_FUNCTION_INFO_V1(function_name);` macro
- `Datum function_name(PG_FUNCTION_ARGS)` signature
- `PG_RETURN_*` macros for return values
- `PG_GETARG_*` macros for arguments

### SQL Function Properties
Functions in the SQL file should specify:
- **IMMUTABLE**: Output depends only on input (comparison, I/O)
- **VOLATILE**: Output varies (random generation)
- **PARALLEL SAFE**: Can run in parallel workers (most functions)
- **STRICT**: Returns NULL if any argument is NULL

## Development Workflow

1. **Make changes** to C code in `src/` or SQL in `pg_ulid--*.sql`
2. **Rebuild**: `make clean && make`
3. **Reinstall**: `sudo make install` (or use Docker)
4. **Test**: `./test.sh` to verify all tests pass
5. **Format**: `make -f Makefile.lint format` before committing
6. **Lint**: `make -f Makefile.lint check` to catch issues

## Docker-based Development

```bash
# Build Docker image with extension
docker build -t postgres-ulid .

# Run PostgreSQL with extension installed
docker run -d -p 5432:5432 postgres-ulid

# Test with specific version
docker build --build-arg PG_VERSION=15 -t postgres-ulid:15 .
```

## PGXN Distribution

This extension is designed for PGXN (PostgreSQL Extension Network) distribution:
- **META.json** contains all PGXN metadata
- Version is defined in both `META.json` and `pg_ulid.control`
- When bumping versions, update both files and create upgrade SQL scripts named `pg_ulid--<old>--<new>.sql`

## Important Implementation Details

### Crockford Base32 Encoding
Uses alphabet: `0123456789ABCDEFGHJKMNPQRSTVWXYZ`
- Excludes I, L, O, U to avoid visual confusion
- Case-insensitive input, uppercase output
- 26 characters encode 130 bits (128 used, 2 bits overflow)

### Performance Optimizations
- **Abbreviated keys**: First 8 bytes used for fast sorting without dereferencing
- **Inline comparison**: `memcmp()` for full 16-byte comparison
- **Sort support**: Custom comparator registered for efficient ORDER BY
- **Binary protocol**: Efficient send/recv for client-server communication

### Thread Safety
The `gen_random_ulid()` function uses PostgreSQL's `pg_strong_random()` which is thread-safe and cryptographically secure.
