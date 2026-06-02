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
  set(_options      REQUIRE_TRANSLATE_OFF_MATCH)
  set(_one_args     TRANSLATE_OFF_MATCH_REGEX)
  set(_multi_args   BSC_FLAGS   LINK_LIBS)

  cmake_parse_arguments(ARG "${_options}" "${_one_args}" "${_multi_args}" ${ARGN})

  # If TRANSLATE_OFF_MATCH_REGEX is specified, enable the unwrap process.
  set(_unwrap_translate_off_blocks FALSE)
  if(ARG_TRANSLATE_OFF_MATCH_REGEX)
    set(_unwrap_translate_off_blocks TRUE)
  endif()

  if(ARG_REQUIRE_TRANSLATE_OFF_MATCH AND NOT _unwrap_translate_off_blocks)
    message(FATAL_ERROR
      "generate_verilog: REQUIRE_TRANSLATE_OFF_MATCH requires "
      "TRANSLATE_OFF_MATCH_REGEX"
    )
  endif()

  # 1. Handle absolute paths and extract source directories.
  get_filename_component(_abs_root_source "${ROOT_SOURCE}" ABSOLUTE)

  set(_all_sources "${_abs_root_source}")
  set(_src_dirs "")

  foreach(_src ${ARG_UNPARSED_ARGUMENTS})
    get_filename_component(_abs_path "${_src}" ABSOLUTE)
    list(APPEND _all_sources "${_abs_path}")

    get_filename_component(_dir_path "${_abs_path}" DIRECTORY)
    list(APPEND _src_dirs "${_dir_path}")
  endforeach()

  list(REMOVE_DUPLICATES _all_sources)
  list(REMOVE_DUPLICATES _src_dirs)

  # 2. Set target and final Verilog output path.
  set(_target "Verilog.${TOP_MODULE}")

  if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(_vdir "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/Verilog")
  elseif(CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
    set(_vdir "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/Verilog")
  else()
    set(_vdir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${_target}.dir")
  endif()

  file(MAKE_DIRECTORY "${_vdir}")

  # Final public Verilog artifact used by downstream tools.
  set(_generated_vlog "${_vdir}/${TOP_MODULE}.v")

  # If TRANSLATE_OFF_MATCH_REGEX is given, generate raw BSC output into a
  # private directory first, then unwrap matching translate_off blocks into
  # the final public artifact.
  if(_unwrap_translate_off_blocks)
    set(_raw_vdir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${_target}.dir/raw_verilog")
    set(_bsc_vdir "${_raw_vdir}")
    set(_raw_generated_vlog "${_raw_vdir}/${TOP_MODULE}.v")
    file(MAKE_DIRECTORY "${_raw_vdir}")
  else()
    set(_bsc_vdir "${_vdir}")
    set(_raw_generated_vlog "${_generated_vlog}")
  endif()

  # 3. Create build target.
  add_custom_target(${_target} ALL DEPENDS "${_generated_vlog}")

  if(ARG_LINK_LIBS)
    add_dependencies(${_target} ${ARG_LINK_LIBS})
  endif()

  # 4. Set intermediate BSC artifact path.
  set(_bdir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${_target}.dir/${TOP_MODULE}.dir")
  file(MAKE_DIRECTORY "${_bdir}")

  # 5. Prepare BSC flags.
  set(_vlog_flags ${ARG_BSC_FLAGS})

  bsc_setup_path_flags(_vlog_flags
    BDIR      "${_bdir}"
    INFO_DIR  "${_bdir}"
    VDIR      "${_bsc_vdir}"
    SRC_DIRS  ${_src_dirs}
    LINK_LIBS ${ARG_LINK_LIBS}
  )

  bsc_setup_verilog_flags(_vlog_flags)

  set(_bsc_cmd ${BSC_BIN} ${_vlog_flags})

  # 6. Pre-elaboration with caching.
  string(MD5 _hash "${_abs_root_source};${TOP_MODULE};${ARGN}")

  bsc_pre_elaboration(
    _blue_objects ${_hash} ${_all_sources}
    BSC_FLAGS ${_vlog_flags}
    LINK_LIBS ${ARG_LINK_LIBS}
  )

  file(RELATIVE_PATH _vlog_path_rel "${CMAKE_BINARY_DIR}" "${_generated_vlog}")

  # 7. Generate raw Verilog using BSC.
  add_custom_command(
    OUTPUT "${_raw_generated_vlog}"
    COMMAND ${_bsc_cmd} "-g" ${TOP_MODULE} "${_abs_root_source}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${_raw_generated_vlog}"
    DEPENDS ${_blue_objects}
    COMMENT "Generating Verilog source ${_raw_generated_vlog}"
    VERBATIM
  )

  # 8. Optionally unwrap selected translate_off blocks into the final output.
  if(_unwrap_translate_off_blocks)
    _get_unwrap_translate_off_script(_unwrap_translate_script)

    set(_require_match OFF)
    if(ARG_REQUIRE_TRANSLATE_OFF_MATCH)
      set(_require_match ON)
    endif()

    add_custom_command(
      OUTPUT "${_generated_vlog}"
      COMMAND "${CMAKE_COMMAND}"
        "-DINPUT=${_raw_generated_vlog}"
        "-DOUTPUT=${_generated_vlog}"
        "-DMATCH_REGEX=${ARG_TRANSLATE_OFF_MATCH_REGEX}"
        "-DREQUIRE_MATCH=${_require_match}"
        -P "${_unwrap_translate_script}"
      DEPENDS
        "${_raw_generated_vlog}"
        "${_unwrap_translate_script}"
      COMMENT "Unwrapping selected translate_off blocks in ${_vlog_path_rel}"
      VERBATIM
    )
  endif()
endfunction()
