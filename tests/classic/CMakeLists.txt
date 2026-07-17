cmake_minimum_required(VERSION 3.30)
project(RegressionClassic LANGUAGES NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../../BluespecCMake.cmake")

bsc_add_library(classic SOURCES bsv/Classic.bs)

bsc_add_bluesim_executable(simc TOP mkTbC SOURCE bsv/TbC.bsv)
bsc_target_link_libraries(simc PRIVATE classic)
