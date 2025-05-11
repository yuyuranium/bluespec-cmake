# bluespec-cmake

CMake modules for building Bluespec targets

## Features

### Building Bluespec package libraries

**Definition:** [`add_bsc_library`](./BluespecLibrary.cmake)

**Example:**
```cmake
# generates Package.bo
add_bsc_library("/path/to/Package.bsv")
```

### Building Bluesim executables

**Definition:** [`add_bluesim_executable`](./BluesimExecutable.cmake)

**Example:**
```cmake
# generates top_sim and top_sim.so
add_bluesim_executable(top_sim mkTop "/path/to/Top.bsv")
```

### Generating VCD waveform file by running Bluesim executable

**Definition:** [`generate_bluesim_waveform`](./BluesimWaveform.cmake)

**Example:**
```cmake
add_bluesim_executable(top_sim mkTop "/path/to/Top.bsv")
# generates top_sim.vcd
generate_bluesim_waveform(top_sim
  SIM_FLAGS
    -m 100 # run simulation for 100 cycles
)
```

### Generating Verilog from Bluespec sources

**Definition:** [`generate_verilog`](./BluespecVerilogGeneration.cmake)

**Example:**
```cmake
# generates mkTop.v
generate_verilog(mkTop "/path/to/Top.bsv")
```

### Building Bluesim SystemC library for Bluespec modules

**Definition:** [`add_bluesim_systemc_library`](./BluesimSystemC.cmake)

**Example:**
```cmake
# generates libmkTop_systemc.a
add_bluesim_systemc_library(mkTop_systemc mkTop "/path/to/Top.bsv")
add_executable(top_sim_sc sc_main.cpp)
target_link_libraries(top_sim_sc SystemC::systemc mkTop_systemc)
```

## Getting started

The bluespec-cmake module can be used in two ways:

### As a library

You can install bluespec-cmake on your system with CMake.

```bash
git clone https://github.com/yuyuranium/bluespec-cmake.git
cd bluespec-cmake
cmake -B build
sudo cmake --build build --target install
```

Nix users can use the flake provided in this repository. The flake provides `bluespec-cmake` as the
default package. To enter a default dev shell with `bluespec-cmake` installed, do:

```bash
nix develop "git+https://github.com/yuyuranium/bluespec-cmake.git"
```

Once bluespec-cmake is available on your system, you can import it by `find_package`.

```cmake
find_package(bluespec-cmake REQUIRED)
# Now you can use add_bluesim_executable() etc.
```

### As a submodule

You can also clone this repo as a git submodule and include this repository in `CMAKE_MODULE_PATH`.

```cmake
set(CMAKE_MODULE_PATH "/path/to/bluespec-cmake/" ${CMAKE_MODULE_PATH})
include(BluespecTargets)
# Now you can use add_bluesim_executable() etc.
```
