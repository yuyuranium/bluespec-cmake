cmake_minimum_required(VERSION 3.22)

include_guard(GLOBAL)

include(BluespecUtils)

# Function: add_bluesim_executable
#   Compile *.bsv files and module to a Bluesim executable.
#
# Usage:
#   add_bluesim_executable(<SIM_EXE> <TOP_MODULE> <ROOT_SOURCE> [source_files...]
#                          [BSC_FLAGS <flags...>]
#                          [LINK_LIBS <libs...>] [LINK_C_LIBS <libs...>]
#                          [C_FLAGS <flags...>] [CXX_FLAGS <flags...>]
#                          [CPP_FLAGS <flags...>] [LD_FLAGS <flags...>])
#
# Arguments:
#   SIM_EXE      - The Bluesim executable name.
#   TOP_MODULE   - Top module to generate the Bluesim executable.
#   ROOT_SOURCE  - Source to the root compilation unit.
#   source_files - Additional source files/directories to include in search path.
#
# Options:
#   BSC_FLAGS   - Multiple flags to be appended during compilation.
#   LINK_LIBS   - List of Bluespec library targets to link against.
#   LINK_C_LIBS - List of foreign C library targets to link against.
#   C_FLAGS     - Arguments passed to the C compiler.
#   CXX_FLAGS   - Arguments passed to the C++ compiler.
#   CPP_FLAGS   - Arguments passed to the C preprocessor.
#   LD_FLAGS    - Arguments passed to the C/C++ linker.
#
# Generates:
#   A target named Bluesim.<SIM_EXE>.
function(add_bluesim_executable SIM_EXE TOP_MODULE ROOT_SOURCE)
  set(_options)
  set(_one_args)
  set(_multi_args
    BSC_FLAGS    LINK_FLAGS    LINK_LIBS      LINK_C_LIBS
    C_FLAGS       CXX_FLAGS     CPP_FLAGS     LD_FLAGS
  )

  cmake_parse_arguments(ARG "${_options}" "${_one_args}" "${_multi_args}" ${ARGN})

  # 1. Handle absolute paths and extract directories
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

  # 2. Set Target and paths
  set(_target "Bluesim.${SIM_EXE}")
  set(_sim_dir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${_target}.dir")

  if(CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(_sim_exe_bin "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE}")
    set(_sim_exe_so  "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE}.so")
    file(MAKE_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}")
  else()
    set(_sim_exe_bin "${CMAKE_BINARY_DIR}/${SIM_EXE}")
    set(_sim_exe_so  "${CMAKE_BINARY_DIR}/${SIM_EXE}.so")
  endif()

  add_custom_target(${_target} ALL DEPENDS "${_sim_exe_bin}")

  if(ARG_LINK_LIBS)
    add_dependencies(${_target} ${ARG_LINK_LIBS})
  endif()

  set(_bdir "${_sim_dir}/${TOP_MODULE}.dir")
  file(MAKE_DIRECTORY "${_bdir}")

  # 3. Prepare BSC compilation flags
  set(_bsim_flags ${ARG_BSC_FLAGS})
  bsc_setup_path_flags(_bsim_flags
    BDIR      "${_bdir}"
    INFO_DIR  "${_bdir}"
    SIMDIR    "${_sim_dir}"
    SRC_DIRS  ${_src_dirs}
    LINK_LIBS ${ARG_LINK_LIBS}
  )

  bsc_setup_sim_flags(_bsim_flags)
  set(_bsc_cmd ${BSC_BIN} ${_bsim_flags})

  # 4. Calculate Hash and execute Pre-elaboration (with caching mechanism)
  string(MD5 _hash "${_abs_root_source};${TOP_MODULE};${ARGN}")
  
  bsc_pre_elaboration(
    _blue_objects ${_hash} ${_all_sources}
    BSC_FLAGS ${_bsim_flags}
    LINK_LIBS ${ARG_LINK_LIBS}
  )

  # 5. Bluesim Code Generation (Elaboration)
  set(_elab_module "${_bdir}/${TOP_MODULE}.ba")
  file(RELATIVE_PATH _elab_module_path "${CMAKE_BINARY_DIR}" "${_elab_module}")

  add_custom_command(
    OUTPUT  "${_elab_module}"
    COMMAND ${_bsc_cmd} "-g" ${TOP_MODULE} "${_abs_root_source}"
    COMMAND ${CMAKE_COMMAND} -E touch "${_elab_module}"
    DEPENDS ${_blue_objects}
    COMMENT "Elaborating Bluespec module ${_elab_module_path}"
    VERBATIM
  )

  # 6. Prepare linking arguments
  bsc_get_bluesim_targets(_bsim_targets ${TOP_MODULE} SIMDIR ${_sim_dir})
  bsc_get_parallel_sim_link_jobs(_jobs)
  bsc_get_link_c_lib_files(_link_c_lib_files LINK_C_LIBS ${ARG_LINK_C_LIBS})
  
  bsc_setup_c_cxx_flags(_c_cxx_flags
    C_FLAGS   ${ARG_C_FLAGS}
    CXX_FLAGS ${ARG_CXX_FLAGS}
    CPP_FLAGS ${ARG_CPP_FLAGS}
    LD_FLAGS  ${ARG_LD_FLAGS}
  )

  # 7. Link Bluesim Executable
  add_custom_command(
    OUTPUT  ${_bsim_targets} "${_sim_exe_bin}" "${_sim_exe_so}"
    COMMAND ${_bsc_cmd} ${_c_cxx_flags} "-parallel-sim-link" ${_jobs}
            "-e" ${TOP_MODULE} "-o" "${_sim_exe_bin}" ${_link_c_lib_files}
    DEPENDS "${_elab_module}" ${ARG_LINK_C_LIBS}
    COMMENT "Linking Bluesim executable ${SIM_EXE}"
    VERBATIM
  )
endfunction()
