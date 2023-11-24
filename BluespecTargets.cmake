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

function(_bsc_find_systemc SYSTEMC_HOME)
  if(NOT TARGET BSC::systemc)
    # Use BSC defined env variable
    find_path(SYSTEMC_INCLUDE NAMES systemc.h
      HINTS "${SYSTEMC}" ENV SYSTEMC
      PATH_SUFFIXES include)
    find_library(SYSTEMC_LIBDIR NAMES systemc
      HINTS "${SYSTEMC}" ENV SYSTEMC
      PATH_SUFFIXES lib)

    if(SYSTEMC_INCLUDE AND SYSTEMC_LIBDIR)
      add_library(BSC::systemc INTERFACE IMPORTED)
      set_target_properties(BSC::systemc
        PROPERTIES
          INTERFACE_INCLUDE_DIRECTORIES "${SYSTEMC_INCLUDE}"
          INTERFACE_LINK_LIBRARIES "${SYSTEMC_LIBDIR}")

      # Get SYSTEMC_HOME from include directory
      get_filename_component(_SYSTEMC_HOME ${SYSTEMC_INCLUDE} DIRECTORY)
      set(SYSTEMC_HOME ${_SYSTEMC_HOME} PARENT_SCOPE)
      return()
    endif()

    # If env variable is not set, use CMake module
    find_package(SystemCLanguage CONFIG REQUIRED)
    if(SystemCLanguage_FOUND)
      add_library(BSC::systemc INTERFACE IMPORTED)
      get_target_property(SYSTEMC_INCLUDE SystemC::systemc INTERFACE_INCLUDE_DIRECTORIES)
      set_target_properties(BSC::systemc
        PROPERTIES
          INTERFACE_INCLUDE_DIRECTORIES "${SYSTEMC_INCLUDE}"
          INTERFACE_LINK_LIBRARIES "SystemC::systemc")

      # Get SYSTEMC_HOME from include directory
      get_filename_component(_SYSTEMC_HOME ${SYSTEMC_INCLUDE} DIRECTORY)
      set(SYSTEMC_HOME ${_SYSTEMC_HOME} PARENT_SCOPE)
      return()
    endif()

    message("SystemC not found. This can be fixed by doing either of the following steps:")
    message("- set SYSTEMC (environment) variable; or")
    message("- use the CMake module of your SystemC installation (may require CMAKE_PREFIX_PATH)")
    message(FATAL_ERROR "SystemC not found")
  else()
    get_target_property(SYSTEMC_INCLUDE BSC::systemc INTERFACE_INCLUDE_DIRECTORIES)
    get_filename_component(_SYSTEMC_HOME ${SYSTEMC_INCLUDE} DIRECTORY)
    set(SYSTEMC_HOME ${_SYSTEMC_HOME} PARENT_SCOPE)
  endif()
endfunction()

function(_bsc_find_bluesim BLUESIM_INCLUDE)
  get_filename_component(BSC_BIN_PATH "${BSC_BIN}" PATH)
  set(_BSC_LIB_PATH "${BSC_BIN_PATH}/../lib/Bluesim")

  if(NOT TARGET BSC::bskernel AND NOT TARGET BSC::bsprim)
    find_library(BLUESIM_BSKERNEL NAMES bskernel
      HINTS "${_BSC_LIB_PATH}" ENV BLUESPECDIR)

    find_library(BLUESIM_BSPRIME NAMES bsprim
      HINTS "${_BSC_LIB_PATH}" ENV BLUESPECDIR)

    if(BLUESIM_BSKERNEL AND BLUESIM_BSPRIME)
      add_library(BSC::bskernel INTERFACE IMPORTED)
      set_target_properties(BSC::bskernel
        PROPERTIES
          INTERFACE_INCLUDE_DIRECTORIES "${BLUESIM_BSKERNEL}"
          INTERFACE_LINK_LIBRARIES "${BLUESIM_BSKERNEL}")

      add_library(BSC::bsprim INTERFACE IMPORTED)
      set_target_properties(BSC::bsprim
        PROPERTIES
          INTERFACE_INCLUDE_DIRECTORIES "${BLUESIM_BSPRIME}"
          INTERFACE_LINK_LIBRARIES "${BLUESIM_BSPRIME}")

      # Return Bluesim include library
      set(${BLUESIM_INCLUDE} ${_BSC_LIB_PATH} PARENT_SCOPE)
      return()
    endif()
    message("Bluesim library not found. This can be fixed by setting BLUESPECDIR (environment) variable")
    message(FATAL_ERROR "Bluesim library not found")
  else()
    set(${BLUESIM_INCLUDE} ${_BSC_LIB_PATH} PARENT_SCOPE)
  endif()
endfunction()

function(_bsc_link_bluesim)
endfunction()

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

# Macro to setup search path
macro(_bsc_setup_search_path BSC_FLAGS SRC_DIRS)
  # Set bsc search path
  set(_BSC_PATH "%/Libraries:${CMAKE_CURRENT_SOURCE_DIR}")
  foreach(DIR ${${SRC_DIRS}})
    get_filename_component(ABS_DIR ${DIR} ABSOLUTE)
    string(APPEND _BSC_PATH ":${ABS_DIR}")
  endforeach()
  list(APPEND ${BSC_FLAGS} "-p" ${_BSC_PATH})
endmacro()

function(add_bsim_executable SIM_EXE TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(BSIM ""
                             ""
                             "BSC_FLAGS;LINK_FLAGS;SRC_DIRS"
                             ${ARGN})
  # Create Bluesim target
  set(TARGET "Bluesim.${SIM_EXE}")
  set(SIMDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir)
  # Prefer CMAKE_RUNTIME_OUTPUT_DIRECTORY
  if(CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(SIM_EXE_BIN ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE})
    set(SIM_EXE_SO ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE}.so)
  else()
    set(SIM_EXE_BIN ${SIMDIR}/${SIM_EXE})
    set(SIM_EXE_SO ${SIMDIR}/${SIM_EXE}.so)
  endif()
  add_custom_target(${TARGET} ALL DEPENDS ${SIM_EXE_BIN})

  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Make output paths for blue objects
  set(BDIR ${SIMDIR}/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  _bsc_setup_search_path(BSIM_BSC_FLAGS BSIM_SRC_DIRS)
  list(APPEND BSIM_BSC_FLAGS "-bdir" ${BDIR})
  list(APPEND BSIM_BSC_FLAGS "-info-dir" ${BDIR})
  list(APPEND BSIM_BSC_FLAGS "-simdir" ${SIMDIR})

  # Flags for Bluesim and elaboration
  list(PREPEND BSIM_BSC_FLAGS "-sim" "-elab")
  set(BSC_COMMAND ${BSC_BIN} ${BSIM_BSC_FLAGS})

  # 1. Partial compilation
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
  set(GENERATED_CXX_HEADERS "${TOP_MODULE}.h"   "model_${TOP_MODULE}.h")
  set(GENERATED_CXX_OBJECTS "${TOP_MODULE}.o"   "model_${TOP_MODULE}.o")

  # All bluesim targets
  list(TRANSFORM GENERATED_CXX_SOURCES PREPEND ${SIMDIR}/)
  list(TRANSFORM GENERATED_CXX_HEADERS PREPEND ${SIMDIR}/)
  list(TRANSFORM GENERATED_CXX_OBJECTS PREPEND ${SIMDIR}/)
  set(BLUESIM_TARGETS ${GENERATED_CXX_SOURCES}
                      ${GENERATED_CXX_HEADERS}
                      ${GENERATED_CXX_OBJECTS}
                      ${SIM_EXE_BIN}
                      ${SIM_EXE_SO})

  # 3. Link Bluesim executable
  add_custom_command(
    OUTPUT  ${BLUESIM_TARGETS}
    COMMAND ${BSC_COMMAND} "-quiet" "-parallel-sim-link" ${NPROC} "-e" ${TOP_MODULE}
            "-o" ${SIM_EXE_BIN}
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
  # Prefer CMAKE_LIBRARY_OUTPUT_DIRECTORY
  if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(VDIR ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/Verilog)
    file(MAKE_DIRECTORY ${VDIR})
  else()
    set(VDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir)
  endif()
  set(GENERATED_VLOG_SOURCE ${VDIR}/${TOP_MODULE}.v)

  add_custom_target(${TARGET} ALL DEPENDS ${GENERATED_VLOG_SOURCE})

  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Make output paths for blue objects
  set(BDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  _bsc_setup_search_path(VLOG_BSC_FLAGS VLOG_SRC_DIRS)
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

function(target_link_bsim_systemc TARGET TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(BSIM_SC ""
                                ""
                                "BSC_FLAGS;SRC_DIRS"
                                ${ARGN})
  # Create Bluesim subtarget
  set(BSIM_TARGET "${TARGET}.SystemC.${TOP_MODULE}")

  # Generate simulation sources under TARGET's binary directory
  get_target_property(BINARY_DIR ${TARGET} BINARY_DIR)
  set(SIMDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir)
  set(GENERATED_SC_SOURCE "${SIMDIR}/${TOP_MODULE}_systemc.cxx")
  set(GENERATED_SC_HEADER "${SIMDIR}/${TOP_MODULE}_systemc.h")
  set(GENERATED_SC_OBJECT "${SIMDIR}/${TOP_MODULE}_systemc.o")
  set(SC_TARGETS ${GENERATED_SC_SOURCE}
                 ${GENERATED_SC_HEADER}
                 ${GENERATED_SC_OBJECT})

  add_custom_target(${BSIM_TARGET} ALL DEPENDS ${SC_TARGETS})

  # Add dependency to the target
  add_dependencies(${TARGET} ${BSIM_TARGET})

  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Make output paths for blue objects
  set(BDIR ${SIMDIR}/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  _bsc_setup_search_path(BSIM_SC_BSC_FLAGS BSIM_SC_SRC_DIRS)
  list(APPEND BSIM_SC_BSC_FLAGS "-bdir" ${BDIR})
  list(APPEND BSIM_SC_BSC_FLAGS "-info-dir" ${BDIR})
  list(APPEND BSIM_SC_BSC_FLAGS "-simdir" ${SIMDIR})

  # Flags for Bluesim and elaboration
  list(PREPEND BSIM_SC_BSC_FLAGS "-sim" "-elab")
  set(BSC_COMMAND ${BSC_BIN} ${BSIM_SC_BSC_FLAGS})

  # 1. Partial compilation
  _bsc_compile_recursively(BLUE_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${BSIM_SC_BSC_FLAGS})

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
  set(GENERATED_CXX_HEADERS "${TOP_MODULE}.h"   "model_${TOP_MODULE}.h")
  set(GENERATED_CXX_OBJECTS "${TOP_MODULE}.o"   "model_${TOP_MODULE}.o")

  # All bluesim targets
  list(TRANSFORM GENERATED_CXX_SOURCES PREPEND ${SIMDIR}/)
  list(TRANSFORM GENERATED_CXX_HEADERS PREPEND ${SIMDIR}/)
  list(TRANSFORM GENERATED_CXX_OBJECTS PREPEND ${SIMDIR}/)
  set(BSIM_SC_TARGETS ${GENERATED_CXX_SOURCES}
                      ${GENERATED_CXX_HEADERS}
                      ${GENERATED_CXX_OBJECTS}
                      ${SC_TARGETS})

  # 3. Generate SystemC model
  _bsc_find_systemc(SYSTEMC_HOME)
  get_target_property(CXX_STANDARD ${TARGET} CXX_STANDARD)
  add_custom_command(
    OUTPUT  ${BSIM_SC_TARGETS}
    COMMAND ${CMAKE_COMMAND} -E env SYSTEMC=${SYSTEMC_HOME}
            ${BSC_COMMAND} "-systemc" "-parallel-sim-link" ${NPROC} "-e" ${TOP_MODULE}
            "-Xc++" "${CMAKE_CXX${CXX_STANDARD}_STANDARD_COMPILE_OPTION}"
            && touch ${BSIM_SC_TARGETS}
    DEPENDS ${ELAB_MODULE}
    COMMENT "Generating SystemC model for ${TOP_MODULE}"
    VERBATIM)

  _bsc_find_bluesim(BLUESIM_INCLUDE)
  target_include_directories(${TARGET} PUBLIC ${SIMDIR} ${BLUESIM_INCLUDE})
  target_link_libraries(${TARGET} ${GENERATED_CXX_OBJECTS} ${GENERATED_SC_OBJECT}
                                  BSC::systemc BSC::bskernel BSC::bsprim)
endfunction()
