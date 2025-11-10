#!/usr/bin/env bash
#
# Test runner for ULID PostgreSQL extension
# Uses pgxn-tools Docker image for reproducible testing
#
# Usage:
#   ./test.sh              # Test with PostgreSQL 18 (default)
#   PG_VERSION=15 ./test.sh # Test with PostgreSQL 15
#   ./test.sh clean        # Clean build artifacts

set -e

# Default PostgreSQL version
PG_VERSION=${PG_VERSION:-18}

# Create output directory for test results
mkdir -p out

# Clean mode
if [ "$1" = "clean" ]; then
    echo "Cleaning build artifacts..."
    rm -rf out/*.diffs out/*.out
    rm -f *.o *.bc *.so
    echo "Clean complete."
    exit 0
fi

echo "Testing with PostgreSQL ${PG_VERSION}..."
docker run --rm -w /repo --volume "$PWD:/repo" pgxn/pgxn-tools \
    sh -c "pg-start ${PG_VERSION} && pg-build-test"

# Check for test failures
if [ -f out/regression.diffs ]; then
    echo ""
    echo "❌ Tests failed. Showing regression diffs:"
    cat out/regression.diffs
    exit 1
else
    echo ""
    echo "✅ All tests passed!"
fi