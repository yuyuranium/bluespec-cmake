# Post-build verification for the shared-components regression test.
if(NOT DEFINED BUILD_DIR)
  message(FATAL_ERROR "check.cmake requires -DBUILD_DIR=<test build tree>")
endif()

set(_sim "${BUILD_DIR}/CMakeFiles/sim.dir/artifacts/sim")
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
# result(1) = right(left(1)) = (1 + 1) + 2 with WIDTH=8 from the PUBLIC
# definition on base.
if(NOT _output MATCHES "result=4")
  message(FATAL_ERROR "unexpected simulation output:\n${_output}")
endif()

foreach(_artifact
    "${BUILD_DIR}/CMakeFiles/rtl.dir/artifacts/mkTb.v"
    "${BUILD_DIR}/CMakeFiles/rtl.dir/artifacts/rtl.f"
    "${BUILD_DIR}/CMakeFiles/check_core.dir/.success")
  if(NOT EXISTS "${_artifact}")
    message(FATAL_ERROR "expected artifact was not produced: ${_artifact}")
  endif()
endforeach()

# Each backend owns one package set shared by all matching endpoints.
foreach(_backend "" "/sim" "/verilog")
  foreach(_package base/Base base/Extra left/Left right/Right core/TopLib)
    string(REPLACE "/" ";" _parts "${_package}")
    list(GET _parts 0 _component)
    list(GET _parts 1 _name)
    set(_bo "${BUILD_DIR}/CMakeFiles/${_component}.dir${_backend}/bo/${_name}.bo")
    if(NOT EXISTS "${_bo}")
      message(FATAL_ERROR "expected package output was not produced: ${_bo}")
    endif()
  endforeach()
endforeach()
