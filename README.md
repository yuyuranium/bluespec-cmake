# BluespecCMake

BluespecCMake is an installable CMake package for BSC projects.  It keeps the
component graph and usage requirements in CMake, then discovers BSV imports at
build time with `bluetcl makedepend` and materializes explicit package edges in
the CMake-generated Ninja graph.

The driver and any package graph implementation are details: users build
ordinary CMake targets and do not invoke either tool directly.

## Quick start

```cmake
cmake_minimum_required(VERSION 3.30)
project(example LANGUAGES C CXX)

find_package(BluespecCMake CONFIG REQUIRED)

bsc_add_library(common
  SOURCES common/Types.bsv common/Common.bsv)

bsc_add_bluesim_executable(sim
  TOP mkTb
  SOURCE tb/Tb.bsv)
bsc_target_link_libraries(sim PRIVATE common)
```

The package can also be vendored with `add_subdirectory` or included through
the repository's `third-party/bluespec-cmake.cmake` wrapper.

## Public API

- `bsc_add_library(<target> SOURCES ...)` declares a reusable BSV component.
  It may contain multiple packages, and every package source is explicit.
- `bsc_target_sources(<target> SOURCES ...)` extends a component after
  creation.
- `bsc_target_link_libraries(<target> PRIVATE|PUBLIC|INTERFACE ...)` declares
  component and endpoint relationships.
- `bsc_target_compile_definitions`, `bsc_target_compile_options`, and
  `bsc_target_link_options` carry BSC usage requirements with normal CMake
  scope semantics.
- `bsc_target_native_sources` and `bsc_target_link_native_libraries` attach
  BDPI/native inputs to an endpoint or component.
- `bsc_add_check` validates packages without a backend artifact.
- `bsc_add_bluesim_executable` creates a Bluesim executable and shared model.
- `bsc_add_verilog` creates generated Verilog and a file list.
- `bsc_add_systemc_library` creates a static SystemC model archive that can
  be linked by an ordinary CMake target.
- `bsc_add_waveform` runs a Bluesim endpoint and produces a VCD file.

`SOURCES` are explicit providers owned by the component, like sources passed
to ordinary `add_library()`.  Adding, removing, or renaming a package
requires the corresponding CMake source-list change.  A package name may have
only one provider in an endpoint closure; conflicts are errors rather than
silent `-p` shadowing.

## CMake/Ninja package graph

CMake owns one ordinary custom-command edge for every explicit `.bsv -> .bo`
package.  The build-time scanner invokes
`bluetcl makedepend` and writes a deterministic topology file.  When an
import is added or removed, the same Ninja invocation regenerates CMake and
reloads the updated package edges.  Implementation-only edits rebuild the
affected package without a configure step.

Package outputs are owned by the component target and live below its normal
`CMakeFiles/<component>.dir/bo/` work directory.  Building the component target
materializes that package set.  Every linked endpoint reuses the same `.bo`
outputs and keeps only top/backend-specific `.ba`, generated native code, RTL,
and public artifacts below `CMakeFiles/<endpoint>.dir/`.  The endpoint driver
does not compile component packages or start another build system.

For example, two endpoints linked to `common` share:

```text
CMakeFiles/common.dir/bo/Types.bo
CMakeFiles/common.dir/bo/Common.bo
```

They do not create endpoint-local copies.  Component compilation uses only
the component's own PRIVATE/PUBLIC requirements and the public interfaces of
its dependencies; endpoint-private flags never propagate backwards into a
component.

Because BSC package compilation can use substantial memory, its outer Ninja
edges use a dedicated job pool that defaults to one job. Increase it only when
the host has enough memory:

```sh
cmake -S . -B build -G Ninja \
  -DBSC_CMAKE_PACKAGE_JOBS=2
```

Endpoint edges are ordinary outer Ninja jobs and therefore share Ninja's
global parallelism with the rest of the CMake build.

Within each endpoint, backend linking defaults to one BSC link job when
`BSC_BUILD_JOBS` is unset. Set `BSC_BUILD_JOBS` explicitly only when the host
can safely support more concurrent C/C++ compilation.

## Phase 1 constraints

- CMake 3.30 or newer is required.
- Ninja is the supported generator and the package currently requires a
  single-config build tree.
- The Phase 1 driver targets POSIX hosts (Linux/macOS); it uses file locks for
  concurrent endpoint invocations.
- BSC, `bluetcl`, Ninja, and Python 3 must be available on `PATH` (or through
  `BLUESPEC_HOME`).
- Generated files stay under the build tree.  `cmake --build <dir> --target
  clean` removes the Bluespec workspace and endpoint artifacts.
- Generic component `.bo` outputs are shared by all compatible endpoints in
  the current build tree.  Install/export of precompiled BSV components and
  reuse across independent build trees are planned for Phase 2.

The tools use only Python's standard library. BSC remains responsible for BSV
compilation, elaboration, backend generation, and native linking. The graph
tool performs package scanning/compilation, while the endpoint driver handles
only endpoint artifact generation.
