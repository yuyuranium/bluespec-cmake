cmake_minimum_required(VERSION 3.22)

include_guard(GLOBAL)

include(BluespecUtils)

# Function: generate_verilog
#   Generate Verilog source for a Bluespec module.
#
# Usage:
#   generate_verilog(<TOP_MODULE> <ROOT_SOURCE> [source_files...]
#                    [BSC_FLAGS <flags...>] [LINK_LIBS <libs...>])
#
# Arguments:
#   TOP_MODULE   - Top module to generate the Bluesim executable.
#   ROOT_SOURCE  - Source to the root compilation unit.
#   source_files - Additional source files/directories to include in search path.
#
# Options:
#   BSC_FLAGS - Multiple flags to be appended during compilation.
#   LINK_LIBS - List of targets to link against.
#
# Generates:
#   A target named Verilog.<TOP_MODULE>.
function(generate_verilog TOP_MODULE ROOT_SOURCE)
  set(_options)
  set(_one_args)
  set(_multi_args   BSC_FLAGS   LINK_LIBS)

  cmake_parse_arguments(ARG "${_options}" "${_one_args}" "${_multi_args}" ${ARGN})

  # 1. Handle absolute paths and extract directories
  get_filename_component(_abs_root_source "${ROOT_SOURCE}" ABSOLUTE)
  
  set(_all_sources "${_abs_root_source}")
  set(_src_dirs "")

  # Extract directories from the remaining sources
  foreach(_src ${ARG_UNPARSED_ARGUMENTS})
    get_filename_component(_abs_path "${_src}" ABSOLUTE)
    list(APPEND _all_sources "${_abs_path}")
    get_filename_component(_dir_path "${_abs_path}" DIRECTORY)
    list(APPEND _src_dirs "${_dir_path}")
  endforeach()

  list(REMOVE_DUPLICATES _all_sources)
  list(REMOVE_DUPLICATES _src_dirs)

  # 2. Set Target and output path (VDIR)
  set(_target "Verilog.${TOP_MODULE}")

  if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(_vdir "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/Verilog")
  elseif(CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
    set(_vdir "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/Verilog")
  else()
    set(_vdir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${_target}.dir")
  endif()
  
  file(MAKE_DIRECTORY "${_vdir}")

  # Define the path for the generated Verilog file
  set(_generated_vlog "${_vdir}/${TOP_MODULE}.v")
  add_custom_target(${_target} ALL DEPENDS "${_generated_vlog}")

  if(ARG_LINK_LIBS)
    add_dependencies(${_target} ${ARG_LINK_LIBS})
  endif()

  # 3. Set intermediate artifact path (BDIR)
  set(_bdir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${_target}.dir/${TOP_MODULE}.dir")
  file(MAKE_DIRECTORY "${_bdir}")

  # 4. Prepare BSC compilation flags
  set(_vlog_flags ${ARG_BSC_FLAGS})
  bsc_setup_path_flags(_vlog_flags
    BDIR      "${_bdir}"
    INFO_DIR  "${_bdir}"
    VDIR      "${_vdir}"
    SRC_DIRS  ${_src_dirs}
    LINK_LIBS ${ARG_LINK_LIBS}
  )

  bsc_setup_verilog_flags(_vlog_flags)
  set(_bsc_cmd ${BSC_BIN} ${_vlog_flags})

  # 5. Calculate Hash and execute Pre-elaboration (with caching mechanism)
  string(MD5 _hash "${_abs_root_source};${TOP_MODULE};${ARGN}")

  bsc_pre_elaboration(
    _blue_objects ${_hash} ${_all_sources}
    BSC_FLAGS ${_vlog_flags}
    LINK_LIBS ${ARG_LINK_LIBS}
  )

  # 6. Verilog Code Generation
  file(RELATIVE_PATH _vlog_path_rel "${CMAKE_BINARY_DIR}" "${_generated_vlog}")
  
  add_custom_command(
    OUTPUT  "${_generated_vlog}"
    COMMAND ${_bsc_cmd} "-g" ${TOP_MODULE} "${_abs_root_source}"
    COMMAND ${CMAKE_COMMAND} -E touch "${_generated_vlog}"
    DEPENDS ${_blue_objects}
    COMMENT "Generating Verilog source ${_vlog_path_rel}"
    VERBATIM
  )
endfunction()
