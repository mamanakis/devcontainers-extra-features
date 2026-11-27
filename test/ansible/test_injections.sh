#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

check "hcloud package is injected" /usr/local/py-utils/venvs/ansible-core/bin/python -c "import hcloud"

reportResults