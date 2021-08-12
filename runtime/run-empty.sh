pushd /sledge/runtime
make clean all
pushd /sledge/runtime/bin
LD_LIBRARY_PATH="$(pwd):$LD_LIBRARY_PATH" ./sledgert ../experiments/concurrency/spec.json