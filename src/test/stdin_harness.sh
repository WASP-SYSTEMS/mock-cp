#!/bin/bash
# This script runs the vulnerable program with the provided blob as STDIN

set -e
set -o pipefail

BLOB_FILE=$1

${SRC}/samples/mock_vp < "$BLOB_FILE" || true
