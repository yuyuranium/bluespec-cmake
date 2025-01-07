cmake_minimum_required(VERSION 3.22)

if(__add_bluespec)
  return()
endif()
set(__add_bluespec ON)

include(BluespecUtils)

# Get number of pyhsical cores
cmake_host_system_information(RESULT NPROC
                              QUERY NUMBER_OF_PHYSICAL_CORES)

include(BluespecLibrary)

function(add_bsim_executable SIM_EXE TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(BSIM ""
                             ""
                             "BSC_FLAGS;LINK_FLAGS;SRC_DIRS;LINK_LIBS"
                             ${ARGN})
  # Create Bluesim target
  set(TARGET "Bluesim.${SIM_EXE}")
  set(SIMDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir)
  # Prefer CMAKE_RUNTIME_OUTPUT_DIRECTORY
  if(CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(SIM_EXE_BIN ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE})
    set(SIM_EXE_SO ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE}.so)
    file(MAKE_DIRECTORY ${CMAKE_RUNTIME_OUTPUT_DIRECTORY})
  else()
    set(SIM_EXE_BIN ${SIMDIR}/${SIM_EXE})
    set(SIM_EXE_SO ${SIMDIR}/${SIM_EXE}.so)
  endif()
  add_custom_target(${TARGET} ALL DEPENDS ${SIM_EXE_BIN})
  if(BSIM_LINK_LIBS)
    add_dependencies(${TARGET} ${BSIM_LINK_LIBS})
  endif()

  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Make output paths for blue objects
  set(BDIR ${SIMDIR}/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  bsc_setup_path_flags(BSIM_BSC_FLAGS
    BDIR     ${BDIR}
    INFO_DIR ${BDIR}
    SIMDIR   ${SIMDIR}
    SRC_DIRS 
      ${BSIM_SRC_DIRS}
    LINK_LIBS
      ${BSIM_LINK_LIBS}
  )

  # Flags for Bluesim and elaboration
  list(PREPEND BSIM_BSC_FLAGS "-sim" "-elab")
  set(BSC_COMMAND ${BSC_BIN} ${BSIM_BSC_FLAGS})

  # 1. Partial compilation
  bsc_pre_elaboration(BLUE_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${BSIM_BSC_FLAGS})

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
                             "BSC_FLAGS;SRC_DIRS;LINK_LIBS"
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
  if(VLOG_LINK_LIBS)
    add_dependencies(${TARGET} ${VLOG_LINK_LIBS})
  endif()

  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Make output paths for blue objects
  set(BDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  bsc_setup_path_flags(VLOG_BSC_FLAGS
    BDIR ${BDIR}
    INFO_DIR ${BDIR}
    VDIR ${VDIR}
    SRC_DIRS 
      ${VLOG_SRC_DIRS}
    LINK_LIBS
      ${VLOG_LINK_LIBS}
  )

  # Flags for Bluesim and elaboration
  list(PREPEND VLOG_BSC_FLAGS "-verilog" "-elab")
  set(BSC_COMMAND ${BSC_BIN} ${VLOG_BSC_FLAGS})

  # 1. Partial compilation
  bsc_pre_elaboration(BLUE_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${VLOG_BSC_FLAGS})

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
                                "BSC_FLAGS;SRC_DIRS;LINK_LIBS"
                                ${ARGN})
  # Create Bluesim subtarget
  set(BSIM_TARGET "${TARGET}.SystemC.${TOP_MODULE}")

  # Generate simulation sources under TARGET's binary directory
  get_target_property(BINARY_DIR ${TARGET} BINARY_DIR)
  set(SIMDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${BSIM_TARGET}.dir)
  set(GENERATED_SC_SOURCE "${SIMDIR}/${TOP_MODULE}_systemc.cxx")
  set(GENERATED_SC_HEADER "${SIMDIR}/${TOP_MODULE}_systemc.h")
  set(GENERATED_SC_OBJECT "${SIMDIR}/${TOP_MODULE}_systemc.o")
  set(SC_TARGETS ${GENERATED_SC_SOURCE}
                 ${GENERATED_SC_HEADER}
                 ${GENERATED_SC_OBJECT})
  set(LIB_TOP_MODULE "${SIMDIR}/lib${TOP_MODULE}.a")

  add_custom_target(${BSIM_TARGET} ALL DEPENDS ${SC_TARGETS} ${LIB_TOP_MODULE})
  if(BSIM_SC_LINK_LIBS)
    add_dependencies(${BSIM_TARGET} ${BSIM_SC_LINK_LIBS})
  endif()

  # Add dependency to the target
  add_dependencies(${TARGET} ${BSIM_TARGET})

  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Make output paths for blue objects
  set(BDIR ${SIMDIR}/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  bsc_setup_path_flags(BSIM_SC_BSC_FLAGS
    BDIR ${BIDR}
    INFO_DIR ${INFO_DIR}
    SIMDIR ${SIMDIR}
    SRC_DIRS
      ${BSIM_SC_SRC_DIRS}
    LINK_LIBS
      ${BSIM_SC_LINK_LIBS}
  )

  # Flags for Bluesim and elaboration
  list(PREPEND BSIM_SC_BSC_FLAGS "-sim" "-elab")
  set(BSC_COMMAND ${BSC_BIN} ${BSIM_SC_BSC_FLAGS})

  # 1. Partial compilation
  bsc_pre_elaboration(BLUE_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${BSIM_SC_BSC_FLAGS})

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

  # 4. Link generated object into a static library
  get_filename_component(PKG_NAME ${ROOT_SOURCE} NAME_WE)  # Assume package name is file name
  set(GET_OBJ_COMMAND "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/synmodules.tcl"
                      ${BSIM_SC_BSC_FLAGS} "${PKG_NAME}")
  add_custom_command(
    OUTPUT  ${LIB_TOP_MODULE}
    COMMAND "${CMAKE_AR}" "rcs" ${LIB_TOP_MODULE} `${GET_OBJ_COMMAND} | xargs ls -d 2> /dev/null`
            ${GENERATED_CXX_OBJECTS}
    WORKING_DIRECTORY ${SIMDIR}
    DEPENDS ${BSIM_SC_TARGETS}
  )

  _bsc_find_bluesim(BLUESIM_INCLUDE)
  target_include_directories(${TARGET} PUBLIC ${SIMDIR} ${BLUESIM_INCLUDE})
  target_link_libraries(${TARGET} ${GENERATED_SC_OBJECT} ${LIB_TOP_MODULE}
                                  BSC::systemc BSC::bskernel BSC::bsprim)
endfunction()
