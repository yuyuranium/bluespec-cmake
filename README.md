# BluespecCMake

BluespecCMake is an installable CMake package for BSC projects.  It keeps the
component graph and usage requirements in CMake, then discovers BSV imports at
build time with `bluetcl makedepend` and materializes explicit package edges in
the CMake-generated Ninja graph.

The driver and any package graph implementation are details: users build
ordinary CMake targets and do not invoke either tool directly.

> **Breaking change:** this is a redesign of the original `bluespec-cmake`
> modules.  The old per-file functions (`add_bsc_library(<source>)`,
> `add_bluesim_executable`, ...) are replaced by a target-based API modeled
> after modern CMake (`add_library`/`target_link_libraries`).  See
> [Migrating from the original API](#migrating-from-the-original-api).

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

Configure with the Ninja generator:

```sh
cmake -S . -B build -G Ninja
cmake --build build
```

## Getting started

### As an installed package

```sh
git clone https://github.com/yuyuranium/bluespec-cmake.git
cmake -S bluespec-cmake -B bluespec-cmake/build -G Ninja
cmake --install bluespec-cmake/build   # may need sudo for system prefixes
```

Then in your project:

```cmake
find_package(BluespecCMake CONFIG REQUIRED)
```

Nix users can use the flake provided in this repository; it provides
`bluespec-cmake` as the default package and a dev shell:

```sh
nix develop "git+https://github.com/yuyuranium/bluespec-cmake.git"
```

### Vendored

The package can also be vendored (for example as a git submodule) and included
directly; vendored use has the same entry point as installed use:

```cmake
include(/path/to/bluespec-cmake/BluespecCMake.cmake)
```

### Toolchain discovery

`bsc` and `bluetcl` are located on `PATH` or through the `BLUESPEC_HOME`
environment variable.  Symbolic links to the tools (package managers,
per-user profiles) are resolved to their real locations before any
invocation, so symlinked installations work out of the box.

## Public API

- `bsc_add_library(<target> SOURCES ...)` declares a reusable BSV component.
  It may contain multiple packages, and every package source is explicit.
  Sources may be BSV (`.bsv`) or Bluespec Classic/Haskell (`.bs`).
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

## Migrating from the original API

| Original | Replacement |
| --- | --- |
| `add_bsc_library(<source>)` | `bsc_add_library(<target> SOURCES <sources...>)` — libraries are named targets that own explicit source lists |
| `add_bluesim_executable(<exe> <top> <source> LINK_LIBS ...)` | `bsc_add_bluesim_executable(<target> TOP <top> SOURCE <source>)` + `bsc_target_link_libraries(<target> PRIVATE ...)` |
| `generate_verilog(<top> <source>)` | `bsc_add_verilog(<target> TOP <top> SOURCE <source>)` |
| `add_bluesim_systemc_library(<lib> <top> <source>)` | `bsc_add_systemc_library(<target> TOP <top> SOURCE <source>)` |
| `generate_bluesim_waveform(<exe> SIM_FLAGS ...)` | `bsc_add_waveform(<target> SIM_TARGET <sim> SIM_FLAGS ...)` |
| `BSC_FLAGS`, `LINK_FLAGS`, `C_FLAGS`, ... | `bsc_target_compile_definitions` / `bsc_target_compile_options` / `bsc_target_link_options` with `PRIVATE`/`PUBLIC`/`INTERFACE` scopes |
| `LINK_C_LIBS` / BDPI sources | `bsc_target_native_sources` and `bsc_target_link_native_libraries` |
| `find_package(bluespec-cmake)` | `find_package(BluespecCMake CONFIG)` |
| `CMAKE_MODULE_PATH` + `include(BluespecTargets)` | `include(.../BluespecCMake.cmake)` (vendored) |

Behavioral differences worth noting:

- Import discovery moves from configure time to build time; adding or
  removing an `import` does not require rerunning `cmake` by hand.
- Dependencies are declared per component, not per file, and usage
  requirements (definitions, options, native inputs) propagate through
  `PUBLIC`/`INTERFACE` scopes like ordinary CMake targets.
- Two endpoints linking the same component share its compiled `.bo`
  outputs instead of recompiling per endpoint.

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

## Testing

The repository carries a ctest-driven regression suite.  Each test configures
and builds a small standalone project against the working tree, then verifies
the produced artifacts (running the Bluesim executables, checking generated
Verilog and VCD output).  The suite covers the shared component graph, VCD
waveform generation, Bluespec Classic (`.bs`) sources, and symlinked
toolchains.

```sh
cmake -S . -B build -G Ninja
ctest --test-dir build --output-on-failure
```

Pass `-DBUILD_TESTING=OFF` to skip the suite.  Tests require `bsc`,
`bluetcl`, Ninja, and Python 3.

## Related work

- The BSC distribution's recommended flow is Make-based: `bsc -u` recompiles
  stale imports recursively inside one compiler invocation, or
  `bluetcl makedepend` emits Makefile fragments.  Both keep the package graph
  inside the compiler run rather than in the build system, so builds are
  serialized per endpoint and artifacts are not shared between testbenches.
- [BSVTools](https://github.com/esa-tu-darmstadt/BSVTools) scaffolds
  Make-based projects with Vivado/IP-XACT integration; library dependencies
  are added manually per project rather than as declared targets.
- [BlueLink](https://github.com/jeffreycassidy/BlueLink)'s
  `BluespecConfig.cmake` defines per-package CMake functions where callers
  list dependent packages by hand.
- [bazel_rules_hdl](https://github.com/hdl/bazel_rules_hdl) covers
  Verilog/Chisel/nMigen flows but has no Bluespec rules.

BluespecCMake differs by treating BSV components as first-class CMake targets
with transitive usage requirements, discovering imports at build time, and
sharing compiled package outputs across all endpoints in a build tree.

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
