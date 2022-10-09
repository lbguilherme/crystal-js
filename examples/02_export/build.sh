export $(crystal env)
export CRYSTAL_PATH=$CRYSTAL_PATH:$(pwd)/../../src
../../scripts/build.sh main.cr -o crystal.wasm $*
../../scripts/build.sh main.cr -o crystal.wasm --esm $*
