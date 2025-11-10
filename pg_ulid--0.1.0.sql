-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_ulid" to load this file. \quit

CREATE TYPE ulid;
CREATE FUNCTION ulid_in (cstring)
    RETURNS ulid
    AS 'MODULE_PATHNAME', 'ulid_in'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_out (ulid)
    RETURNS cstring AS 'MODULE_PATHNAME', 'ulid_out'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_recv (internal)
    RETURNS ulid AS 'MODULE_PATHNAME', 'ulid_recv'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_send (ulid)
    RETURNS bytea AS 'MODULE_PATHNAME', 'ulid_send'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE TYPE ulid (
    INPUT = ulid_in,
    OUTPUT = ulid_out,
    RECEIVE = ulid_recv,
    SEND = ulid_send,
    INTERNALLENGTH = 16,
    ALIGNMENT = double,
    STORAGE = plain
);
CREATE FUNCTION gen_random_ulid()
    RETURNS ulid AS 'MODULE_PATHNAME', 'gen_random_ulid'
    LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION ulid_cmp(ulid, ulid)
    RETURNS int4
    AS 'MODULE_PATHNAME', 'ulid_cmp'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_eq(ulid, ulid)
    RETURNS bool
    AS 'MODULE_PATHNAME', 'ulid_eq'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_ne(ulid, ulid)
    RETURNS bool AS 'MODULE_PATHNAME', 'ulid_ne'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_ge(ulid, ulid)
    RETURNS bool AS 'MODULE_PATHNAME', 'ulid_ge'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_gt(ulid, ulid)
    RETURNS bool AS 'MODULE_PATHNAME', 'ulid_gt'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_le(ulid, ulid)
    RETURNS bool AS 'MODULE_PATHNAME', 'ulid_le'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION ulid_lt(ulid, ulid)
    RETURNS bool AS 'MODULE_PATHNAME', 'ulid_lt'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION ulid_sortsupport(internal)
    RETURNS VOID AS 'MODULE_PATHNAME', 'ulid_sortsupport'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION ulid_hash(ulid)
    RETURNS int AS 'MODULE_PATHNAME', 'ulid_hash'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION ulid_hash_extended(ulid, bigint)
    RETURNS bigint AS 'MODULE_PATHNAME', 'ulid_hash_extended'
    LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OPERATOR <> ( PROCEDURE = ulid_ne,
	LEFTARG = ulid, RIGHTARG = ulid,
	NEGATOR = =, RESTRICT = neqsel);
CREATE OPERATOR > ( PROCEDURE = ulid_gt,
	LEFTARG = ulid, RIGHTARG = ulid,
	COMMUTATOR = <, NEGATOR = <=);
CREATE OPERATOR < ( PROCEDURE = ulid_lt,
	LEFTARG = ulid, RIGHTARG = ulid,
	COMMUTATOR = >, NEGATOR = >=);
CREATE OPERATOR >= ( PROCEDURE = ulid_ge,
	LEFTARG = ulid, RIGHTARG = ulid,
	COMMUTATOR = <=, NEGATOR = <);
CREATE OPERATOR <= ( PROCEDURE = ulid_le,
	LEFTARG = ulid, RIGHTARG = ulid,
	COMMUTATOR = >=, NEGATOR = >);
CREATE OPERATOR = ( PROCEDURE = ulid_eq,
	LEFTARG = ulid, RIGHTARG = ulid,
	COMMUTATOR = =, NEGATOR = <>, RESTRICT = eqsel, HASHES, MERGES);

CREATE OPERATOR CLASS ulid_ops DEFAULT FOR TYPE ulid USING btree AS
       OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
       FUNCTION 1 ulid_cmp(ulid, ulid),
       FUNCTION 2 ulid_sortsupport(internal);

CREATE OPERATOR CLASS ulid_ops DEFAULT FOR TYPE ulid USING hash AS
       OPERATOR 1 =, FUNCTION 1 ulid_hash(ulid), FUNCTION 2 ulid_hash_extended(ulid, bigint);

-- Documentation comments
COMMENT ON TYPE ulid IS 'Universally Unique Lexicographically Sortable Identifier (ULID) - 128-bit identifier with timestamp and randomness';
COMMENT ON FUNCTION gen_random_ulid() IS 'Generate a random ULID with embedded millisecond timestamp';
COMMENT ON FUNCTION ulid_cmp(ulid, ulid) IS 'Compare two ULIDs for sorting';
COMMENT ON OPERATOR CLASS ulid_ops USING btree IS 'B-tree operator class for ULID with optimized sorting support';
COMMENT ON OPERATOR CLASS ulid_ops USING hash IS 'Hash operator class for ULID equality operations';
