cmake_minimum_required(VERSION 3.30)
include_guard(GLOBAL)

find_program(BSC_BIN NAMES bsc HINTS ENV BLUESPEC_HOME)
find_program(BLUETCL_BIN NAMES bluetcl HINTS ENV BLUESPEC_HOME)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(BSC_BIN "${BSC_BIN}" CACHE FILEPATH "BSC compiler" FORCE)
set(BLUETCL_BIN "${BLUETCL_BIN}" CACHE FILEPATH "Bluetcl dependency scanner" FORCE)
set(Python3_EXECUTABLE "${Python3_EXECUTABLE}" CACHE FILEPATH "Python interpreter used by BluespecCMake" FORCE)

if(NOT BSC_BIN OR NOT BLUETCL_BIN)
  message(FATAL_ERROR
    "BluespecCMake requires both bsc and bluetcl. "
    "Set BLUESPEC_HOME or add the BSC bin directory to PATH.")
endif()

get_filename_component(_bsc_realpath "${BSC_BIN}" REALPATH)
get_filename_component(_bsc_bin_dir "${_bsc_realpath}" DIRECTORY)
get_filename_component(BLUESPEC_DIR "${_bsc_bin_dir}/.." ABSOLUTE)
set(BLUESPEC_DIR "${BLUESPEC_DIR}" CACHE PATH "BSC installation root" FORCE)
set(BSC_LIBRARY_DIR "${BLUESPEC_DIR}/lib/Verilog" CACHE PATH
  "Bluespec Verilog primitive library" FORCE)
if(NOT IS_DIRECTORY "${BSC_LIBRARY_DIR}")
  message(FATAL_ERROR "Bluespec Verilog library not found: ${BSC_LIBRARY_DIR}")
endif()

find_library(_bskernel_library NAMES bskernel
  HINTS "${BLUESPEC_DIR}/lib/Bluesim" ENV BLUESPECDIR)
find_library(_bsprim_library NAMES bsprim
  HINTS "${BLUESPEC_DIR}/lib/Bluesim" ENV BLUESPECDIR)
if(NOT _bskernel_library OR NOT _bsprim_library)
  message(FATAL_ERROR
    "Bluespec runtime libraries bskernel and bsprim were not found under "
    "${BLUESPEC_DIR}/lib/Bluesim.")
endif()

if(NOT TARGET Bluespec::Compiler)
  add_executable(Bluespec::Compiler IMPORTED GLOBAL)
  set_target_properties(Bluespec::Compiler PROPERTIES IMPORTED_LOCATION "${BSC_BIN}")
endif()
if(NOT TARGET Bluespec::Bluetcl)
  add_executable(Bluespec::Bluetcl IMPORTED GLOBAL)
  set_target_properties(Bluespec::Bluetcl PROPERTIES IMPORTED_LOCATION "${BLUETCL_BIN}")
endif()
if(NOT TARGET Bluespec::bskernel AND _bskernel_library)
  add_library(Bluespec::bskernel UNKNOWN IMPORTED GLOBAL)
  set_target_properties(Bluespec::bskernel PROPERTIES
    IMPORTED_LOCATION "${_bskernel_library}"
    INTERFACE_INCLUDE_DIRECTORIES "${BLUESPEC_DIR}/lib/Bluesim")
endif()
if(NOT TARGET Bluespec::bsprim AND _bsprim_library)
  add_library(Bluespec::bsprim UNKNOWN IMPORTED GLOBAL)
  set_target_properties(Bluespec::bsprim PROPERTIES
    IMPORTED_LOCATION "${_bsprim_library}"
    INTERFACE_INCLUDE_DIRECTORIES "${BLUESPEC_DIR}/lib/Bluesim")
endif()

if(DEFINED ENV{BSC_OPTIONS} AND NOT "$ENV{BSC_OPTIONS}" STREQUAL "")
  message(FATAL_ERROR
    "BSC_OPTIONS is not supported by BluespecCMake. "
    "Use bsc_target_compile_options() or bsc_target_compile_definitions().")
endif()

if(EXISTS "${BLUESPEC_CMAKE_ROOT}/tools/bsc_cmake_driver.py")
  set(_bsc_driver "${BLUESPEC_CMAKE_ROOT}/tools/bsc_cmake_driver.py")
  set(_bsc_graph_tool "${BLUESPEC_CMAKE_ROOT}/tools/bsc_graph.py")
else()
  get_filename_component(_bsc_package_prefix "${BLUESPEC_CMAKE_ROOT}/../../.." ABSOLUTE)
  set(_bsc_driver "${_bsc_package_prefix}/libexec/bluespec-cmake/bsc_cmake_driver.py")
  set(_bsc_graph_tool
    "${_bsc_package_prefix}/libexec/bluespec-cmake/bsc_graph.py")
endif()
set(BLUESPEC_CMAKE_DRIVER "${_bsc_driver}" CACHE FILEPATH "BluespecCMake build driver" FORCE)
set(BLUESPEC_GRAPH_TOOL "${_bsc_graph_tool}" CACHE FILEPATH
  "BluespecCMake graph tool" FORCE)
