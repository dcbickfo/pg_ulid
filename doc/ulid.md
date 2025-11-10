# ULID Extension for PostgreSQL

## Synopsis

```sql
CREATE EXTENSION ulid;

SELECT gen_random_ulid();
-- Output: 01HN64YSHFEB58ZAH8AV4HTTBT
```

## Description

The `ulid` extension provides a native ULID (Universally Unique Lexicographically Sortable Identifier) data type for PostgreSQL. ULIDs are 128-bit identifiers that combine a timestamp with random data, making them both unique and sortable by creation time.

### ULID Format

A ULID consists of:
- **48-bit timestamp**: Milliseconds since Unix epoch
- **80-bit randomness**: Cryptographically secure random data

Encoded as a 26-character case-insensitive string using Crockford Base32:
```
01AN4Z07BY79KA1307SR9X4MV3
|----------|------------|
 Timestamp    Randomness
```

## Data Type

### `ulid`

Stores a 128-bit ULID value internally as 16 bytes.

**Properties:**
- Lexicographically sortable by timestamp
- Case-insensitive string representation
- URL-safe encoding (no special characters)
- Compact: 26 characters vs 36 for UUID

## Functions

### `gen_random_ulid() → ulid`

Generates a new ULID with the current timestamp and cryptographically secure random data.

```sql
SELECT gen_random_ulid();
```

**Returns:** A new ULID value

**Characteristics:**
- `VOLATILE` - Returns different values on each call
- Uses PostgreSQL's `pg_strong_random()` for secure randomness
- Timestamp precision: milliseconds

## Operators

The `ulid` type supports all standard comparison operators:

| Operator | Description |
|----------|-------------|
| `<` | Less than |
| `<=` | Less than or equal |
| `=` | Equal |
| `<>` or `!=` | Not equal |
| `>=` | Greater than or equal |
| `>` | Greater than |

All comparison operators are `PARALLEL SAFE` and `IMMUTABLE`.

## Indexing

### B-tree Index (Default)

Supports all comparison operations and `ORDER BY`:

```sql
CREATE INDEX idx_events_ulid ON events (event_id);

-- Efficient range queries
SELECT * FROM events
WHERE event_id >= '01HN64YSHF00000000000000'
  AND event_id < '01HN65000000000000000000'
ORDER BY event_id;
```

**Features:**
- Optimized sort support via abbreviated keys
- All comparison operators
- Fast range scans

### Hash Index

Supports equality operations only:

```sql
CREATE INDEX idx_events_ulid_hash ON events USING HASH (event_id);

-- Fast equality lookups
SELECT * FROM events WHERE event_id = '01HN64YSHFEB58ZAH8AV4HTTBT';
```

## Type Conversion

### From String

```sql
SELECT '01HN64YSHFEB58ZAH8AV4HTTBT'::ulid;
```

**Validation:**
- Must be exactly 26 characters
- Case-insensitive (automatically normalized)
- First character must be ≤ '7' (prevents 128-bit overflow)
- Invalid characters: I, L, O, U (Crockford Base32 exclusions)

### To String

```sql
SELECT event_id::text FROM events;
```

Returns uppercase 26-character Crockford Base32 encoding.

## Usage Examples

### Table with ULID Primary Key

```sql
CREATE TABLE events (
    event_id ulid PRIMARY KEY DEFAULT gen_random_ulid(),
    event_type TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO events (event_type) VALUES ('user_signup');
```

### Sorting by Creation Time

ULIDs naturally sort by creation time:

```sql
SELECT event_id, created_at
FROM events
ORDER BY event_id ASC;  -- Chronological order
```

### Time-Range Queries

Generate ULID boundaries for time ranges:

```sql
-- Get events from the last hour
-- (requires extracting timestamp from ULID or using timestamp column)
SELECT * FROM events
WHERE event_id > gen_random_ulid()
ORDER BY event_id;
```

## Comparison with UUID

| Feature | ULID | UUID v4 |
|---------|------|---------|
| Size | 128 bits | 128 bits |
| String Length | 26 chars | 36 chars (with hyphens) |
| Sortable | ✅ Yes (by time) | ❌ No |
| Randomness | 80 bits | 122 bits |
| URL-Safe | ✅ Yes | ⚠️ Needs encoding |
| Timestamp | ✅ Embedded | ❌ No |
| Collision Resistance | High | Very High |

## Technical Details

### Internal Representation

- Storage: 16 bytes (128 bits)
- Alignment: Natural (no padding)
- Pass-by-reference type

### Encoding

Uses Crockford Base32 alphabet:
```
0123456789ABCDEFGHJKMNPQRSTVWXYZ
```

Excludes I, L, O, U to avoid confusion with 1, 1, 0, V.

### Performance

- Comparison: `memcmp` on 16 bytes
- Sorting: Optimized with abbreviated key support
- Hashing: Efficient hash function for hash indexes

## Security Considerations

- Random component uses `pg_strong_random()` (cryptographically secure)
- 80 bits of entropy provides strong collision resistance
- Not suitable for cryptographic secrets (timestamp is predictable)

## Limitations

- Timestamp limited to millisecond precision
- Maximum timestamp: year 10889 (48-bit millisecond counter)
- Not compatible with UUID functions/casts
- Case-insensitive input but always outputs uppercase

## See Also

- [ULID Specification](https://github.com/ulid/spec)
- [Crockford Base32](https://www.crockford.com/base32.html)
- PostgreSQL `uuid` type
- PostgreSQL `gen_random_uuid()` function
