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

# Helper function to compile a root source file recursively
function(_bsc_compile_recursively BLUESPEC_OBJECTS ROOT_SOURCE)
  cmake_parse_arguments("" ""
                           ""
                           "BSC_FLAGS"
                           ${ARGN})
  # Setup Bluetcl options
  set(DEP_CHECK ${BLUETCL_BIN} "-exec" "makedepend" "-sim" "-elab" ${_BSC_FLAGS}
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
      COMMAND ${BSC_COMMAND} ${_BSC_FLAGS} ${SRC}
      DEPENDS ${DEPS})
  endforeach()

  # Return the bluespec objects
  set(${BLUESPEC_OBJECTS} ${_BLUESPEC_OBJECTS} PARENT_SCOPE)
  message(STATUS "Checking dependencies for ${ROOT_SOURCE} - done")
endfunction()

# Function to add Bluesim executable as a target
function(add_bluesim_executable SIM_EXE TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(BLUESIM ""
                                ""
                                "BSC_FLAGS;SRC_DIRS;DEFINES;LINK_FLAGS;BDPI_SOURCES"
                                ${ARGN})
  # Use absolute path
  if(NOT IS_ABSOLUTE ROOT_SOURCE)
    set(ROOT_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/${ROOT_SOURCE}")
  endif()

  # Set BSC search paths
  set(BSC_PATH "%/Libraries:${CMAKE_CURRENT_SOURCE_DIR}")
  foreach(DIR ${BLUESIM_SRC_DIRS})
    # Use absolute path
    if(IS_ABSOLUTE ${DIR})
      string(APPEND BSC_PATH ":${DIR}")
    else()
      string(APPEND BSC_PATH ":${CMAKE_CURRENT_SOURCE_DIR}/${DIR}")
    endif()
  endforeach()
  list(APPEND BLUESIM_BSC_FLAGS "-p" ${BSC_PATH})

  # Append all defined macros
  foreach(DEF ${BLUESIM_DEFINES})
    list(APPEND BLUESIM_BSC_FLAGS "-D" ${DEF})
  endforeach()

  # Redirect all generated intermediate files to the build directory
  list(APPEND BLUESIM_BSC_FLAGS
    "-bdir" "${CMAKE_CURRENT_BINARY_DIR}"
    "-simdir" "${CMAKE_CURRENT_BINARY_DIR}"
    "-info-dir" "${CMAKE_CURRENT_BINARY_DIR}")

  # Elaborated Bluesim module
  set(ELAB_MODULE "${TOP_MODULE}.ba")

  # Compiled files
  set(GENERATED_CXX_SOURCES "${TOP_MODULE}.cxx" "model_${TOP_MODULE}.cxx")
  set(GENERATED_CXX_HEADERS "${TOP_MODULE}.h" "model_${TOP_MODULE}.h")
  set(COMPILED_CXX_OBJECTS "${TOP_MODULE}.o" "model_${TOP_MODULE}.o")
  set(SIM_EXE_SO "${SIM_EXE}.so")

  # All bluesim targets
  set(BLUESIM_TARGETS ${GENERATED_CXX_SOURCES}
                      ${GENERATED_CXX_HEADERS}
                      ${COMPILED_CXX_OBJECTS}
                      ${CMAKE_BINARY_DIR}/${SIM_EXE}
                      ${CMAKE_BINARY_DIR}/${SIM_EXE_SO})

  set(BSC_COMMAND "${BSC_BIN}" "-q" "-elab" "-sim")

  # 1. Partial compilation
  _bsc_compile_recursively(BLUESPEC_OBJECTS ${ROOT_SOURCE}
    BSC_FLAGS ${BLUESIM_BSC_FLAGS})

  # 2. Bluesim code generation
  add_custom_command(
    OUTPUT  ${ELAB_MODULE}
    COMMAND ${BSC_COMMAND} "-g" ${TOP_MODULE} ${BLUESIM_BSC_FLAGS} ${ROOT_SOURCE}
    DEPENDS ${BLUESPEC_OBJECTS}
    VERBATIM)

  # 3. Link Bluesim executable
  add_custom_command(
    OUTPUT  ${BLUESIM_TARGETS}
    COMMAND ${BSC_COMMAND} "-parallel-sim-link" "8" "-e" ${TOP_MODULE}
    ${BLUESIM_BSC_FLAGS} "-o" ${CMAKE_BINARY_DIR}/${SIM_EXE} ${BLUESIM_LINK_FLAGS}
    ${BLUESIM_BDPI_SOURCES}
    DEPENDS ${ELAB_MODULE}
    COMMENT "Linking Bluesim executable ${SIM_EXE}"
    VERBATIM)

  add_custom_target(bluesim_${SIM_EXE} ALL
    DEPENDS ${BLUESIM_TARGETS})
endfunction()
