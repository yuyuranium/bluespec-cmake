cmake_minimum_required(VERSION 3.30)
include_guard(GLOBAL)

set(BLUESPEC_CMAKE_ROOT "${CMAKE_CURRENT_LIST_DIR}" CACHE INTERNAL
  "BluespecCMake module directory" FORCE)
include("${CMAKE_CURRENT_LIST_DIR}/FindBluespecToolchain.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/BluespecTargets.cmake")
