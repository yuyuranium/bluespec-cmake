# Each regression test configures and builds a small standalone project with
# `ctest --build-and-test`, then runs the project's check.cmake script against
# the produced build tree.  The projects vendor the package through the same
# BluespecCMake.cmake entry point that add_subdirectory users include.

function(bsc_add_regression_test NAME PROJECT_DIR)
  cmake_parse_arguments(ARG "" "" "BUILD_OPTIONS" ${ARGN})
  set(_binary_dir "${CMAKE_CURRENT_BINARY_DIR}/${NAME}")
  set(_command
    "${CMAKE_CTEST_COMMAND}"
    --build-and-test
      "${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_DIR}"
      "${_binary_dir}"
    --build-generator "${CMAKE_GENERATOR}")
  if(ARG_BUILD_OPTIONS)
    list(APPEND _command --build-options ${ARG_BUILD_OPTIONS})
  endif()
  list(APPEND _command
    --test-command "${CMAKE_COMMAND}"
      -DBUILD_DIR=${_binary_dir}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_DIR}/check.cmake")
  add_test(NAME "${NAME}" COMMAND ${_command})
endfunction()

# Core component graph: the base -> {left,right} -> core diamond shared by a
# Bluesim endpoint, a Verilog endpoint, and a check endpoint.  Guards
# bsc_add_library ownership, PUBLIC compile-definition propagation, and
# per-backend artifact layout.
bsc_add_regression_test(shared-components shared-components)

# Bluesim waveform generation (contributed in PR #1): bsc_add_waveform must
# run the Bluesim endpoint with -V and the given SIM_FLAGS to produce a VCD.
bsc_add_regression_test(waveform waveform)

# Bluespec Classic sources (contributed in PR #2): a .bs package must be a
# first-class component source alongside .bsv.
bsc_add_regression_test(classic classic)

# Symbolically linked toolchain (contributed in PR #2): bsc and bluetcl locate
# their libraries relative to the invoked path, so the package must resolve
# symlinks before invoking either tool.
set(_symlink_dir "${CMAKE_CURRENT_BINARY_DIR}/symlinked-toolchain-bin")
file(MAKE_DIRECTORY "${_symlink_dir}")
file(CREATE_LINK "${BSC_BIN}" "${_symlink_dir}/bsc" SYMBOLIC)
file(CREATE_LINK "${BLUETCL_BIN}" "${_symlink_dir}/bluetcl" SYMBOLIC)
bsc_add_regression_test(symlinked-toolchain classic
  BUILD_OPTIONS
    "-DBSC_BIN=${_symlink_dir}/bsc"
    "-DBLUETCL_BIN=${_symlink_dir}/bluetcl")
