cmake_minimum_required(VERSION 3.22)

if(_BLUESIM_SYSTEMC)
  return()
endif()
set(_BLUESIM_SYSTEMC)

include(BluespecUtils)

# Function: add_bluesim_systemc_library
#   Add a library for the Bluesim SystemC model generated by Bluespec.
#
# Arguments:
#   TARGET      - The target name.
#   TOP_MODULE  - Top module to generate the Bluesim executable.
#   ROOT_SOURCE - Source to the root compilation unit.
#   C_LIBS      - Foreign C source/object files to link against.
#   BSC_FLAGS   - Multiple flags to be appended during compilation.
#   SRC_DIRS    - List of directories for *.bsv and *.bo.
#   LINK_LIBS   - List of Bluespec library targets to link against.
#   LINK_C_LIBS - List of foreign C library targets to link against.
#   C_FLAGS     - Arguments passed to the C compiler.
#   CXX_FLAGS   - Arguments passed to the C++ compiler.
#   CPP_FLAGS   - Arguments passed to the C preprocessor.
#   LD_FLAGS    - Arguments passed to the C/C++ linker.
#
# Generates:
#   A target named <TARGET> and a Bluesim SystemC target Bluesim.SystemC.lib<TARGET>
function(add_bluesim_systemc_library TARGET TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(BSIM_SC ""
                                ""
                                "BSC_FLAGS;SRC_DIRS;LINK_LIBS;LINK_C_LIBS;C_FLAGS;CXX_FLAGS;CPP_FLAGS;LD_FLAGS"
                                ${ARGN})
  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)
  list(TRANSFORM BSIM_SC_C_LIBS PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")

  # Create Bluesim SystemC target
  set(BSIM_SC_TARGET "Bluesim.SystemC.lib${TARGET}")

  # Generate simulation sources under TARGET's binary directory
  set(SIMDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${BSIM_SC_TARGET}.dir)

  # Determine output path and set it as the target's dependency
  if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(TARGET_LIB_DIR ${CMAKE_LIBRARY_OUTPUT_DIRECTORY})
  elseif(CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
    set(TARGET_LIB_DIR ${CMAKE_ARCHIVE_OUTPUT_DIRECTORY})
  else()
    set(TARGET_LIB_DIR ${SIMDIR})
  endif()
  set(TARGET_LIB "${TARGET_LIB_DIR}/lib${TARGET}.a")
  add_custom_target(${BSIM_SC_TARGET} ALL DEPENDS ${TARGET_LIB})

  # Add dependencies if specified
  if(BSIM_SC_LINK_LIBS)
    add_dependencies(${BSIM_SC_TARGET} ${BSIM_SC_LINK_LIBS})
  endif()

  # Make output paths for bluespec objects
  set(BDIR ${SIMDIR}/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  bsc_setup_path_flags(BSIM_SC_BSC_FLAGS
    BDIR ${BDIR}
    INFO_DIR ${INFO_DIR}
    SIMDIR ${SIMDIR}
    SRC_DIRS ${BSIM_SC_SRC_DIRS}
    LINK_LIBS ${BSIM_SC_LINK_LIBS}
  )

  # Flags for Bluesim and elaboration
  bsc_setup_sim_flags(BSIM_SC_BSC_FLAGS)
  set(BSC_COMMAND ${BSC_BIN} ${BSIM_SC_BSC_FLAGS})

  # 1. Partial compilation
  bsc_pre_elaboration(BLUE_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${BSIM_SC_BSC_FLAGS})

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
    VERBATIM)

  bsc_get_bluesim_targets(BLUESIM_TARGETS ${TOP_MODULE} SIMDIR ${SIMDIR})
  bsc_get_bluesim_sc_targets(BLUESIM_SC_TARGETS ${TOP_MODULE} SIMDIR ${SIMDIR})
  bsc_get_parallel_sim_link_jobs(JOBS)
  bsc_get_link_c_lib_files(LINK_C_LIB_FILES LINK_C_LIBS ${BSIM_SC_LINK_C_LIBS})
  bsc_setup_systemc_include_flags(SYSTEMC_INCLUDE_FLAGS)
  bsc_setup_c_cxx_flags(C_CXX_FLAGS
    C_FLAGS ${BSIM_SC_C_FLAGS}
    CXX_FLAGS ${BSIM_SC_CXX_FLAGS}
    CPP_FLAGS ${BSIM_SC_CPP_FLAGS}
    LD_FLAGS ${BSIM_SC_LD_FLAGS}
  )

  # 3. Generate SystemC model
  add_custom_command(
    OUTPUT  ${BLUESIM_TARGETS} ${BLUESIM_SC_TARGETS}
    COMMAND ${BSC_COMMAND} ${C_CXX_FLAGS} "-systemc" "-parallel-sim-link" ${JOBS}
            "-e" ${TOP_MODULE} ${SYSTEMC_INCLUDE_FLAGS} ${LINK_C_LIB_FILES}
    DEPENDS ${ELAB_MODULE} ${BSIM_SC_LINK_C_LIBS}
    COMMENT "Generating SystemC model for ${TOP_MODULE}"
    VERBATIM
  )

  # 4. Link generated objects into a static library
  string(REPLACE "${CMAKE_BINARY_DIR}/" "" TARGET_LIB_PATH ${TARGET_LIB})
  add_custom_command(
    OUTPUT  ${TARGET_LIB}
    COMMAND "${CMAKE_AR}" "rcs" ${TARGET_LIB} `echo *.o`
    WORKING_DIRECTORY ${SIMDIR}
    DEPENDS ${BLUESIM_TARGETS} ${BLUESIM_SC_TARGETS}
    COMMENT "Linking Bluesim SystemC library ${TARGET_LIB_PATH}"
  )

  # Import the compiled Bluesim SystemC library as CXX library
  add_library(${TARGET} INTERFACE IMPORTED GLOBAL)
  add_dependencies(${TARGET} ${BSIM_SC_TARGET})
  set_target_properties(${TARGET}
    PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${SIMDIR}"
      INTERFACE_LINK_LIBRARIES "${TARGET_LIB}")
  target_link_libraries(${TARGET} INTERFACE BSC::bskernel BSC::bsprim)
endfunction()
