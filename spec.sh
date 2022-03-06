#!/bin/bash
set -e

rm -rf .tmp/*

mkdir -p .tmp/lib
ln -s "$PWD" .tmp/lib/web

cd .tmp

export CRYSTAL_WEB_EMIT_DENO=1
../scripts/build.sh ../spec/all.cr -o spec.wasm --error-trace
echo "runCrystalApp(new URL('./spec.wasm', import.meta.url))" >> spec.js

deno run --allow-read spec.js
