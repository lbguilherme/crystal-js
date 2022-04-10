#!/bin/bash
set -e

rm -rf .tmp/*

mkdir -p .tmp/lib
ln -s "$PWD" .tmp/lib/web

cd .tmp

../scripts/build.sh ../spec/all.cr -o spec.wasm --error-trace

time deno run --allow-read spec.js
# time node spec.js
