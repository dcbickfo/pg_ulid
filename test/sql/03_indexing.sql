-- ULID indexing tests
-- Tests B-tree and hash indexes, sorting, and EXPLAIN plans

SET client_min_messages = error;
\set ECHO none
CREATE EXTENSION pg_ulid;
\set ECHO all

-- Create table with indexed columns
CREATE TABLE ulids_idx (
    ulid_test1 ulid,
    ulid_test2 ulid
);

-- Create B-tree index (supports ordering)
CREATE INDEX ulid_test1_b ON ulids_idx (ulid_test1);

-- Create hash index (supports equality only)
CREATE INDEX ulid_test2_h ON ulids_idx USING HASH (ulid_test2);

-- Insert test data
INSERT INTO ulids_idx (ulid_test1, ulid_test2)
VALUES
    ('01H00000000000000000000000', '01H00000000000000000000000'),
    ('02000000000000000000000000', '02000000000000000000000000'),
    ('07000000000000000000000000', '07000000000000000000000000'),
    ('01HN64YSHF6P620FAY6YAJHQRK', '01HN64YSHFVRED3MZ41CFA2B91'),
    ('01HN64YSHFEB58ZAH8AV4HTTBT', '01HN64YSHF5R3F07A8440PMDZR'),
    ('01HN64YSHFFA1RXFMZ9R1W8SBV', '01HN64YSHF2S74QQNCDAD15C0S'),
    ('01HN64YSHF8QPCNP0FE4VNK6J7', '01HN64YSHFMZKAF6RBQVP97YN0'),
    ('01HN64YSHFZQXPJWNGGG2455V3', '01HN64YSHF7VGB658863XBS216');

-- Test ascending sort (should use B-tree index)
SELECT ulid_test1 FROM ulids_idx ORDER BY ulid_test1 ASC;

-- Test descending sort
SELECT ulid_test2 FROM ulids_idx ORDER BY ulid_test2 DESC;

-- Verify index is used for sorting
EXPLAIN SELECT ulid_test1 FROM ulids_idx ORDER BY ulid_test1 ASC;

-- Test index scan with WHERE clause
SET enable_seqscan = off;
SELECT ulid_test1 FROM ulids_idx WHERE ulid_test1 <= '07000000000000000000000000' ORDER BY ulid_test1;

-- Cleanup
DROP TABLE ulids_idx;
