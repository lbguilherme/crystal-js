#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CRYSTAL="$SCRIPT_DIR"/crystal/bin/crystal
CRYSTAL_OPTS=""

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --release)
      RELEASE_MODE=1
      CRYSTAL_OPTS="$CRYSTAL_OPTS --release"
      shift
    ;;
    --error-trace)
      CRYSTAL_OPTS="$CRYSTAL_OPTS --error-trace"
      shift
    ;;
    -o)
      OUTPUT_FILE=$2
      shift
      shift
    ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
    ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
    ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

INPUT_FILE=$1

if [ -z "$INPUT_FILE" ]
then
  echo "Usage: $0 [--release] [-o OUTPUT_FILE] INPUT_FILE"
  exit 1
fi

if [ -z "$OUTPUT_FILE" ]
then
  OUTPUT_FILE=$(basename "$INPUT_FILE" .cr).wasm
fi

if ! wasm-ld --version &>/dev/null
then
  echo "Please install wasm-ld"
  exit 1
fi

if [ -n "$RELEASE_MODE" ] && ! wasm-opt --version &>/dev/null
then
  echo "Please install wasm-opt"
  exit 1
fi

if [ -n "$RELEASE_MODE" ] && ! uglifyjs --version &>/dev/null
then
  echo "Please install uglifyjs"
  exit 1
fi

if ! "$CRYSTAL" --version &>/dev/null
then
  rm -rf "$SCRIPT_DIR"/crystal
  git clone -b feat/webassembly https://github.com/lbguilherme/crystal.git "$SCRIPT_DIR"/crystal
  make -C "$SCRIPT_DIR"/crystal
fi

if [ ! -f "$SCRIPT_DIR"/wasm32-wasi/libc.a ]
then
  curl -L https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-14/wasi-sysroot-14.0.tar.gz | tar -C "$SCRIPT_DIR" -xz wasi-sysroot/lib/wasm32-wasi --strip-components=2
fi

if [ ! -f "$SCRIPT_DIR"/wasm32-wasi/libclang_rt.builtins-wasm32.a ]
then
  curl -L https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-14/libclang_rt.builtins-wasm32-wasi-14.0.tar.gz | tar -C "$SCRIPT_DIR"/wasm32-wasi -xz lib/wasi --strip-components=2
fi

if [ ! -f "$SCRIPT_DIR"/wasm32-wasi/libpcre.a ]
then
  curl -L https://github.com/lbguilherme/crystal/files/7791111/libpcre-8.45.tar.gz | tar -C "$SCRIPT_DIR"/wasm32-wasi -xz libpcre.a
fi

WORK_DIR=$(mktemp -d)

function cleanup {
  rm -r $WORK_DIR
}

trap cleanup EXIT
export JAVASCRIPT_OUTPUT_FILE="${OUTPUT_FILE%.wasm}.js"
"$CRYSTAL" build "$INPUT_FILE" -o "$WORK_DIR/obj" $CRYSTAL_OPTS --cross-compile --target wasm32-unknown-wasi

if [ -z "$RELEASE_MODE" ]
then
  wasm-ld "$WORK_DIR/obj.wasm" -o $OUTPUT_FILE -L "$SCRIPT_DIR"/wasm32-wasi -lc -lclang_rt.builtins-wasm32 -lpcre --import-undefined --no-entry --export __original_main
else
  wasm-ld "$WORK_DIR/obj.wasm" -o "$WORK_DIR/linked.wasm" -L "$SCRIPT_DIR"/wasm32-wasi -lc -lclang_rt.builtins-wasm32 -lpcre --import-undefined --no-entry --export __original_main --strip-all --compress-relocations
  wasm-opt "$WORK_DIR/linked.wasm" -o $OUTPUT_FILE -Oz --converge
  uglifyjs "$JAVASCRIPT_OUTPUT_FILE" --compress --mangle -o "$WORK_DIR/opt.js"
  mv "$WORK_DIR/opt.js" "$JAVASCRIPT_OUTPUT_FILE"
fi
