# CMake configuration for IDE support only (CLion, VS Code, etc.)
# This is NOT the official build system for the extension.
# Use the Makefile with PGXS for building and installation.
# See README.md for build instructions.

cmake_minimum_required(VERSION 3.27)
project(pg_ulid C)

find_package(PostgreSQL REQUIRED)
set(CMAKE_C_STANDARD 11)

add_library(pg_ulid src/ulid.c)
target_include_directories(pg_ulid PRIVATE src)
target_link_libraries(pg_ulid PRIVATE PostgreSQL::PostgreSQL)