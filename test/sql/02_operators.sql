-- ULID comparison operator tests
-- Tests all comparison operators: =, <>, <, <=, >, >=

SET client_min_messages = error;
\set ECHO none
CREATE EXTENSION pg_ulid;
\set ECHO all

-- Create test table
CREATE TABLE ulids_ops (
    ulid_test1 ulid,
    ulid_test2 ulid
);

-- Insert test data with known values
INSERT INTO ulids_ops (ulid_test1, ulid_test2)
VALUES
    ('01H00000000000000000000000', '01H00000000000000000000000'),
    ('02000000000000000000000000', '02000000000000000000000000'),
    ('07000000000000000000000000', '07000000000000000000000000');

-- Test less than or equal (<=)
SELECT ulid_test1 FROM ulids_ops WHERE ulid_test1 <= '07000000000000000000000000' ORDER BY ulid_test1;

-- Test less than (<)
SELECT ulid_test1 FROM ulids_ops WHERE ulid_test1 < '07000000000000000000000000' ORDER BY ulid_test1;

-- Test greater than or equal (>=)
SELECT ulid_test1 FROM ulids_ops WHERE ulid_test1 >= '02000000000000000000000000' ORDER BY ulid_test1;

-- Test greater than (>)
SELECT ulid_test1 FROM ulids_ops WHERE ulid_test1 > '01H00000000000000000000000' ORDER BY ulid_test1;

-- Test not equal (<>)
SELECT ulid_test1 FROM ulids_ops WHERE ulid_test1 <> '02000000000000000000000000' ORDER BY ulid_test1;

-- Test equal (=)
SELECT ulid_test1 FROM ulids_ops WHERE ulid_test1 = '01H00000000000000000000000';

-- Test hash index equality
SELECT ulid_test2 FROM ulids_ops WHERE ulid_test2 = '01H00000000000000000000000';
SELECT ulid_test2 FROM ulids_ops WHERE ulid_test2 <> '02000000000000000000000000' ORDER BY ulid_test2;

-- Cleanup
DROP TABLE ulids_ops;
