cmake_minimum_required(VERSION 3.22)

if(__add_bluespec)
  return()
endif()
set(__add_bluespec ON)

# We need Bluespec compiler and Bluetcl
find_program(BSC_BIN
  NAMES bsc
  DOC "Bluespec compiler")

find_program(BLUETCL_BIN
  NAMES bluetcl
  DOC "Bluetcl")

if(NOT BSC_BIN)
  message(FATAL_ERROR "Bluespec compiler binary not found!")
endif()

if(NOT BLUETCL_BIN)
  message(FATAL_ERROR "Bluetcl binary not found!")
endif()

# Get number of pyhsical cores
cmake_host_system_information(RESULT NPROC
                              QUERY NUMBER_OF_PHYSICAL_CORES)

# Helper function to compile a root source file recursively
function(_bsc_compile_recursively BLUESPEC_OBJECTS ROOT_SOURCE)
  cmake_parse_arguments("" ""
                           ""
                           "BSC_FLAGS"
                           ${ARGN})

  # Setup BSC command
  set(BSC_COMMAND ${BSC_BIN} ${_BSC_FLAGS})

  # Setup Bluetcl options
  set(DEP_CHECK ${BLUETCL_BIN} "-exec" "makedepend" ${_BSC_FLAGS}
                ${ROOT_SOURCE})

  # Bluespec objects
  set(_BLUESPEC_OBJECTS "")

  message(STATUS "Checking dependencies for ${ROOT_SOURCE}")
  execute_process(
    COMMAND         ${DEP_CHECK}
    RESULT_VARIABLE DEP_CHECK_RESULT
    OUTPUT_VARIABLE DEP_CHECK_OUTPUT)

  if(NOT ${DEP_CHECK_RESULT} EQUAL "0")
    message(FATAL_ERROR "Checking dependencies for ${ROOT_SOURCE} - failed")
  endif()

  # Split the output string to list
  string(REPLACE "\n" ";" DEP_LIST ${DEP_CHECK_OUTPUT})
  foreach(LINE ${DEP_LIST})
    # Line starts with a '#' is a comment, skip it
    string(FIND ${LINE} "#" IS_NOT_DEP)
    if(${IS_NOT_DEP} EQUAL "0")
      continue()
    endif()

    # Split make-style dependency expression into target and its dependencies
    string(REPLACE ":" ";" TARGET_DEPS ${LINE})
    list(GET TARGET_DEPS 0 TARGET) # before the colon is the target
    list(GET TARGET_DEPS 1 DEPS)   # after the colon is its dependencies

    list(APPEND _BLUESPEC_OBJECTS ${TARGET}) # add bluespec object target

    string(REPLACE "\t" "" DEPS ${DEPS}) # remove tabs
    separate_arguments(DEPS)             # convert to list

    list(GET DEPS 0 SRC) # first dependency is the source file

    # Command to build the target
    add_custom_command(
      OUTPUT  ${TARGET}
      COMMAND ${BSC_COMMAND} ${SRC}
      DEPENDS ${DEPS})
  endforeach()

  # Return the bluespec objects
  set(${BLUESPEC_OBJECTS} ${_BLUESPEC_OBJECTS} PARENT_SCOPE)
  message(STATUS "Checking dependencies for ${ROOT_SOURCE} - done")
endfunction()

function(add_bsim_executable SIM_EXE TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(BSIM ""
                             ""
                             "BSC_FLAGS;LINK_FLAGS;SRC_DIRS"
                             ${ARGN})
  # Create Bluesim target
  set(TARGET "Bluesim.${SIM_EXE}")
  set(SIM_EXE_BIN ${CMAKE_BINARY_DIR}/${SIM_EXE})
  set(SIM_EXE_SO ${CMAKE_BINARY_DIR}/${SIM_EXE}.so)

  add_custom_target(${TARGET} ALL DEPENDS ${SIM_EXE_BIN})

  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Set bsc search path
  set(_BSC_PATH "%/Libraries:${CMAKE_CURRENT_SOURCE_DIR}")
  foreach(DIR ${BSIM_SRC_DIRS})
    get_filename_component(ABS_DIR ${DIR} ABSOLUTE)
    string(APPEND _BSC_PATH ":${ABS_DIR}")
  endforeach()
  list(APPEND BSIM_BSC_FLAGS "-p" ${_BSC_PATH})

  get_target_property(BINARY_DIR ${TARGET} BINARY_DIR)
  set(SIMDIR ${BINARY_DIR}/CMakeFiles/${TARGET}.dir)
  set(BDIR ${SIMDIR}/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  list(APPEND BSIM_BSC_FLAGS "-bdir" ${BDIR})
  list(APPEND BSIM_BSC_FLAGS "-info-dir" ${BDIR})
  list(APPEND BSIM_BSC_FLAGS "-simdir" ${SIMDIR})

  # Flags for Bluesim and elaboration
  list(PREPEND BSIM_BSC_FLAGS "-sim" "-elab")

  set(BSC_COMMAND ${BSC_BIN} ${BSIM_BSC_FLAGS})

  _bsc_compile_recursively(BLUE_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${BSIM_BSC_FLAGS})

  # 2. Bluesim code generation
  set(ELAB_MODULE ${BDIR}/${TOP_MODULE}.ba)

  # Elaborate Bluesim top module
  add_custom_command(
    OUTPUT  ${ELAB_MODULE}
    COMMAND ${BSC_COMMAND} "-g" ${TOP_MODULE} ${BSIM_BSC_FLAGS} ${ROOT_SOURCE}
            && touch ${ELAB_MODULE}
    DEPENDS ${BLUE_OBJECTS}
    VERBATIM)

  # Compiled files
  set(GENERATED_CXX_SOURCES "${TOP_MODULE}.cxx" "model_${TOP_MODULE}.cxx")
  set(GENERATED_CXX_HEADERS "${TOP_MODULE}.h" "model_${TOP_MODULE}.h")
  set(COMPILED_CXX_OBJECTS "${TOP_MODULE}.o" "model_${TOP_MODULE}.o")

  # All bluesim targets
  list(TRANSFORM GENERATED_CXX_SOURCES PREPEND ${SIMDIR}/)
  list(TRANSFORM GENERATED_CXX_HEADERS PREPEND ${SIMDIR}/)
  list(TRANSFORM COMPILED_CXX_OBJECTS PREPEND ${SIMDIR}/)
  set(BLUESIM_TARGETS ${GENERATED_CXX_SOURCES}
                      ${GENERATED_CXX_HEADERS}
                      ${COMPILED_CXX_OBJECTS}
                      ${SIM_EXE_BIN}
                      ${SIM_EXE_SO})

  # 3. Link Bluesim executable
  add_custom_command(
    OUTPUT  ${BLUESIM_TARGETS}
    COMMAND ${BSC_COMMAND} "-quiet" "-parallel-sim-link" ${NPROC} "-e" ${TOP_MODULE}
            "-o" ${SIM_EXE_BIN} ${BSIM_LINK_FLAGS}
    DEPENDS ${ELAB_MODULE}
    COMMENT "Linking Bluesim executable ${SIM_EXE}"
    VERBATIM)

endfunction()

function(emit_verilog TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(VLOG ""
                             ""
                             "BSC_FLAGS;SRC_DIRS"
                             ${ARGN})
  # Create Verilog target
  set(TARGET "Verilog.${TOP_MODULE}")
  set(VDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir)
  set(GENERATED_VLOG_SOURCE ${VDIR}/${TOP_MODULE}.v)

  add_custom_target(${TARGET} ALL DEPENDS ${GENERATED_VLOG_SOURCE})

  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Set bsc search path
  set(_BSC_PATH "%/Libraries:${CMAKE_CURRENT_SOURCE_DIR}")
  foreach(DIR ${VLOG_SRC_DIRS})
    get_filename_component(ABS_DIR ${DIR} ABSOLUTE)
    string(APPEND _BSC_PATH ":${ABS_DIR}")
  endforeach()
  list(APPEND VLOG_BSC_FLAGS "-p" ${_BSC_PATH})

  set(BDIR ${VDIR}/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  list(APPEND VLOG_BSC_FLAGS "-bdir" ${BDIR})
  list(APPEND VLOG_BSC_FLAGS "-info-dir" ${BDIR})
  list(APPEND VLOG_BSC_FLAGS "-vdir" ${VDIR})

  # Flags for Bluesim and elaboration
  list(PREPEND VLOG_BSC_FLAGS "-verilog" "-elab")

  set(BSC_COMMAND ${BSC_BIN} ${VLOG_BSC_FLAGS})

  # 1. Partial compilation
  _bsc_compile_recursively(BLUE_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${VLOG_BSC_FLAGS})

  # 2. Verilog code generation
  add_custom_command(
    OUTPUT  ${GENERATED_VLOG_SOURCE}
    COMMAND ${BSC_COMMAND} "-g" ${TOP_MODULE} ${VLOG_BSC_FLAGS} ${ROOT_SOURCE}
            && touch ${GENERATED_VLOG_SOURCE}
    DEPENDS ${BLUE_OBJECTS}
    COMMENT "Generating Verilog source ${TOP_MODULE}.v"
    VERBATIM)

endfunction()
