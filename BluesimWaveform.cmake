cmake_minimum_required(VERSION 3.22)

if(_BLUESIM_WAVEFORM)
  return()
endif()
set(_BLUESIM_WAVEFORM)

# Function: generate_bluesim_waveform
#   Run the Bluesim executable and generate a VCD waveform file.
#
# Arguments:
#   SIM_EXE   - Name of the Bluesim executable (must match the one passed to add_bluesim_executable).
#   SIM_FLAGS - Optional list of flags to pass to the Bluesim executable.
#
# Generates:
#   A target named "Bluesim.<SIM_EXE>.vcd" that runs the executable to produce the VCD waveform file.

function(generate_bluesim_waveform SIM_EXE)
  # Parse optional arguments
  cmake_parse_arguments(BSIM "" "" "SIM_FLAGS" ${ARGN})

  # Determine the executable and VCD output paths based on CMake settings
  if(CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(SIM_EXE_BIN ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${SIM_EXE})
    set(VCD_FILE ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/waveform/${SIM_EXE}.vcd)
  else()
    set(SIM_EXE_BIN ${CMAKE_BINARY_DIR}/${SIM_EXE})
    set(VCD_FILE ${CMAKE_BINARY_DIR}/waveform/${SIM_EXE}.vcd)
  endif()

  # Ensure the output directory exists
  get_filename_component(VCD_DIR ${VCD_FILE} DIRECTORY)
  file(MAKE_DIRECTORY ${VCD_DIR})

  # Define the custom target name
  set(TARGET_NAME "Bluesim.${SIM_EXE}.vcd")

  # Add a custom command to generate the VCD file
  add_custom_command(
    OUTPUT ${VCD_FILE}
    COMMAND ${SIM_EXE_BIN} "-V" ${VCD_FILE} ${BSIM_SIM_FLAGS}
    DEPENDS ${SIM_EXE_BIN}
    COMMENT "Generating VCD waveform file for Bluesim simulation: ${VCD_FILE}"
    VERBATIM
    WORKING_DIRECTORY ${VCD_DIR}
  )

  # Add the custom target that depends on the VCD file
  add_custom_target(${TARGET_NAME} ALL DEPENDS ${VCD_FILE})

  # Ensure the target depends on the Bluesim executable being built
  add_dependencies(${TARGET_NAME} Bluesim.${SIM_EXE})
endfunction()