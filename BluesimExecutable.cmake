cmake_minimum_required(VERSION 3.22)

if(_BLUESIM_EXECUTABLE)
  return()
endif()
set(_BLUESIM_EXECUTABLE)

include(BluespecUtils)

# Function: add_bluesim_executable
#   Compile *.bsv files and module to a Bluesim executable.
#
# Arguments:
#   SIM_EXE     - The Bluesim executable name.
#   TOP_MODULE  - Top module to generate the Bluesim executable.
#   ROOT_SOURCE - Source to the root compilation unit.
#   BSC_FLAGS   - Multiple flags to be appended during compilation.
#   SRC_DIRS    - List of directories for *.bsv and *.bo.
#   LINK_LIBS   - List of targets to link against.
#
# Generates:
#   A target named Bluesim.<SIM_EXE>.
function(add_bluesim_executable SIM_EXE TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(BSIM ""
                             ""
                             "BSC_FLAGS;LINK_FLAGS;SRC_DIRS;LINK_LIBS"
                             ${ARGN})
  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Create Bluesim target
  set(TARGET "Bluesim.${SIM_EXE}")
  set(SIMDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir)

  # Determine output executable path and set it as the target's dependency
  if(CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(SIM_EXE_BIN ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE})
    set(SIM_EXE_SO ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE}.so)
    file(MAKE_DIRECTORY ${CMAKE_RUNTIME_OUTPUT_DIRECTORY})
  else()
    set(SIM_EXE_BIN ${CMAKE_BINARY_DIR}/${SIM_EXE})
    set(SIM_EXE_SO ${CMAKE_BINARY_DIR}/${SIM_EXE}.so)
  endif()
  add_custom_target(${TARGET} ALL DEPENDS ${SIM_EXE_BIN})

  # Add dependencies if specified
  if(BSIM_LINK_LIBS)
    add_dependencies(${TARGET} ${BSIM_LINK_LIBS})
  endif()

  # Make output paths for blue objects
  set(BDIR ${SIMDIR}/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  bsc_setup_path_flags(BSIM_BSC_FLAGS
    BDIR ${BDIR}
    INFO_DIR ${BDIR}
    SIMDIR ${SIMDIR}
    SRC_DIRS ${BSIM_SRC_DIRS}
    LINK_LIBS ${BSIM_LINK_LIBS}
  )

  # Flags for Bluesim and elaboration
  bsc_setup_sim_flags(BSIM_BSC_FLAGS)
  set(BSC_COMMAND ${BSC_BIN} ${BSIM_BSC_FLAGS})

  # 1. Partial compilation
  bsc_pre_elaboration(BLUE_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${BSIM_BSC_FLAGS})

  # 2. Bluesim code generation
  set(ELAB_MODULE ${BDIR}/${TOP_MODULE}.ba)
  string(REPLACE "${CMAKE_BINARY_DIR}/" "" ELAB_MODULE_PATH ${ELAB_MODULE})

  # Elaborate Bluesim top module
  add_custom_command(
    OUTPUT  ${ELAB_MODULE}
    COMMAND ${BSC_COMMAND} "-g" ${TOP_MODULE} ${BSIM_BSC_FLAGS} ${ROOT_SOURCE}
            && touch ${ELAB_MODULE}
    DEPENDS ${BLUE_OBJECTS}
    COMMENT "Elaborating Bluespec module ${ELAB_MODULE_PATH}"
    VERBATIM
  )

  bsc_get_bluesim_targets(BLUESIM_TARGETS ${TOP_MODULE})
  bsc_get_parallel_sim_link_jobs(JOBS)

  # 3. Link Bluesim executable
  add_custom_command(
    OUTPUT  ${BLUESIM_TARGETS} ${SIM_EXE_BIN} ${SIM_EXE_SO}
    COMMAND ${BSC_COMMAND} "-parallel-sim-link" ${JOBS} "-e" ${TOP_MODULE}
            "-o" ${SIM_EXE_BIN}
    DEPENDS ${ELAB_MODULE}
    COMMENT "Linking Bluesim executable ${SIM_EXE}"
    VERBATIM
  )
endfunction()
