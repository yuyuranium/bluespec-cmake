cmake_minimum_required(VERSION 3.22)

if(_BLUESPEC_VERILOG_GENERATION)
  return()
endif()
set(_BLUESPEC_VERILOG_GENERATION)

include(BluespecUtils)

# Function: generate_verilog
#   Generate Verilog source for a Bluespec module.
#
# Arguments:
#   TOP_MODULE  - Top module to generate the Bluesim executable.
#   ROOT_SOURCE - Source to the root compilation unit.
#   BSC_FLAGS   - Multiple flags to be appended during compilation.
#   SRC_DIRS    - List of directories for *.bsv and *.bo.
#   LINK_LIBS   - List of targets to link against.
#
# Generates:
#   A target named Verilog.<TOP_MODULE>.
function(generate_verilog TOP_MODULE ROOT_SOURCE)
  cmake_parse_arguments(VLOG ""
                             ""
                             "BSC_FLAGS;SRC_DIRS;LINK_LIBS"
                             ${ARGN})
  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Create Verilog target
  set(TARGET "Verilog.${TOP_MODULE}")

  # Prefer CMAKE_LIBRARY_OUTPUT_DIRECTORY
  if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(VDIR ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/Verilog)
  elseif(CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
    set(VDIR ${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/Verilog)
  else()
    set(VDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir)
  endif()
  file(MAKE_DIRECTORY ${VDIR})

  # Determine output verilog path and set it as the target's dependency
  set(GENERATED_VLOG_SOURCE ${VDIR}/${TOP_MODULE}.v)
  add_custom_target(${TARGET} ALL DEPENDS ${GENERATED_VLOG_SOURCE})

  # Add dependencies if specified
  if(VLOG_LINK_LIBS)
    add_dependencies(${TARGET} ${VLOG_LINK_LIBS})
  endif()

  # Make output paths for blue objects
  set(BDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir/${TOP_MODULE}.dir)
  file(MAKE_DIRECTORY ${BDIR})

  # Setup search and output path
  bsc_setup_path_flags(VLOG_BSC_FLAGS
    BDIR ${BDIR}
    INFO_DIR ${BDIR}
    VDIR ${VDIR}
    SRC_DIRS ${VLOG_SRC_DIRS}
    LINK_LIBS ${VLOG_LINK_LIBS}
  )

  # Flags for Bluesim and elaboration
  bsc_setup_verilog_flags(VLOG_BSC_FLAGS)
  set(BSC_COMMAND ${BSC_BIN} ${VLOG_BSC_FLAGS})

  # 1. Partial compilation
  bsc_pre_elaboration(BLUESPEC_OBJECTS ${ROOT_SOURCE} BSC_FLAGS ${VLOG_BSC_FLAGS})

  # 2. Verilog code generation
  string(REPLACE "${CMAKE_BINARY_DIR}/" "" GENERATED_VLOG_SOURCE_PATH ${GENERATED_VLOG_SOURCE})
  add_custom_command(
    OUTPUT  ${GENERATED_VLOG_SOURCE}
    COMMAND ${BSC_COMMAND} "-g" ${TOP_MODULE} ${ROOT_SOURCE}
            && touch ${GENERATED_VLOG_SOURCE}
    DEPENDS ${BLUESPEC_OBJECTS}
    COMMENT "Generating Verilog source ${GENERATED_VLOG_SOURCE_PATH}"
    VERBATIM
  )
endfunction()
