-- Basic ULID functionality tests
-- Tests extension creation, basic data type operations, and gen_random_ulid()

SET client_min_messages = error;
\set ECHO none
CREATE EXTENSION pg_ulid;
\set ECHO all

-- Test basic table creation with ulid columns
CREATE TABLE ulids_basic (
    id ulid PRIMARY KEY,
    secondary_id ulid
);

-- Test gen_random_ulid() function
SELECT LENGTH(gen_random_ulid()::TEXT) AS ulid_length;

-- Test basic insert
INSERT INTO ulids_basic VALUES (gen_random_ulid(), gen_random_ulid());

-- Test case insensitivity
SELECT '01h00000000000000000000000'::ulid = '01H00000000000000000000000'::ulid AS case_insensitive_test;

-- Test maximum valid ULID (boundary case)
SELECT '7ZZZZZZZZZZZZZZZZZZZZZZZZZ'::ulid AS max_valid_ulid;

-- Test NULL handling
SELECT NULL::ulid IS NULL AS null_test;
INSERT INTO ulids_basic (id, secondary_id) VALUES (gen_random_ulid(), NULL);
SELECT COUNT(*) FROM ulids_basic WHERE secondary_id IS NULL;

-- Test extended hash function
SELECT ulid_hash_extended('01H00000000000000000000000'::ulid, 42) IS NOT NULL AS hash_extended_test;

-- Test comparison with self (two different generated ULIDs should not be equal)
SELECT gen_random_ulid() = gen_random_ulid() AS different_ulids;

-- Test monotonicity (ULIDs generated in sequence should be sortable)
CREATE TEMPORARY TABLE ulid_sequence AS
SELECT gen_random_ulid() AS id FROM generate_series(1, 100);

-- Verify all ULIDs are unique
SELECT COUNT(DISTINCT id) = 100 AS all_unique FROM ulid_sequence;

-- Test string representation round-trip
SELECT id::text::ulid = id AS roundtrip_test FROM ulid_sequence LIMIT 1;

-- Cleanup
DROP TABLE ulid_sequence;
DROP TABLE ulids_basic;
