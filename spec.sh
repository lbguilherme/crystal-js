#!/bin/bash
set -e

tmpfile=$(mktemp /tmp/crystal-js-spec.XXXXXX)

./scripts/build.sh ./spec/all.cr -o $tmpfile.wasm --error-trace --esm

time deno run --allow-read $tmpfile.mjs
# time node $tmpfile.js
