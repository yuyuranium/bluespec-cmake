# Shared component experiment

This project verifies that `bsc_add_library()` owns one reusable package set.
The `base -> {left,right} -> core` diamond is linked by both Bluesim and
Verilog endpoints. A successful combined build contains exactly one output
for each component package below `CMakeFiles/<component>.dir/bo/`.

```sh
cmake -S . -B build -G Ninja \
  -DBSC_CMAKE_PACKAGE_JOBS=1
cmake --build build --target sim rtl
```

Building `base` directly is also supported:

```sh
cmake --build build --target base
```
