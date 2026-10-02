cmake_minimum_required(VERSION 3.30)
project(SynthesisBoundaries LANGUAGES NONE)
include("${CMAKE_CURRENT_LIST_DIR}/../../BluespecCMake.cmake")

bsc_add_library(child SOURCES Child.bsv)
bsc_target_compile_definitions(child PRIVATE CHILD_WIDTH=8)
bsc_add_verilog(rtl TOP mkTop SOURCE Top.bsv)
bsc_target_compile_definitions(rtl PRIVATE CHILD_WIDTH=16)
bsc_target_link_libraries(rtl PRIVATE child)
bsc_add_bluesim_executable(sim TOP mkTop SOURCE Top.bsv)
bsc_target_compile_definitions(sim PRIVATE CHILD_WIDTH=16)
bsc_target_link_libraries(sim PRIVATE child)

enable_testing()
get_target_property(_rtl_dir rtl BSC_ARTIFACT_DIRECTORY)
add_test(NAME verilog_synthesis_boundary
  COMMAND "${CMAKE_COMMAND}" "-DARTIFACT_DIR=${_rtl_dir}"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyHierarchy.cmake")
get_target_property(_sim sim BSC_EXECUTABLE)
add_test(NAME bluesim_synthesis_boundary COMMAND "${_sim}")
set_tests_properties(bluesim_synthesis_boundary PROPERTIES TIMEOUT 10)
