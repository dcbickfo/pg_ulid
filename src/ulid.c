/*-------------------------------------------------------------------------
 *
 * ulid.c
 *    ULID (Universally Unique Lexicographically Sortable Identifier) data type
 *
 * Copyright (c) 2025
 *
 * Portions Copyright (c) 2007-2025, PostgreSQL Global Development Group
 * (Data type implementation patterns, sort support, and indexing structures)
 *
 * Crockford Base32 encoding/decoding inspired by public domain ULID
 * implementations including https://github.com/skeeto/ulid-c (Unlicense)
 *
 * This code is released under the MIT License.
 * See LICENSE file in the root directory.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "ulid.h"
#include "fmgr.h"
#include "port/pg_bswap.h"
#include "lib/stringinfo.h"
#include "libpq/pqformat.h"

/* PostgreSQL 12 has hash functions in access/hash.h */
#if PG_VERSION_NUM >= 130000
#include "common/hashfn.h"
#else
#include "access/hash.h"
#endif

#include "utils/sortsupport.h"
#include "utils/guc.h"
#include "lib/hyperloglog.h"
#include "utils/builtins.h"

#include <time.h>

PG_MODULE_MAGIC;

/* sortsupport for ulid */
typedef struct {
	int64 input_count; /* number of non-null values seen */
	bool estimating;   /* true if estimating cardinality */

	hyperLogLogState abbr_card; /* cardinality estimator */
} ulid_sortsupport_state;

/*
 * Unsigned datum comparator for sort support  (abbreviated keys).
 * Compares two Datum values as unsigned integers.
 */
static int ulid_abbrev_cmp(Datum x, Datum y, SortSupport ssup) {
	if (x < y) {
		return -1;
	}
	if (x > y) {
		return 1;
	}
	return 0;
}

Datum ulid_in(PG_FUNCTION_ARGS);
Datum ulid_out(PG_FUNCTION_ARGS);
Datum gen_random_ulid(PG_FUNCTION_ARGS);
Datum ulid_recv(PG_FUNCTION_ARGS);
Datum ulid_send(PG_FUNCTION_ARGS);
Datum ulid_lt(PG_FUNCTION_ARGS);
Datum ulid_le(PG_FUNCTION_ARGS);
Datum ulid_eq(PG_FUNCTION_ARGS);
Datum ulid_ge(PG_FUNCTION_ARGS);
Datum ulid_gt(PG_FUNCTION_ARGS);
Datum ulid_ne(PG_FUNCTION_ARGS);
Datum ulid_cmp(PG_FUNCTION_ARGS);
Datum ulid_hash(PG_FUNCTION_ARGS);
Datum ulid_hash_extended(PG_FUNCTION_ARGS);
Datum ulid_sortsupport(PG_FUNCTION_ARGS);
static void string_to_ulid(const char *source, pg_ulid_t *ulid,
                           struct Node *escontext);
static int ulid_fast_cmp(Datum x, Datum y, SortSupport ssup);
static bool ulid_abbrev_abort(int memtupcount, SortSupport ssup);
static Datum ulid_abbrev_convert(Datum original, SortSupport ssup);


PG_FUNCTION_INFO_V1(ulid_in);
Datum ulid_in(PG_FUNCTION_ARGS) {
	char *ulid_str = PG_GETARG_CSTRING(0);
	pg_ulid_t *ulid;

	ulid = (pg_ulid_t *)palloc(sizeof(*ulid));
	string_to_ulid(ulid_str, ulid, fcinfo->context);
	PG_RETURN_ULID_P(ulid);
}

PG_FUNCTION_INFO_V1(ulid_out);
Datum ulid_out(PG_FUNCTION_ARGS) {
	pg_ulid_t *ulid = PG_GETARG_ULID_P(0);
	char *ulid_str = (char *)palloc(ULID_ENCODED_LEN + 1);

	/*
	 * Convert 16-byte ULID to 26-character Crockford base32 string.
	 * Algorithm: Extract 5-bit chunks from the byte array and map to base32.
	 * First 10 characters encode the 48-bit timestamp (bytes 0-5).
	 * Last 16 characters encode the 80-bit random component (bytes 6-15).
	 */

	/*
	 * Encode 48-bit timestamp (bytes 0-5) -> characters 0-9
	 * Each character encodes 5 bits, extracted via bit masks and shifts.
	 * Example: byte[0] = AAAAA BBB -> char[0] = AAAAA, partial char[1] = BBB
	 */
	ulid_str[0] = C32_ENCODING[(ulid->data[0] & 224) >> 5]; /* bits 7-5 of byte 0 */
	ulid_str[1] = C32_ENCODING[ulid->data[0] & 31]; /* bits 4-0 of byte 0 */
	ulid_str[2] = C32_ENCODING[(ulid->data[1] & 248) >> 3]; /* bits 7-3 of byte 1 */
	ulid_str[3] =
		C32_ENCODING[((ulid->data[1] & 7) << 2) | ((ulid->data[2] & 192) >> 6)];
	ulid_str[4] = C32_ENCODING[(ulid->data[2] & 62) >> 1];
	ulid_str[5] =
		C32_ENCODING[((ulid->data[2] & 1) << 4) | ((ulid->data[3] & 240) >> 4)];
	ulid_str[6] = C32_ENCODING[((ulid->data[3] & 15) << 1) |
	                           ((ulid->data[4] & 128) >> 7)];
	ulid_str[7] = C32_ENCODING[(ulid->data[4] & 124) >> 2];
	ulid_str[8] =
		C32_ENCODING[((ulid->data[4] & 3) << 3) | ((ulid->data[5] & 224) >> 5)];
	ulid_str[9] = C32_ENCODING[ulid->data[5] & 31];

	/* Encode 80-bit random component (bytes 6-15) -> characters 10-25 */
	ulid_str[10] = C32_ENCODING[(ulid->data[6] & 248) >> 3];
	ulid_str[11] =
		C32_ENCODING[((ulid->data[6] & 7) << 2) | ((ulid->data[7] & 192) >> 6)];
	ulid_str[12] = C32_ENCODING[(ulid->data[7] & 62) >> 1];
	ulid_str[13] =
		C32_ENCODING[((ulid->data[7] & 1) << 4) | ((ulid->data[8] & 240) >> 4)];
	ulid_str[14] = C32_ENCODING[((ulid->data[8] & 15) << 1) |
	                            ((ulid->data[9] & 128) >> 7)];
	ulid_str[15] = C32_ENCODING[(ulid->data[9] & 124) >> 2];
	ulid_str[16] = C32_ENCODING[((ulid->data[9] & 3) << 3) |
	                            ((ulid->data[10] & 224) >> 5)];
	ulid_str[17] = C32_ENCODING[ulid->data[10] & 31];
	ulid_str[18] = C32_ENCODING[(ulid->data[11] & 248) >> 3];
	ulid_str[19] = C32_ENCODING[((ulid->data[11] & 7) << 2) |
	                            ((ulid->data[12] & 192) >> 6)];
	ulid_str[20] = C32_ENCODING[(ulid->data[12] & 62) >> 1];
	ulid_str[21] = C32_ENCODING[((ulid->data[12] & 1) << 4) |
	                            ((ulid->data[13] & 240) >> 4)];
	ulid_str[22] = C32_ENCODING[((ulid->data[13] & 15) << 1) |
	                            ((ulid->data[14] & 128) >> 7)];
	ulid_str[23] = C32_ENCODING[(ulid->data[14] & 124) >> 2];
	ulid_str[24] = C32_ENCODING[((ulid->data[14] & 3) << 3) |
	                            ((ulid->data[15] & 224) >> 5)];
	ulid_str[25] = C32_ENCODING[ulid->data[15] & 31];

	ulid_str[26] = '\0';

	PG_RETURN_CSTRING(ulid_str);
}


/*
 * Converts Crockford base32 string to the internal 16-byte binary
 * representation.
 *
 * Crockford base32 uses: 0-9, A-Z (excluding I, L, O, U)
 * Each character represents 5 bits.
 * 26 characters * 5 bits = 130 bits, but only 128 bits are used.
 */
static void string_to_ulid(const char *source, pg_ulid_t *ulid,
                           struct Node *escontext) {
	const unsigned char *src = (const unsigned char *)source;

	/* Parameter reserved for soft error handling in PostgreSQL 16+ */
	(void)escontext;

	if (strlen(source) != ULID_ENCODED_LEN) {
		ereport(ERROR, (errmsg("invalid ulid: incorrect length %d (expected %d)",
		                       (int)strlen(source), ULID_ENCODED_LEN)));
	}

	/* Validate each character is valid Crockford base32 */
	for (int i = 0; i < ULID_ENCODED_LEN; i++) {
		if (DEC[src[i]] == 0xFF) {
			ereport(ERROR,
			        (errmsg("invalid ulid: bad character at position %d", i)));
		}
	}

	/* First character must be <= '7' to prevent 128-bit overflow */
	if (src[0] > '7') {
		ereport(ERROR,
		        (errmsg("invalid ulid: value overflows 128 bit encoding")));
	}

	/* Decode timestamp (characters 0-9 -> bytes 0-5) */
	ulid->data[0] = (DEC[src[0]] << 5) | DEC[src[1]];
	ulid->data[1] = (DEC[src[2]] << 3) | (DEC[src[3]] >> 2);
	ulid->data[2] =
		(DEC[src[3]] << 6) | (DEC[src[4]] << 1) | (DEC[src[5]] >> 4);
	ulid->data[3] = (DEC[src[5]] << 4) | (DEC[src[6]] >> 1);
	ulid->data[4] =
		(DEC[src[6]] << 7) | (DEC[src[7]] << 2) | (DEC[src[8]] >> 3);
	ulid->data[5] = (DEC[src[8]] << 5) | DEC[src[9]];

	/* Decode random component (characters 10-25 -> bytes 6-15) */
	ulid->data[6] = (DEC[src[10]] << 3) | (DEC[src[11]] >> 2);
	ulid->data[7] =
		(DEC[src[11]] << 6) | (DEC[src[12]] << 1) | (DEC[src[13]] >> 4);
	ulid->data[8] = (DEC[src[13]] << 4) | (DEC[src[14]] >> 1);
	ulid->data[9] =
		(DEC[src[14]] << 7) | (DEC[src[15]] << 2) | (DEC[src[16]] >> 3);
	ulid->data[10] = (DEC[src[16]] << 5) | DEC[src[17]];
	ulid->data[11] = (DEC[src[18]] << 3) | (DEC[src[19]] >> 2);
	ulid->data[12] =
		(DEC[src[19]] << 6) | (DEC[src[20]] << 1) | (DEC[src[21]] >> 4);
	ulid->data[13] = (DEC[src[21]] << 4) | (DEC[src[22]] >> 1);
	ulid->data[14] =
		(DEC[src[22]] << 7) | (DEC[src[23]] << 2) | (DEC[src[24]] >> 3);
	ulid->data[15] = (DEC[src[24]] << 5) | DEC[src[25]];
}

PG_FUNCTION_INFO_V1(gen_random_ulid);
Datum gen_random_ulid(PG_FUNCTION_ARGS) {
	pg_ulid_t *ulid = palloc(ULID_LEN);
	struct timespec ts;
	uint64_t tms;

	/*
	 * Set first 48 bits to unix epoch timestamp
	 */
	if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
		ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
		                errmsg("could not get CLOCK_REALTIME")));
	}

	tms = ((uint64_t)ts.tv_sec * 1000) + ((uint64_t)ts.tv_nsec / 1000000);
	tms = pg_hton64(tms << 16);
	memcpy(&ulid->data[0], &tms, 6);

	if (!pg_strong_random(&ulid->data[6], ULID_LEN - 6)) {
		ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
		                errmsg("could not generate random values")));
	}

	PG_RETURN_ULID_P(ulid);
}

PG_FUNCTION_INFO_V1(ulid_recv);
Datum ulid_recv(PG_FUNCTION_ARGS) {
	StringInfo buffer = (StringInfo)PG_GETARG_POINTER(0);
	pg_ulid_t *ulid;

	ulid = (pg_ulid_t *)palloc(ULID_LEN);
	memcpy(ulid->data, pq_getmsgbytes(buffer, ULID_LEN), ULID_LEN);
	PG_RETURN_POINTER(ulid);
}

PG_FUNCTION_INFO_V1(ulid_send);
Datum ulid_send(PG_FUNCTION_ARGS) {
	pg_ulid_t *ulid = PG_GETARG_ULID_P(0);
	StringInfoData buffer;

	pq_begintypsend(&buffer);
	pq_sendbytes(&buffer, (const char *)ulid->data, ULID_LEN);
	PG_RETURN_BYTEA_P(pq_endtypsend(&buffer));
}

PG_FUNCTION_INFO_V1(ulid_lt);
Datum ulid_lt(PG_FUNCTION_ARGS) {
	const pg_ulid_t *arg1 = PG_GETARG_ULID_P(0);
	const pg_ulid_t *arg2 = PG_GETARG_ULID_P(1);

	PG_RETURN_BOOL(ulid_internal_cmp(arg1, arg2) < 0);
}

PG_FUNCTION_INFO_V1(ulid_le);
Datum ulid_le(PG_FUNCTION_ARGS) {
	const pg_ulid_t *arg1 = PG_GETARG_ULID_P(0);
	const pg_ulid_t *arg2 = PG_GETARG_ULID_P(1);

	PG_RETURN_BOOL(ulid_internal_cmp(arg1, arg2) <= 0);
}

PG_FUNCTION_INFO_V1(ulid_eq);
Datum ulid_eq(PG_FUNCTION_ARGS) {
	const pg_ulid_t *arg1 = PG_GETARG_ULID_P(0);
	const pg_ulid_t *arg2 = PG_GETARG_ULID_P(1);

	PG_RETURN_BOOL(ulid_internal_cmp(arg1, arg2) == 0);
}

PG_FUNCTION_INFO_V1(ulid_ge);
Datum ulid_ge(PG_FUNCTION_ARGS) {
	const pg_ulid_t *arg1 = PG_GETARG_ULID_P(0);
	const pg_ulid_t *arg2 = PG_GETARG_ULID_P(1);

	PG_RETURN_BOOL(ulid_internal_cmp(arg1, arg2) >= 0);
}

PG_FUNCTION_INFO_V1(ulid_gt);
Datum ulid_gt(PG_FUNCTION_ARGS) {
	const pg_ulid_t *arg1 = PG_GETARG_ULID_P(0);
	const pg_ulid_t *arg2 = PG_GETARG_ULID_P(1);

	PG_RETURN_BOOL(ulid_internal_cmp(arg1, arg2) > 0);
}

PG_FUNCTION_INFO_V1(ulid_ne);
Datum ulid_ne(PG_FUNCTION_ARGS) {
	const pg_ulid_t *arg1 = PG_GETARG_ULID_P(0);
	const pg_ulid_t *arg2 = PG_GETARG_ULID_P(1);

	PG_RETURN_BOOL(ulid_internal_cmp(arg1, arg2) != 0);
}

/* handler for btree index operator */
PG_FUNCTION_INFO_V1(ulid_cmp);
Datum ulid_cmp(PG_FUNCTION_ARGS) {
	const pg_ulid_t *arg1 = PG_GETARG_ULID_P(0);
	const pg_ulid_t *arg2 = PG_GETARG_ULID_P(1);

	PG_RETURN_INT32(ulid_internal_cmp(arg1, arg2));
}

/*
 * Sort support strategy routine
 */
PG_FUNCTION_INFO_V1(ulid_sortsupport);
Datum ulid_sortsupport(PG_FUNCTION_ARGS) {
	SortSupport ssup = (SortSupport)PG_GETARG_POINTER(0);

	ssup->comparator = ulid_fast_cmp;
	ssup->ssup_extra = NULL;

	if (ssup->abbreviate) {
		ulid_sortsupport_state *uss;
		MemoryContext oldcontext;

		oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

		uss = palloc(sizeof(ulid_sortsupport_state));
		uss->input_count = 0;
		uss->estimating = true;
		initHyperLogLog(&uss->abbr_card, 10);

		ssup->ssup_extra = uss;

		ssup->comparator = ulid_abbrev_cmp;
		ssup->abbrev_converter = ulid_abbrev_convert;
		ssup->abbrev_abort = ulid_abbrev_abort;
		ssup->abbrev_full_comparator = ulid_fast_cmp;

		MemoryContextSwitchTo(oldcontext);
	}

	PG_RETURN_VOID();
}

/*
 * SortSupport comparison func
 */
static int ulid_fast_cmp(Datum x, Datum y, SortSupport ssup) {
	const pg_ulid_t *arg1 = DatumGetULIDP(x);
	const pg_ulid_t *arg2 = DatumGetULIDP(y);

	return ulid_internal_cmp(arg1, arg2);
}

/*
 * Callback for estimating effectiveness of abbreviated key optimization.
 *
 * We pay no attention to the cardinality of the non-abbreviated data, because
 * there is no equality fast-path within authoritative ulid comparator.
 */
static bool ulid_abbrev_abort(int memtupcount, SortSupport ssup) {
	ulid_sortsupport_state *uss = ssup->ssup_extra;
	double abbr_card;

	if (memtupcount < 10000 || uss->input_count < 10000 || !uss->estimating) {
		return false;
	}

	abbr_card = estimateHyperLogLog(&uss->abbr_card);

	/*
	 * If we have >100k distinct values, then even if we were sorting many
	 * billion rows we'd likely still break even, and the penalty of undoing
	 * that many rows of abbrevs would probably not be worth it.  Stop even
	 * counting at that point.
	 */
	if (abbr_card > 100000.0) {
#ifdef TRACE_SORT
		if (trace_sort) {
			elog(LOG,
			     "ulid_abbrev: estimation ends at cardinality %f"
			     " after " INT64_FORMAT " values (%d rows)",
			     abbr_card, uss->input_count, memtupcount);
		}
#endif
		uss->estimating = false;
		return false;
	}

	/*
	 * Target minimum cardinality is 1 per ~2k of non-null inputs.  0.5 row
	 * fudge factor allows us to abort earlier on genuinely pathological data
	 * where we've had exactly one abbreviated value in the first 2k
	 * (non-null) rows.
	 */
	if (abbr_card < (uss->input_count / 2000.0) + 0.5) {
#ifdef TRACE_SORT
		if (trace_sort) {
			elog(LOG,
			     "ulid_abbrev: aborting abbreviation at cardinality %f"
			     " below threshold %f after " INT64_FORMAT " values (%d rows)",
			     abbr_card, (uss->input_count / 2000.0) + 0.5, uss->input_count,
			     memtupcount);
		}
#endif
		return true;
	}

#ifdef TRACE_SORT
	if (trace_sort) {
		elog(LOG,
		     "ulid_abbrev: cardinality %f after " INT64_FORMAT
		     " values (%d rows)",
		     abbr_card, uss->input_count, memtupcount);
	}
#endif

	return false;
}

/*
 * Conversion routine for sortsupport.  Converts original ulid representation
 * to abbreviated key representation.
 *
 * Strategy: Pack the first sizeof(Datum) bytes of ULID data into a Datum.
 * On 64-bit systems, this includes the full 48-bit timestamp (bytes 0-5)
 * plus 2 bytes of randomness (bytes 6-7), providing excellent discrimination.
 *
 * Since ULID timestamps are stored in big-endian format, we use
 * DatumBigEndianToNative() to convert to native byte order for fast
 * unsigned integer comparison.
 */
static Datum ulid_abbrev_convert(Datum original, SortSupport ssup) {
	ulid_sortsupport_state *uss = ssup->ssup_extra;
	const pg_ulid_t *authoritative = DatumGetULIDP(original);
	Datum res;

	memcpy(&res, authoritative->data, sizeof(Datum));
	uss->input_count += 1;

	if (uss->estimating) {
		uint32 tmp;

#if SIZEOF_DATUM == 8
		tmp = (uint32)res ^ (uint32)((uint64)res >> 32);
#else /* SIZEOF_DATUM != 8 */
		tmp = (uint32)res;
#endif

		addHyperLogLog(&uss->abbr_card, DatumGetUInt32(hash_uint32(tmp)));
	}

	/*
	 * Byteswap on little-endian machines.
	 *
	 * This is needed so that ulid_abbrev_cmp() (an unsigned integer
	 * 3-way comparator) works correctly on all platforms.  If we didn't do
	 * this, the comparator would have to call memcmp() with a pair of
	 * pointers to the first byte of each abbreviated key, which is slower.
	 */
	res = DatumBigEndianToNative(res);

	return res;
}

/* hash index support */
PG_FUNCTION_INFO_V1(ulid_hash);
Datum ulid_hash(PG_FUNCTION_ARGS) {
	const pg_ulid_t *key = PG_GETARG_ULID_P(0);

	return hash_any(key->data, ULID_LEN);
}

PG_FUNCTION_INFO_V1(ulid_hash_extended);
Datum ulid_hash_extended(PG_FUNCTION_ARGS) {
	const pg_ulid_t *key = PG_GETARG_ULID_P(0);
	return hash_any_extended(key->data, ULID_LEN, PG_GETARG_INT64(1));
}
