cmake_minimum_required(VERSION 3.24...3.28)

project(
  bluespec-cmake
  DESCRIPTION "CMake modules for Bluespec targets"
  LANGUAGES CXX
  VERSION 0.0.0
)

if(CMAKE_PROJECT_NAME STREQUAL PROJECT_NAME)
  set(INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/lib/cmake/${PROJECT_NAME}")

  # Install CMake scripts
  install(
    FILES
      ./BluespecTargets.cmake
      ./BluespecUtils.cmake
      ./FindBluespecToolchain.cmake
    DESTINATION
      ${INSTALL_DIR}
  )

  # Install tcl scripts
  install(
    PROGRAMS
      ./synmodules.tcl
    DESTINATION
      ${INSTALL_DIR}
  )

  # Generate package config file
  include(CMakePackageConfigHelpers)
  configure_package_config_file(
    bluespec-cmake-config.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/bluespec-cmake-config.cmake
    INSTALL_DESTINATION
      ${INSTALL_DIR}
  )

  # Generate package version file
  write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/bluespec-cmake-config-version.cmake
    VERSION
      ${PROJECT_VERSION}
    COMPATIBILITY
      AnyNewerVersion
  )

  # Install package config and version files
  install(
    FILES
      ${CMAKE_CURRENT_BINARY_DIR}/bluespec-cmake-config.cmake
      ${CMAKE_CURRENT_BINARY_DIR}/bluespec-cmake-config-version.cmake
    DESTINATION
      ${INSTALL_DIR}
  )
endif()
