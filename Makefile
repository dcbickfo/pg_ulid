# PostgreSQL Extension Build System (PGXS)
# This is the official build system. Use this for building and installation.
# The Dockerfile and test.sh use this Makefile.
#
# Build: make
# Install: make install (requires superuser)
# Test: ./test.sh (uses Docker) or make installcheck
# Clean: make clean
# Dist: make dist (create PGXN distribution)

EXTENSION = ulid
MODULES = ulid

# Extract version from META.json
EXTVERSION = $(shell grep '"version"' META.json | head -1 | sed -E 's/.*"version": "(.*)".*/\1/')

DATA = ulid--$(EXTVERSION).sql
DOCS = README.md doc/ulid.md Changes

# Test configuration (PGXN standard structure)
TESTS = $(wildcard test/sql/*.sql)
REGRESS = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test --outputdir=out

# Source files (in src/ directory)
vpath %.c src
vpath %.h src

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Custom targets for build artifact management
.PHONY: clean-artifacts
clean-artifacts:
	rm -f out/*.diffs out/*.out
	rm -f *.o *.bc *.so

# Override clean to also clean our out directory
clean: clean-artifacts

# PGXN distribution target
.PHONY: dist
dist:
	@echo "Creating PGXN distribution..."
	git archive --format=zip --prefix=$(EXTENSION)-$(EXTVERSION)/ \
		-o $(EXTENSION)-$(EXTVERSION).zip HEAD
	@echo "Created $(EXTENSION)-$(EXTVERSION).zip"
	@echo "Run: pgxn load $(EXTENSION)-$(EXTVERSION).zip to test"

# Version info
.PHONY: version
version:
	@echo "Extension: $(EXTENSION)"
	@echo "Version: $(EXTVERSION)"
