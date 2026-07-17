cmake_minimum_required(VERSION 3.30)
project(RegressionSharedComponents LANGUAGES NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../../BluespecCMake.cmake")

bsc_add_library(base SOURCES bsv/Base.bsv bsv/Extra.bsv)
bsc_target_compile_definitions(base PUBLIC WIDTH=8)

bsc_add_library(left SOURCES bsv/Left.bsv)
bsc_target_link_libraries(left PUBLIC base)

bsc_add_library(right SOURCES bsv/Right.bsv)
bsc_target_link_libraries(right PUBLIC base)

bsc_add_library(core SOURCES bsv/TopLib.bsv)
bsc_target_link_libraries(core PUBLIC left right)

bsc_add_bluesim_executable(sim TOP mkTb SOURCE bsv/Tb.bsv)
bsc_target_link_libraries(sim PRIVATE core)

bsc_add_verilog(rtl TOP mkTb SOURCE bsv/Tb.bsv)
bsc_target_link_libraries(rtl PRIVATE core)

bsc_add_check(check_core LIBRARIES core)
