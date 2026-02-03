cmake_minimum_required(VERSION 3.22)

include_guard(GLOBAL)

include(BluespecUtils)

# Function: add_bsc_library
#   Compile *.bsv files to *.bo binary representation.
#
# Usage:
#   add_bsc_library(<ROOT_SOURCE> [source_files...]
#                   [BSC_FLAGS <flags...>]
#                   [LINK_LIBS <libs...>])
#
# Arguments:
#   ROOT_SOURCE  - Source to the root compilation unit.
#   source_files - Additional source files/directories to include in search path.
#
# Options:
#   BSC_FLAGS - Multiple flags to be appended during compilation.
#   LINK_LIBS - List of targets to link against.
#
# Generates:
#   A target whose name is the package name of the source.
function(add_bsc_library ROOT_SOURCE)
  set(_options)
  set(_one_args)
  set(_multi_args   BSC_FLAGS  LINK_LIBS)

  cmake_parse_arguments(ARG "${_options}" "${_one_args}" "${_multi_args}" ${ARGN})

  # 1. Handle absolute paths and extract directories (replacing original SRC_DIRS)
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

  # 2. Get Package Name and set it as Target name
  bsc_package_name(_target "${_abs_root_source}")

  # 3. Determine compilation output directory (BDIR)
  if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(_bdir "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/Libraries")
  elseif(CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
    set(_bdir "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/Libraries")
  else()
    set(_bdir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${_target}.dir")
  endif()
  
  file(MAKE_DIRECTORY "${_bdir}")

  # 4. Define the path for the generated .bo file and the Target
  set(_generated_bo "${_bdir}/${_target}.bo")
  add_custom_target(${_target} ALL DEPENDS "${_generated_bo}")

  # 5. Handle dependencies
  if(ARG_LINK_LIBS)
    add_dependencies(${_target} ${ARG_LINK_LIBS})
  endif()

  # 6. Set Target properties
  set_target_properties(${_target}
    PROPERTIES
      LINK_DIRECTORIES "${_bdir}"
  )

  # 7. Prepare BSC compilation flags (using automatically extracted _src_dirs)
  set(_final_flags ${ARG_BSC_FLAGS})
  bsc_setup_path_flags(_final_flags
    BDIR      ${_bdir}
    INFO_DIR  ${_bdir}
    SRC_DIRS  ${_src_dirs}
    LINK_LIBS ${ARG_LINK_LIBS}
  )

  string(MD5 _hash "${ROOT_SOURCE};${ARGN}")

  # 8. Execute Pre-elaboration
  bsc_pre_elaboration(
    BLUESPEC_OBJECTS ${_hash} ${_all_sources}
    BSC_FLAGS ${_final_flags}
  )
endfunction()
