cmake_minimum_required(VERSION 3.22)

include_guard(GLOBAL)

include(FindBluespecToolchain)

# Variable: _BSC_BDIR
#   Internal list of BDIR's of all bluespec targets.
set(_BSC_BDIR CACHE INTERNAL "BSC_BDIR")

# Function: bsc_package_name
#   Compute the package name of given bsv source. See 2.1 Components of a BSV Design.
#   All BSV code is assumed to be inside a package. Furthermore BSC and other tools assume that
#   there is one package per file, and they use the package name to derive the file name.
#
# Usage:
#   bsc_package_name(<PKG_NAME_VAR> <SOURCE>)
#
# Arguments:
#   PKG_NAME_VAR - (Output) Variable to store the package name.
#   SOURCE       - Source file (*.bsv).
function(bsc_package_name PKG_NAME SOURCE)
  get_filename_component(_PKG_NAME ${SOURCE} NAME_WE)
  get_filename_component(_EXT ${SOURCE} EXT)
  # Make sure file extension is bsv.
  if(${_EXT} STREQUAL ".bsv" OR ${_EXT} STREQUAL ".bs")
    set(${PKG_NAME} ${_PKG_NAME} PARENT_SCOPE)
  endif()
endfunction()

# Function: bsc_setup_path_flags
#   Setup all search paths and modified the bsc flags. See 3.6 Setting the path.
#
# Usage:
#   bsc_setup_path_flags(<BSC_FLAGS_VAR>
#                        [BDIR <dir>] [SIMDIR <dir>] [VDIR <dir>] [INFO_DIR <dir>]
#                        [SRC_DIRS <dirs...>] [LINK_LIBS <targets...>])
#
# Arguments:
#   BSC_FLAGS_VAR - (Inout) Variable containing list of compilation flags.
#
# Options:
#   BDIR      - Output directory for .bo and .ba files (-bdir).
#   SIMDIR    - Output directory for Bluesim intermediate files (-simdir).
#   VDIR      - Output directory for .v files (-vdir).
#   INFO_DIR  - Output directory for informational files (-info-dir).
#   SRC_DIRS  - List of directories for *.bsv and *.bo (-p).
#   LINK_LIBS - List of targets to link against (-p).
function(bsc_setup_path_flags BSC_FLAGS)
  cmake_parse_arguments("" ""
                           "BDIR;SIMDIR;VDIR;INFO_DIR"
                           "SRC_DIRS;LINK_LIBS"
                           ${ARGN})
  set(_BSC_FLAGS ${${BSC_FLAGS}})

  if(_BDIR)
    list(APPEND _BSC_FLAGS "-bdir" ${_BDIR})
  endif()

  # Append to the internal BDIR list.
  set(_BSC_BDIR ${_BSC_BDIR} ${_BDIR} CACHE INTERNAL "BSC_BDIR")

  if(_SIMDIR)
    list(APPEND _BSC_FLAGS "-simdir" ${_SIMDIR})
  endif()

  if(_VDIR)
    list(APPEND _BSC_FLAGS "-vdir" ${_VDIR})
  endif()

  if(_INFO_DIR)
    list(APPEND _BSC_FLAGS "-info-dir" ${_INFO_DIR})
  endif()

  # Set bsc search path
  set(_BSC_PATH "%/Libraries" ${CMAKE_CURRENT_SOURCE_DIR})

  # Source directories (*.bsv)
  foreach(DIR ${_SRC_DIRS})
    get_filename_component(ABS_DIR ${DIR} ABSOLUTE)
    list(APPEND _BSC_PATH ${ABS_DIR})
  endforeach()

  # Library directories (*.bo)
  foreach(LIB ${_LINK_LIBS})
    get_target_property(LINK_DIR ${LIB} LINK_DIRECTORIES)
    get_filename_component(ABS_DIR ${LINK_DIR} ABSOLUTE)
    list(APPEND _BSC_PATH ${ABS_DIR})
  endforeach()

  list(REMOVE_DUPLICATES _BSC_PATH)
  list(REMOVE_ITEM _BSC_PATH ${_BDIR})  # Remove bdir, as it's added by default.
  list(JOIN _BSC_PATH ":" _BSC_PATH_STR)
  list(APPEND _BSC_FLAGS "-p" ${_BSC_PATH_STR})

  set(${BSC_FLAGS} ${_BSC_FLAGS} PARENT_SCOPE)
endfunction()

# Function: bsc_get_link_c_lib_files
#   Transform a list of targets to the TARGET_FILE generator expressions.
#
# Usage:
#   bsc_get_link_c_lib_files(<LINK_C_LIB_FILES_VAR> [LINK_C_LIBS <targets...>])
#
# Arguments:
#   LINK_C_LIB_FILES_VAR - (Output) Variable to store list of paths to all C libraries.
#
# Options:
#   LINK_C_LIBS          - List of C library targets.
function(bsc_get_link_c_lib_files LINK_C_LIB_FILES)
  cmake_parse_arguments("" ""
                           ""
                           "LINK_C_LIBS"
                           ${ARGN})
  set(_LINK_C_LIB_FILES)
  foreach(C_LIB ${_LINK_C_LIBS})
    list(APPEND _LINK_C_LIB_FILES $<TARGET_FILE:${C_LIB}>)
  endforeach()
  set(${LINK_C_LIB_FILES} ${_LINK_C_LIB_FILES} PARENT_SCOPE)
endfunction()

# Function: bsc_get_parallel_sim_link_jobs
#   Get the number of jobs for parallel sim link.
#
# Usage:
#   bsc_get_parallel_sim_link_jobs(<JOBS_VAR>)
#
# Arguments:
#   JOBS_VAR - (Output) Variable to store the number of jobs.
function(bsc_get_parallel_sim_link_jobs JOBS)
  cmake_host_system_information(RESULT _JOBS QUERY NUMBER_OF_LOGICAL_CORES)
  if(NOT _JOBS)
    set(_JOBS 4) # Use 4 if we cannot get number of processor count
  endif()
  set(${JOBS} ${_JOBS} PARENT_SCOPE)
endfunction()

# Function: bsc_setup_sim_flags
#   Setup bsc flags for Bluesim. See 3.1 Common compile and linking flags.
#
# Usage:
#   bsc_setup_sim_flags(<BSC_FLAGS_VAR>)
#
# Arguments:
#   BSC_FLAGS_VAR - (Inout) Variable containing list of compilation flags.
function(bsc_setup_sim_flags BSC_FLAGS)
  set(_BSC_FLAGS ${${BSC_FLAGS}})
  list(PREPEND _BSC_FLAGS "-sim" "-elab")
  set(${BSC_FLAGS} ${_BSC_FLAGS} PARENT_SCOPE)
endfunction()

# Function: bsc_setup_c_cxx_flags
#   Setup bsc C/C++ flags. See 3.14 C/C++ flags.
#
# Usage:
#   bsc_setup_c_cxx_flags(<C_CXX_FLAGS_VAR>
#                         [C_FLAGS <flags...>] [CXX_FLAGS <flags...>]
#                         [CPP_FLAGS <flags...>] [LD_FLAGS <flags...>])
#
# Arguments:
#   C_CXX_FLAGS_VAR - (Out) Variable to store the list of flags.
#
# Options:
#   C_FLAGS     - Arguments passed to the C compiler.
#   CXX_FLAGS   - Arguments passed to the C++ compiler.
#   CPP_FLAGS   - Arguments passed to the C preprocessor.
#   LD_FLAGS    - Arguments passed to the C/C++ linker.
function(bsc_setup_c_cxx_flags C_CXX_FLAGS)
  cmake_parse_arguments("" ""
                           ""
                           "C_FLAGS;CXX_FLAGS;CPP_FLAGS;LD_FLAGS"
                           ${ARGN})
  list(TRANSFORM _C_FLAGS PREPEND "-Xc;")
  list(TRANSFORM _CXX_FLAGS PREPEND "-Xc++;")
  list(TRANSFORM _CPP_FLAGS PREPEND "-Xcpp;")
  list(TRANSFORM _LD_FLAGS PREPEND "-Xl;")
  set(_C_CXX_FLAGS ${_C_FLAGS} ${_CXX_FLAGS} ${_CPP_FLAGS} ${_LD_FLAGS})
  set(${C_CXX_FLAGS} ${_C_CXX_FLAGS} PARENT_SCOPE)
endfunction()

# Function: bsc_setup_systemc_include_flags
#   Setup CXX bsc flags for including SystemC. See 3.6 Setting the path. To search for SystemC,
#   user can either set the environment variable `SYSTEMC` or set the CMake variable `SYSTMEC`. If
#   target SystemC::systemc exists, the include and link directories are added to the
#   CXX_SYSTEMC_FLAGS.
#
# Usage:
#   bsc_setup_systemc_include_flags(<CXX_SYSTEMC_FLAGS_VAR>)
#
# Arguments:
#   CXX_SYSTEMC_FLAGS_VAR - (Inout) Variable containing list of compilation flags.
function(bsc_setup_systemc_include_flags CXX_SYSTEMC_FLAGS)
  # See if SystemC::systemc is an existing target
  if(TARGET SystemC::systemc)
    set(_CXX_SYSTEMC_FLAGS
        "-Xc++"
        "-I$<TARGET_PROPERTY:SystemC::systemc,INTERFACE_INCLUDE_DIRECTORIES>")
    set(${CXX_SYSTEMC_FLAGS} ${_CXX_SYSTEMC_FLAGS} PARENT_SCOPE)
    return()
  endif()

  # Use BSC defined env variable
  find_path(SYSTEMC_INCLUDE NAMES systemc.h
    HINTS "${SYSTEMC}" ENV SYSTEMC
    PATH_SUFFIXES include)
  find_library(SYSTEMC_LIBDIR NAMES systemc
    HINTS "${SYSTEMC}" ENV SYSTEMC
    PATH_SUFFIXES lib)

  if(SYSTEMC_INCLUDE AND SYSTEMC_LIBDIR)
    set(_CXX_SYSTEMC_FLAGS "-Xc++" "-I${SYSTEMC_INCLUDE}")
    set(${CXX_SYSTEMC_FLAGS} ${_CXX_SYSTEMC_FLAGS} PARENT_SCOPE)
    return()
  endif()

  # If env variable is not set, use CMake module
  find_package(SystemCLanguage CONFIG REQUIRED)
  if(SystemCLanguage_FOUND)
    set(_CXX_SYSTEMC_FLAGS
        "-Xc++"
        "-I$<TARGET_PROPERTY:SystemC::systemc,INTERFACE_INCLUDE_DIRECTORIES>")
    set(${CXX_SYSTEMC_FLAGS} ${_CXX_SYSTEMC_FLAGS} PARENT_SCOPE)
    return()
  endif()

  message("SystemC not found. This can be fixed by doing either of the following steps:")
  message("- set SYSTEMC (environment) variable; or")
  message("- use the CMake module of your SystemC installation (may require CMAKE_PREFIX_PATH)")
  message(FATAL_ERROR "SystemC not found")
endfunction()

# Function: bsc_setup_verilog_flags
#   Setup bsc flags for verilog generation. See 3.1 Common compile and linking flags.
#
# Usage:
#   bsc_setup_verilog_flags(<BSC_FLAGS_VAR>)
#
# Arguments:
#   BSC_FLAGS_VAR - (Inout) Variable containing list of compilation flags.
function(bsc_setup_verilog_flags BSC_FLAGS)
  set(_BSC_FLAGS ${${BSC_FLAGS}})
  list(PREPEND _BSC_FLAGS "-verilog" "-elab")
  set(${BSC_FLAGS} ${_BSC_FLAGS} PARENT_SCOPE)
endfunction()

# Function: bsc_get_bluesim_targets
#   Determine all generated Bluesim targets.
#
# Usage:
#   bsc_get_bluesim_targets(<BLUESIM_TARGETS_VAR> <TOP_MODULE> [SIMDIR <dir>])
#
# Arguments:
#   BLUESIM_TARGETS_VAR - (Output) Variable to store list of paths to the Bluesim targets.
#   TOP_MODULE          - Top module to generate the Bluesim executable.
#
# Options:
#   SIMDIR              - Output directory for Bluesim intermediate files.
function(bsc_get_bluesim_targets BLUESIM_TARGETS TOP_MODULE)
  cmake_parse_arguments("" ""
                           "SIMDIR"
                           ""
                           ${ARGN})
  set(GENERATED_CXX_SOURCES "${TOP_MODULE}.cxx" "model_${TOP_MODULE}.cxx")
  set(GENERATED_CXX_HEADERS "${TOP_MODULE}.h"   "model_${TOP_MODULE}.h")
  set(GENERATED_CXX_OBJECTS "${TOP_MODULE}.o"   "model_${TOP_MODULE}.o")
  set(_BLUESIM_TARGETS ${GENERATED_CXX_SOURCES}
                       ${GENERATED_CXX_HEADERS}
                       ${GENERATED_CXX_OBJECTS})
  if(_SIMDIR)
    list(TRANSFORM _BLUESIM_TARGETS PREPEND "${_SIMDIR}/")
  endif()
  set(${BLUESIM_TARGETS} ${_BLUESIM_TARGETS} PARENT_SCOPE)
endfunction()

# Function: bsc_get_bluesim_sc_targets
#   Determine all generated Bluesim targets.
#
# Usage:
#   bsc_get_bluesim_sc_targets(<BLUESIM_SC_TARGETS_VAR> <TOP_MODULE> [SIMDIR <dir>])
#
# Arguments:
#   BLUESIM_SC_TARGETS_VAR - (Output) Variable to store list of paths to the Bluesim SystemC targets.
#   TOP_MODULE             - Top module to generate the Bluesim executable.
#
# Options:
#   SIMDIR                 - Output directory for Bluesim intermediate files.
function(bsc_get_bluesim_sc_targets BLUESIM_SC_TARGETS TOP_MODULE)
  cmake_parse_arguments("" ""
                           "SIMDIR"
                           ""
                           ${ARGN})
  set(GENERATED_SC_SOURCE "${TOP_MODULE}_systemc.cxx")
  set(GENERATED_SC_HEADER "${TOP_MODULE}_systemc.h")
  set(GENERATED_SC_OBJECT "${TOP_MODULE}_systemc.o")
  set(_BLUESIM_SC_TARGETS ${GENERATED_SC_SOURCE}
                          ${GENERATED_SC_HEADER}
                          ${GENERATED_SC_OBJECT})
  if(_SIMDIR)
    list(TRANSFORM _BLUESIM_SC_TARGETS PREPEND "${SIMDIR}/")
  endif()
  set(${BLUESIM_SC_TARGETS} ${_BLUESIM_SC_TARGETS})
endfunction()

# Function: bsc_pre_elaboration
#   Helper function to compile a root source file recursively to Bluespec
#   objects (*.bo).
#
# Usage:
#   bsc_pre_elaboration(<BLUESPEC_OBJECTS_VAR> <HASH> [source_files...]
#                       [BSC_FLAGS <flags...>])
#
# Arguments:
#   BLUESPEC_OBJECTS_VAR - (Output) Variable to store list of Bluespec object files (*.bo).
#   HASH                 - Unique hash for the compilation unit.
#   source_files         - Source files to process.
#
# Options:
#   BSC_FLAGS            - Multiple flags to be appended during compilation.
function(bsc_pre_elaboration BLUESPEC_OBJECTS HASH)
  set(_options)
  set(_one_args)
  set(_multi_args   BSC_FLAGS   LINK_LIBS)
  cmake_parse_arguments(ARG "${_options}" "${_one_args}" "${_multi_args}" ${ARGN})

  set(_sources ${ARG_UNPARSED_ARGUMENTS})
  if(NOT _sources)
    message(FATAL_ERROR "bsc_pre_elaboration: No source files provided.")
  endif()

  # Use the first source as the identifier for the cache key (or use the HASH itself)
  list(GET _sources 0 _first_src)
  set(_cache_list_var "BSC_DEP_LIST_${HASH}")

  # 1. Perform dependency check (only execute_process when Hash changes)
  if(NOT DEFINED ${_cache_list_var})
    message(STATUS "Checking dependencies for ${_first_src} (${HASH})")
    
    # Note: makedepend still needs to scan all _sources to get the complete dependency graph
    set(_dep_check ${BLUETCL_BIN} "-exec" "makedepend" ${ARG_BSC_FLAGS} ${_first_src})

    execute_process(
      COMMAND           ${_dep_check}
      RESULT_VARIABLE   _res
      ERROR_VARIABLE    _err
      OUTPUT_VARIABLE   _out
    )

    if(NOT _res EQUAL "0")
      message(STATUS "${_err}")
      message(FATAL_ERROR "Checking dependencies for ${_first_src} (${HASH}) - failed")
    endif()

    string(REPLACE "\n" ";" _dep_list "${_out}")
    set(${_cache_list_var} "${_dep_list}" CACHE INTERNAL "Cached DEP_LIST")
  endif()

  # 2. Build in-memory KV-store (for fast lookup)
  # We use _src as the Key, storing the corresponding _target and _deps
  set(_current_dep_list "${${_cache_list_var}}")
  set(_internal_kv_prefix "KV_${HASH}")

  foreach(_line ${_current_dep_list})
    string(FIND "${_line}" "#" _is_comment)
    if(_is_comment EQUAL "0" OR "${_line}" STREQUAL "")
      continue()
    endif()

    string(REPLACE ":" ";" _target_deps "${_line}")
    list(GET _target_deps 0 _target)
    list(GET _target_deps 1 _deps_raw)

    # Extract the first dependency item as the source code path (_src)
    string(REPLACE "\t" "" _deps_list "${_deps_raw}")
    separate_arguments(_deps_list)
    list(GET _deps_list 0 _src)

    # Store data into KV-store
    # Key: absolute path of _src
    get_filename_component(_abs_src "${_src}" ABSOLUTE)
    set("${_internal_kv_prefix}_TGT_${_abs_src}" "${_target}")
    set("${_internal_kv_prefix}_DEP_${_abs_src}" "${_deps_list}")
  endforeach()

  set(_link_lib_files "")
  foreach(_lib ${ARG_LINK_LIBS})
    if(TARGET ${_lib})
      get_target_property(_lib_bo_path ${_lib} BSC_OUTPUT_FILE)
      if(_lib_bo_path)
        list(APPEND _link_lib_files "${_lib_bo_path}")
      endif()
    endif()
  endforeach()

  # 3. Iterate through SOURCES provided by the developer and match with KV-store
  set(_local_objs "")
  set(_bsc_cmd ${BSC_BIN} ${ARG_BSC_FLAGS})

  foreach(_s ${_sources})
    get_filename_component(_abs_s "${_s}" ABSOLUTE)
    
    # Query KV-store
    set(_target "${${_internal_kv_prefix}_TGT_${_abs_s}}")
    set(_deps   "${${_internal_kv_prefix}_DEP_${_abs_s}}")

    if(_target)
      list(APPEND _local_objs "${_target}")
      string(REPLACE "${CMAKE_BINARY_DIR}/" "" _target_path "${_target}")

      add_custom_command(
        OUTPUT  "${_target}"
        COMMAND ${_bsc_cmd} "${_abs_s}"
        COMMENT "Building Bluespec object ${_target_path}"
        DEPENDS ${_deps} ${_link_lib_files}
        VERBATIM
      )
    else()
      message(WARNING "Source file ${_s} was specified but no dependency rule was found by makedepend.")
    endif()
  endforeach()

  # Return the list of generated objects
  set(${BLUESPEC_OBJECTS} "${_local_objs}" PARENT_SCOPE)
endfunction()

# Internal helper:
#   Creates a CMake -P script that unwraps translate_off/on blocks when
#   the block body matches MATCH_REGEX.
#
# Meaning:
#   INPUT         : input file
#   OUTPUT        : output file
#   MATCH_REGEX   : regex searched inside each translate_off block
#   REQUIRE_MATCH : if ON, fail when no matching block is found
function(_get_unwrap_translate_off_script OUT_SCRIPT)
  set(_script "${CMAKE_CURRENT_BINARY_DIR}/UnwrapTranslateOffBlocks.cmake")

  if(NOT EXISTS "${_script}")
    file(WRITE "${_script}" [=[
if(NOT DEFINED INPUT OR INPUT STREQUAL "")
  message(FATAL_ERROR "UnwrapTranslateOffBlocks: INPUT is required")
endif()

if(NOT EXISTS "${INPUT}")
  message(FATAL_ERROR "UnwrapTranslateOffBlocks: INPUT does not exist: ${INPUT}")
endif()

if(NOT DEFINED OUTPUT OR OUTPUT STREQUAL "")
  set(OUTPUT "${INPUT}")
endif()

if(NOT DEFINED MATCH_REGEX OR MATCH_REGEX STREQUAL "")
  message(FATAL_ERROR "UnwrapTranslateOffBlocks: MATCH_REGEX is required")
endif()

if(NOT DEFINED REQUIRE_MATCH)
  set(REQUIRE_MATCH OFF)
endif()

set(_translate_off_re "^[ \t]*//[ \t]*(synopsys|synthesis)[ \t]+translate_off")
set(_translate_on_re  "^[ \t]*//[ \t]*(synopsys|synthesis)[ \t]+translate_on")

file(READ "${INPUT}" _content)

# Protect semicolons before converting the text into a CMake list.
# This matters because Verilog/SystemVerilog lines usually contain semicolons.
string(REPLACE ";" "\\;" _content "${_content}")

# Normalize CRLF to LF.
string(REPLACE "\r\n" "\n" _content "${_content}")
string(REPLACE "\r" "\n" _content "${_content}")

# Split into lines.
string(REPLACE "\n" ";" _lines "${_content}")

set(_out "")
set(_in_translate_block FALSE)
set(_block_has_match FALSE)
set(_block_start_line "")
set(_block_body "")
set(_matched_blocks 0)

foreach(_line IN LISTS _lines)
  if(NOT _in_translate_block)
    if(_line MATCHES "${_translate_off_re}")
      set(_in_translate_block TRUE)
      set(_block_has_match FALSE)
      set(_block_start_line "${_line}")
      set(_block_body "")
    else()
      string(APPEND _out "${_line}\n")
    endif()
  else()
    if(_line MATCHES "${MATCH_REGEX}")
      set(_block_has_match TRUE)
    endif()

    if(_line MATCHES "${_translate_on_re}")
      if(_block_has_match)
        # Remove only translate_off/on wrapper.
        # Keep the block body.
        string(APPEND _out "${_block_body}")
        math(EXPR _matched_blocks "${_matched_blocks} + 1")
      else()
        # Preserve unrelated translate_off block.
        string(APPEND _out "${_block_start_line}\n")
        string(APPEND _out "${_block_body}")
        string(APPEND _out "${_line}\n")
      endif()

      set(_in_translate_block FALSE)
      set(_block_has_match FALSE)
      set(_block_start_line "")
      set(_block_body "")
    else()
      string(APPEND _block_body "${_line}\n")
    endif()
  endif()
endforeach()

# If a translate_off block is unterminated, preserve it conservatively.
if(_in_translate_block)
  string(APPEND _out "${_block_start_line}\n")
  string(APPEND _out "${_block_body}")
endif()

if(_matched_blocks EQUAL 0)
  if(REQUIRE_MATCH)
    message(FATAL_ERROR
      "UnwrapTranslateOffBlocks: no translate_off block matching "
      "'${MATCH_REGEX}' was found in ${INPUT}"
    )
  else()
    message(STATUS
      "UnwrapTranslateOffBlocks: no translate_off block matching "
      "'${MATCH_REGEX}' was found in ${INPUT}; copying input unchanged"
    )
  endif()
endif()

set(_tmp "${OUTPUT}.tmp")
file(WRITE "${_tmp}" "${_out}")

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${_tmp}" "${OUTPUT}"
  COMMAND_ERROR_IS_FATAL ANY
)

file(REMOVE "${_tmp}")

message(STATUS
  "UnwrapTranslateOffBlocks: unwrapped ${_matched_blocks} matching block(s): ${OUTPUT}"
)
]=])
  endif()

  set(${OUT_SCRIPT} "${_script}" PARENT_SCOPE)
endfunction()
