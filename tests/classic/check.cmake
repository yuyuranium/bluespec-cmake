# Post-build verification for the classic (.bs) regression test.
if(NOT DEFINED BUILD_DIR)
  message(FATAL_ERROR "check.cmake requires -DBUILD_DIR=<test build tree>")
endif()

set(_sim "${BUILD_DIR}/CMakeFiles/simc.dir/artifacts/simc")
if(NOT EXISTS "${_sim}")
  message(FATAL_ERROR "Bluesim executable was not produced: ${_sim}")
endif()
execute_process(
  COMMAND "${_sim}"
  OUTPUT_VARIABLE _output
  RESULT_VARIABLE _result)
if(NOT _result EQUAL 0)
  message(FATAL_ERROR "Bluesim run failed (${_result}):\n${_output}")
endif()
if(NOT _output MATCHES "result=2")
  message(FATAL_ERROR "unexpected simulation output:\n${_output}")
endif()
