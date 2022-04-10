#!/bin/bash
set -e

tmpfile=$(mktemp /tmp/crystal-js-spec.XXXXXX)

./scripts/build.sh ./spec/all.cr -o $tmpfile.wasm --error-trace

time deno run --allow-read $tmpfile.js
# time node $tmpfile.js
