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

macro(_bsc_flags_set_search_paths BSC_FLAGS)
  cmake_parse_arguments("" ""
                           ""
                           "SRC_DIRS"
                           ${ARGN})
  set(_BSC_PATH "%/Libraries:${CMAKE_CURRENT_SOURCE_DIR}")
  foreach(DIR ${_SRC_DIRS})
    # Use absolute path
    get_filename_component(ABS_DIR ${DIR} ABSOLUTE)
    string(APPEND _BSC_PATH ":${ABS_DIR}")
  endforeach()
  list(APPEND ${BSC_FLAGS} "-p" ${_BSC_PATH})
endmacro()

macro(_bsc_flags_append_macro_definitions BSC_FLAGS)
  cmake_parse_arguments("" ""
                           ""
                           "DEFINES"
                           ${ARGN})
  foreach(DEF ${_DEFINES})
    list(APPEND ${BSC_FLAGS} "-D" ${DEF})
  endforeach()
endmacro()

macro(_bsc_flags_redirect_output_dir BSC_FLAGS)
  cmake_parse_arguments("" ""
                           ""
                           "OUTPUT_DIRS"
                           ${ARGN})
  foreach(DIR ${_OUTPUT_DIRS})
    list(APPEND ${BSC_FLAGS}
         ${DIR} ${CMAKE_CURRENT_BINARY_DIR})
  endforeach()
endmacro()

function(_set_bluesim_link_flags BLUESIM_LINK_FLAGS)
  cmake_parse_arguments("" ""
                           ""
                           "C_FLAGS;CXX_FLAGS;LD_FLAGS"
                           ${ARGN})
  set(_BLUESIM_LINK_FLAGS "")

  foreach(FLAG ${_C_FLAGS})
    list(APPEND _BLUESIM_LINK_FLAGS "-Xc" ${FLAG})
  endforeach()

  foreach(FLAG ${_CXX_FLAGS})
    list(APPEND _BLUESIM_LINK_FLAGS "-Xc++" ${FLAG})
  endforeach()

  foreach(FLAG ${_LD_FLAGS})
    list(APPEND _BLUESIM_LINK_FLAGS "-Xl" ${FLAG})
  endforeach()

  set(${BLUESIM_LINK_FLAGS} ${_BLUESIM_LINK_FLAGS} PARENT_SCOPE)
endfunction()

# Function to add Bluesim executable as a target
function(add_bluesim_executable SIM_EXE TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(BLUESIM ""
                                ""
                                "BSC_FLAGS;SRC_DIRS;DEFINES;C_FLAGS;CXX_FLAGS;LD_FLAGS;BDPI_FILES"
                                ${ARGN})
  # Use absolute path
  if(NOT IS_ABSOLUTE ROOT_SOURCE)
    set(ROOT_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/${ROOT_SOURCE}")
  endif()

  # Flags for Bluesim and elaboration
  list(PREPEND BLUESIM_BSC_FLAGS "-sim" "-elab")

  # Set BSC search paths
  _bsc_flags_set_search_paths(BLUESIM_BSC_FLAGS
                              SRC_DIRS ${BLUESIM_SRC_DIRS})

  # Append all defined macros
  _bsc_flags_append_macro_definitions(BLUESIM_BSC_FLAGS
                                      DEFINES ${BLUESIM_DEFINES})

  # Redirect all generated intermediate files to the build directory
  _bsc_flags_redirect_output_dir(BLUESIM_BSC_FLAGS
                                 OUTPUT_DIRS "-bdir" "-simdir" "-info-dir")

  set(BSC_COMMAND ${BSC_BIN} ${BLUESIM_BSC_FLAGS})

  # 1. Partial compilation
  _bsc_compile_recursively(BLUESPEC_OBJECTS ${ROOT_SOURCE} BLUESIM
    BSC_FLAGS ${BLUESIM_BSC_FLAGS})

  # 2. Bluesim code generation
  set(ELAB_MODULE "${TOP_MODULE}.ba")

  # Elaborate Bluesim top module
  add_custom_command(
    OUTPUT  ${ELAB_MODULE}
    COMMAND ${BSC_COMMAND} "-g" ${TOP_MODULE} ${BLUESIM_BSC_FLAGS} ${ROOT_SOURCE}
    DEPENDS ${BLUESPEC_OBJECTS}
    VERBATIM)

  # 3. Link Bluesim executable
  message(STATUS "Checking number of physical cores")
  cmake_host_system_information(RESULT N
                                QUERY NUMBER_OF_PHYSICAL_CORES)
  message(STATUS "Number of physical cores: ${N}")

  # Setup bluesim link flags
  _set_bluesim_link_flags(BLUESIM_LINK_FLAGS
                          C_FLAGS   ${BLUESIM_CFLAGS}
                          CXX_FLAGS ${BLUESIM_CXX_FLAGS}
                          LD_FLAGS  ${BLUESIM_LD_FLAGS})

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

  add_custom_command(
    OUTPUT  ${BLUESIM_TARGETS}
    COMMAND ${BSC_COMMAND} "-parallel-sim-link" ${N} "-e" ${TOP_MODULE}
            "-o" ${CMAKE_BINARY_DIR}/${SIM_EXE} ${BLUESIM_LINK_FLAGS}
            ${BLUESIM_BDPI_FILES}
    DEPENDS ${ELAB_MODULE}
    COMMENT "Linking Bluesim executable ${SIM_EXE}"
    VERBATIM)

  add_custom_target(Bluesim.${SIM_EXE} ALL
    DEPENDS ${BLUESIM_TARGETS})
endfunction()
