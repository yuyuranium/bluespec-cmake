cmake_minimum_required(VERSION 3.30)

project(BluespecCMake VERSION 1.0.0 LANGUAGES NONE)

if(NOT DEFINED CMAKE_INSTALL_LIBDIR)
  # GNUInstallDirs cannot infer an architecture for a LANGUAGES NONE project.
  # The package is intentionally language-neutral, so use the conventional
  # lib directory unless the caller selected another one.
  set(CMAKE_INSTALL_LIBDIR lib CACHE PATH "Install library directory")
endif()
include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

set(BSC_CMAKE_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/cmake/BluespecCMake")

configure_package_config_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/BluespecCMakeConfig.cmake.in"
  "${CMAKE_CURRENT_BINARY_DIR}/BluespecCMakeConfig.cmake"
  INSTALL_DESTINATION "${BSC_CMAKE_INSTALL_DIR}"
)
write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/BluespecCMakeConfigVersion.cmake"
  VERSION "${PROJECT_VERSION}"
  COMPATIBILITY SameMajorVersion
)

install(
  FILES
    BluespecCMake.cmake
    BluespecTargets.cmake
    FindBluespecToolchain.cmake
  DESTINATION "${BSC_CMAKE_INSTALL_DIR}"
)
install(
  PROGRAMS
    tools/bsc_cmake_driver.py
    tools/bsc_graph.py
  DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}/bluespec-cmake"
)
install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/BluespecCMakeConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/BluespecCMakeConfigVersion.cmake"
  DESTINATION "${BSC_CMAKE_INSTALL_DIR}"
)

# Vendored use has the same entry point as installed use.
include("${CMAKE_CURRENT_SOURCE_DIR}/BluespecCMake.cmake")
