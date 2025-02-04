cmake_minimum_required(VERSION 3.22)

if(_BLUESPEC_UTILS)
  return()
endif()
set(_BLUESPEC_UTILS)

include(FindBluespecToolchain)
include(ProcessorCount)

# Function: bsc_package_name
#   Compute the package name of given bsv source. See 2.1 Components of a BSV Design.
#   All BSV code is assumed to be inside a package. Furthermore BSC and other tools assume that
#   there is one package per file, and they use the package name to derive the file name.
#
# Arguments:
#   PKG_NAME - (Output) Package name of the bsv source.
#   SOURCE   - Source file (*.bsv).
function(bsc_package_name PKG_NAME SOURCE)
  get_filename_component(_PKG_NAME ${SOURCE} NAME_WE)
  get_filename_component(_EXT ${SOURCE} EXT)
  # Make sure file extension is bsv.
  if(${_EXT} STREQUAL ".bsv")
    set(${PKG_NAME} ${_PKG_NAME} PARENT_SCOPE)
  endif()
endfunction()

# Function: bsc_setup_path_flags
#   Setup all search paths and modified the bsc flags. See 3.6 Setting the path.
#
# Arguments:
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
# Argument:
#   LINK_C_LIB_FILES - (Output) List of paths to all C libraries
#   LINK_C_LIB       - List of C library targets
function(bsc_get_link_c_lib_files LINK_C_LIB_FILES LINK_C_LIB)
  set(_LINK_C_LIB_FILES)
  foreach(C_LIB ${LINK_C_LIB})
    list(APPEND _LINK_C_LIB_FILES $<TARGET_FILE:${C_LIB}>)
  endforeach()
  set(${LINK_C_LIB_FILES} ${_LINK_C_LIB_FILES} PARENT_SCOPE)
endfunction()

# Function: bsc_get_parallel_sim_link_jobs
#   Get the number of jobs for parallel sim link.
#
# Argument:
#   JOBS - (Output) Number of jobs for parallel sim link.
function(bsc_get_parallel_sim_link_jobs JOBS)
  ProcessorCount(_JOBS)
  if(NOT _JOBS)
    set(_JOBS 4) # Use 4 if we cannot get number of processor count
  endif()
  set(${JOBS} ${_JOBS} PARENT_SCOPE)
endfunction()

# Function: bsc_setup_sim_flags
#   Setup bsc flags for Bluesim. See 3.1 Common compile and linking flags.
#
# Arguments:
#   BSC_FLAGS - (Inout) List of compilation flags with search paths set up.
function(bsc_setup_sim_flags BSC_FLAGS)
  set(_BSC_FLAGS ${${BSC_FLAGS}})
  list(PREPEND _BSC_FLAGS "-sim" "-elab")
  set(${BSC_FLAGS} ${_BSC_FLAGS} PARENT_SCOPE)
endfunction()

# Function: bsc_setup_sim_flags
#   Setup bsc C/C++ flags. See 3.14 C/C++ flags.
#
# Arguments:
#   C_CXX_FLAGS - (Out) List of compilation flags with search paths set up.
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
# Arguments:
#   CXX_SYSTEMC_FLAGS - (Inout) List of compilation flags with cxx systemc paths set up.
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
# Arguments:
#   BSC_FLAGS - (Inout) List of compilation flags with search paths set up.
function(bsc_setup_verilog_flags BSC_FLAGS)
  set(_BSC_FLAGS ${${BSC_FLAGS}})
  list(PREPEND _BSC_FLAGS "-verilog" "-elab")
  set(${BSC_FLAGS} ${_BSC_FLAGS} PARENT_SCOPE)
endfunction()

# Function: bsc_get_bluesim_targets
#   Determine all generated Bluesim targets.
#
# Arguments:
#   BLUESIM_TARGETS - (Output) A list of paths to the Bluesim targets.
#   TOP_MODULE      - Top module to generate the Bluesim executable.
#   SIMDIR             - Output directory for Bluesim intermediate files.
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
    list(TRANSFORM _BLUESIM_TARGETS PREPEND "${SIMDIR}/")
  endif()
  set(${BLUESIM_TARGETS} ${_BLUESIM_TARGETS} PARENT_SCOPE)
endfunction()

# Function: bsc_get_bluesim_sc_targets
#   Determine all generated Bluesim targets.
#
# Arguments:
#   BLUESIM_SC_TARGETS - (Output) A list of paths to the Bluesim SystemC targets.
#   TOP_MODULE         - Top module to generate the Bluesim executable.
#   SIMDIR             - Output directory for Bluesim intermediate files.
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
    string(REPLACE "${CMAKE_BINARY_DIR}/" "" TARGET_PATH ${TARGET})

    string(REPLACE "\t" "" DEPS ${DEPS}) # remove tabs
    separate_arguments(DEPS)             # convert to list

    list(GET DEPS 0 SRC) # first dependency is the source file

    # Command to build the target
    add_custom_command(
      OUTPUT ${TARGET}
      COMMAND ${BSC_COMMAND} ${SRC}
      COMMENT "Building Bluespec object ${TARGET_PATH}"
      DEPENDS ${DEPS})
  endforeach()

  # Return the bluespec objects
  set(${BLUESPEC_OBJECTS} ${_BLUESPEC_OBJECTS} PARENT_SCOPE)
  message(STATUS "Checking dependencies for ${ROOT_SOURCE} - done")
endfunction()
