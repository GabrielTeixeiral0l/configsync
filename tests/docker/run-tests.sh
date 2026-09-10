#!/usr/bin/env bash
# MountSync - tests/docker/run-tests.sh
# Build and run the complete test suite inside isolated Docker container

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Building MountSync Test Docker Image ==="
docker build -t mountsync-test -f tests/docker/Dockerfile .

echo "=== Running Full BATS Test Suite in Container ==="
docker run --rm -v "$PROJECT_ROOT:/home/tester/mountsync" mountsync-test bash -c "tests/libs/bats-core/bin/bats tests/*.bats"

echo "=== Container Tests Passed Successfully! ==="
