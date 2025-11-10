SET client_min_messages = error;
\set ECHO none
CREATE EXTENSION ulid;
\set ECHO all

CREATE TABLE ulids (
    ulid_test1 ulid,
    ulid_test2 ulid
);

CREATE INDEX ulid_test1_b ON ulids (ulid_test1);
CREATE INDEX ulid_test2_h ON ulids USING HASH (ulid_test2);

INSERT INTO ulids (ulid_test1, ulid_test2)
VALUES
    ('01H00000000000000000000000', '01H00000000000000000000000'),
    ('02000000000000000000000000', '02000000000000000000000000'),
    ('07000000000000000000000000', '07000000000000000000000000');

SELECT LENGTH(gen_random_ulid()::TEXT);

SET enable_seqscan = off;
SELECT ulid_test1 FROM ulids WHERE ulid_test1 <= '07000000000000000000000000';
SELECT ulid_test1 FROM ulids WHERE ulid_test1 < gen_random_ulid();
SELECT ulid_test1 FROM ulids WHERE ulid_test1 >= '01H00000000000000000000000';
SELECT ulid_test1 FROM ulids WHERE ulid_test1 > gen_random_ulid();
SELECT ulid_test1 FROM ulids WHERE ulid_test1 <> gen_random_ulid();
SELECT ulid_test1 FROM ulids WHERE ulid_test1 = '01H00000000000000000000000';

SELECT ulid_test2 FROM ulids WHERE ulid_test2 = '01H00000000000000000000000';
SELECT ulid_test2 FROM ulids WHERE ulid_test2 <> '02000000000000000000000000';

INSERT INTO ulids (ulid_test1, ulid_test2)
VALUES
    ('01HN64YSHF6P620FAY6YAJHQRK', '01HN64YSHFVRED3MZ41CFA2B91'),
    ('01HN64YSHFEB58ZAH8AV4HTTBT', '01HN64YSHF5R3F07A8440PMDZR'),
    ('01HN64YSHFFA1RXFMZ9R1W8SBV', '01HN64YSHF2S74QQNCDAD15C0S'),
    ('01HN64YSHF8QPCNP0FE4VNK6J7', '01HN64YSHFMZKAF6RBQVP97YN0'),
    ('01HN64YSHFZQXPJWNGGG2455V3', '01HN64YSHF7VGB658863XBS216');

SELECT ulid_test1 FROM ulids ORDER BY ulid_test1 ASC;
SELECT ulid_test2 FROM ulids ORDER BY ulid_test2 DESC;

EXPLAIN SELECT ulid_test1 FROM ulids ORDER BY ulid_test1 ASC;

CREATE TABLE ulids_copy (
    ulid_test1 ulid,
    ulid_test2 ulid
);

COPY ulids TO '/tmp/ulids'  WITH (FORMAT binary);
COPY ulids_copy FROM '/tmp/ulids' WITH (FORMAT binary);

SELECT * FROM ulids;
SELECT * FROM ulids_copy;

DROP TABLE ulids;
DROP TABLE ulids_copy;

CREATE TABLE ulids (
   ulid_test1 ulid PRIMARY KEY,
   ulid_test2 ulid
);

INSERT INTO ulids (ulid_test1, ulid_test2)
SELECT gen_random_ulid(), gen_random_ulid() FROM generate_series(1, 1000000);

SELECT * FROM ulids WHERE ulid_test1 = ulid_test2;

-- Test edge cases
-- Test overflow boundary (first character > '7' should fail)
DO $$
BEGIN
    PERFORM '80000000000000000000000000'::ulid;
    RAISE EXCEPTION 'Should have failed on overflow';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

-- Test invalid characters
DO $$
BEGIN
    PERFORM '01H0000000000000000000000I'::ulid;  -- 'I' is invalid
    RAISE EXCEPTION 'Should have failed on invalid character';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

-- Test wrong length (too short)
DO $$
BEGIN
    PERFORM '01H0000000000000000000000'::ulid;  -- 25 chars (too short)
    RAISE EXCEPTION 'Should have failed on wrong length';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

-- Test wrong length (too long)
DO $$
BEGIN
    PERFORM '01H00000000000000000000000000'::ulid;  -- 29 chars (too long)
    RAISE EXCEPTION 'Should have failed on wrong length';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

-- Test case insensitivity
SELECT '01h00000000000000000000000'::ulid = '01H00000000000000000000000'::ulid AS case_insensitive_test;

-- Test maximum valid ULID (boundary case)
SELECT '7ZZZZZZZZZZZZZZZZZZZZZZZZZ'::ulid AS max_valid_ulid;

-- Test invalid characters L, O, U at end
DO $$
BEGIN
    PERFORM '01H000000000000000000000L'::ulid;  -- 'L' is invalid
    RAISE EXCEPTION 'Should have failed on invalid character L';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

DO $$
BEGIN
    PERFORM '01H000000000000000000000O'::ulid;  -- 'O' is invalid
    RAISE EXCEPTION 'Should have failed on invalid character O';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

DO $$
BEGIN
    PERFORM '01H000000000000000000000U'::ulid;  -- 'U' is invalid
    RAISE EXCEPTION 'Should have failed on invalid character U';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

-- Test invalid characters at beginning
DO $$
BEGIN
    PERFORM 'I1H00000000000000000000000'::ulid;  -- 'I' at start
    RAISE EXCEPTION 'Should have failed on invalid character at start';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

-- Test invalid characters in middle
DO $$
BEGIN
    PERFORM '01H0000000L000000000000000'::ulid;  -- 'L' in middle
    RAISE EXCEPTION 'Should have failed on invalid character in middle';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

-- Test special characters
DO $$
BEGIN
    PERFORM '01H00000000000000000000-00'::ulid;  -- '-' is invalid
    RAISE EXCEPTION 'Should have failed on special character';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

DO $$
BEGIN
    PERFORM '01H00000000000000000000_00'::ulid;  -- '_' is invalid
    RAISE EXCEPTION 'Should have failed on special character';
EXCEPTION
    WHEN others THEN
        -- Expected to fail
        NULL;
END $$;

-- Test NULL handling
SELECT NULL::ulid IS NULL AS null_test;
INSERT INTO ulids (ulid_test1, ulid_test2) VALUES (gen_random_ulid(), NULL);
SELECT COUNT(*) FROM ulids WHERE ulid_test2 IS NULL;

-- Test extended hash function
SELECT ulid_hash_extended('01H00000000000000000000000'::ulid, 42) IS NOT NULL AS hash_extended_test;

-- Test comparison with self
SELECT gen_random_ulid() = gen_random_ulid() AS different_ulids;

-- Test monotonicity (ULIDs generated in sequence should be sortable)
CREATE TEMPORARY TABLE ulid_sequence AS
SELECT gen_random_ulid() AS id FROM generate_series(1, 100);

-- Verify all ULIDs are unique
SELECT COUNT(DISTINCT id) = 100 AS all_unique FROM ulid_sequence;

-- Test string representation round-trip
SELECT id::text::ulid = id AS roundtrip_test FROM ulid_sequence LIMIT 1;

DROP TABLE ulid_sequence;