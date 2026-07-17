# Post-build verification for the waveform regression test.
if(NOT DEFINED BUILD_DIR)
  message(FATAL_ERROR "check.cmake requires -DBUILD_DIR=<test build tree>")
endif()

set(_vcd "${BUILD_DIR}/CMakeFiles/wave.dir/artifacts/wave.vcd")
if(NOT EXISTS "${_vcd}")
  message(FATAL_ERROR "VCD waveform was not produced: ${_vcd}")
endif()
file(SIZE "${_vcd}" _size)
if(_size EQUAL 0)
  message(FATAL_ERROR "VCD waveform is empty: ${_vcd}")
endif()
# The register toggles before $finish, so the dump must contain value changes.
file(READ "${_vcd}" _contents)
if(NOT _contents MATCHES "\\$var")
  message(FATAL_ERROR "VCD waveform has no variable declarations: ${_vcd}")
endif()
