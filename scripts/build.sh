#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
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

if [ ! -f "$SCRIPT_DIR"/wasm32-wasi-libs/libc.a ]
then
  mkdir -p "$SCRIPT_DIR"/wasm32-wasi-libs
  curl -L https://github.com/lbguilherme/wasm-libs/releases/download/0.0.2/wasm32-wasi-libs.tar.gz | tar -C "$SCRIPT_DIR"/wasm32-wasi-libs -xz
fi

export CRYSTAL_JS_WASM="$OUTPUT_FILE"
export CRYSTAL_JS_OUTPUT="${OUTPUT_FILE%.wasm}.js"
export CRYSTAL_LIBRARY_PATH="$SCRIPT_DIR"/wasm32-wasi-libs
LINK_ARGS="-lclang_rt.builtins-wasm32 --allow-undefined --no-entry --export __js_bridge_main --export __crystal_malloc_atomic --export __crystal_malloc --export __js_bridge_get_type_id"
LINK_ARGS="$LINK_ARGS --export-if-defined=__export_0 --export-if-defined=__export_1 --export-if-defined=__export_2 --export-if-defined=__export_3 --export-if-defined=__export_4 --export-if-defined=__export_5"

if [ -z "$RELEASE_MODE" ]
then
  crystal build "$INPUT_FILE" -o $OUTPUT_FILE $CRYSTAL_OPTS --target wasm32-wasi --link-flags "$LINK_ARGS"
else
  WORK_DIR=$(mktemp -d)
  function cleanup {
    rm -rf $WORK_DIR
  }
  trap cleanup EXIT
  LINK_ARGS="$LINK_ARGS --strip-all --compress-relocations"
  crystal build "$INPUT_FILE" -o "$WORK_DIR/linked.wasm" $CRYSTAL_OPTS --target wasm32-wasi --link-flags "$LINK_ARGS"
  wasm-opt "$WORK_DIR/linked.wasm" -o $OUTPUT_FILE -Oz --converge --all-features
  uglifyjs "$CRYSTAL_JS_OUTPUT" --compress --mangle -o "$WORK_DIR/opt.js"
  mv "$WORK_DIR/opt.js" "$CRYSTAL_JS_OUTPUT"
fi
