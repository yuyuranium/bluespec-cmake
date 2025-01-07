cmake_minimum_required(VERSION 3.22)

if(_BLUESPEC_UTILS)
  return()
endif()
set(_BLUESPEC_UTILS)

include(FindBluespecToolchain)

# Function: bsc_setup_path_flags
#   Setup all search paths and modified the bsc flags. See 3.6 Setting the path.
#
# Parameters:
#   BSC_FLAGS - (Inout) List of compilation flags with search paths set up.
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

  if(_SIMDIR)
    list(APPEND _BSC_FLAGS "-simdir" ${_SIMDIR})
  endif()

  if(_VIDR)
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

# Function: bsc_pre_elaboration
#   Helper function to compile a root source file recursively to Bluespec
#   objects (*.bo).
#
# Arguments:
#   BLUESPEC_OBJECTS - (Output) A list of Bluespec object files (*.bo).
#   ROOT_SOURCE      - Source to the root compilation unit.
#   BSC_FLAGS        - Multiple flags to be appended during compilation.
function(bsc_pre_elaboration BLUESPEC_OBJECTS ROOT_SOURCE)
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
    ERROR_VARIABLE  DEP_ERROR_VARIABLE
    OUTPUT_VARIABLE DEP_CHECK_OUTPUT)

  if(NOT ${DEP_CHECK_RESULT} EQUAL "0")
    message(STATUS ${DEP_ERROR_VARIABLE})
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
      OUTPUT ${TARGET}
      COMMAND
        ${BSC_COMMAND} ${SRC}
      DEPENDS
        ${DEPS})
  endforeach()

  # Return the bluespec objects
  set(${BLUESPEC_OBJECTS} ${_BLUESPEC_OBJECTS} PARENT_SCOPE)
  message(STATUS "Checking dependencies for ${ROOT_SOURCE} - done")
endfunction()