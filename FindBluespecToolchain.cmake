cmake_minimum_required(VERSION 3.22)

# Section: Bluespec compiler
#   Search working Bluespec compiler.
#
# Expose:
#   BSC_BIN - Path to the Bluespec compiler executable.
if(NOT BSC_BIN)
  message(STATUS "Checking for working Bluespec compiler")
  find_program(BSC_BIN
    NAMES bsc
    HINT ENV BLUESPEC_HOME
    DOC "Bluespec compiler")
  message(STATUS "Found working Bluespec compiler: ${BSC_BIN}")

  if(NOT BSC_BIN)
    message(FATAL_ERROR "Bluespec compiler binary not found!")
  endif()
endif()

# Section: Bluetcl
#   Search Bluetcl executable.
#
# Expose:
#   BLUETCL_BIN - Path to the Bluetcl executable.
if(NOT BLUETCL_BIN)
  message(STATUS "Checking for working Bluetcl")
  find_program(BLUETCL_BIN
    NAMES bluetcl
    HINT ENV BLUESPEC_HOME
    DOC "Bluetcl")
  message(STATUS "Found working Bluetcl: ${BLUETCL_BIN}")

  if(NOT BLUETCL_BIN)
    message(FATAL_ERROR "Bluetcl binary not found!")
  endif()
endif()

# Section: Bluesim bskernel
#   Search the Bluesim bskernel library.
#
# Expose:
#   BSC::bskernel - Imported target for the Bluesim bskernel.
if(NOT TARGET BSC::bskernel)
  get_filename_component(BSC_BIN_PATH "${BSC_BIN}" PATH)
  set(_BSC_LIB_PATH "${BSC_BIN_PATH}/../lib/Bluesim")

  message(STATUS "Checking for BSC::bskernel")
  find_library(BLUESIM_BSKERNEL NAMES bskernel
    HINTS "${_BSC_LIB_PATH}" ENV BLUESPECDIR)

  if(BLUESIM_BSKERNEL)
    message(STATUS "Found bskernel: ${BLUESIM_BSKERNEL}")
    add_library(BSC::bskernel INTERFACE IMPORTED)
    set_target_properties(BSC::bskernel
      PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${_BSC_LIB_PATH}"
        INTERFACE_LINK_LIBRARIES "${BLUESIM_BSKERNEL}")
  else()
    message("bskernel not found. This can be fixed by setting BLUESPECDIR (environment) variable")
    message(FATAL_ERROR "bskernel not found")
  endif()
endif()

# Section: Bluesim bsprim
#   Search the Bluesim bsprim library.
#
# Expose:
#   BSC::bsprim - Imported target for the Bluesim bsprim.
if(NOT TARGET BSC::bsprim)
  get_filename_component(BSC_BIN_PATH "${BSC_BIN}" PATH)
  set(_BSC_LIB_PATH "${BSC_BIN_PATH}/../lib/Bluesim")

  message(STATUS "Checking for BSC::bsprim")
  find_library(BLUESIM_BSPRIME NAMES bsprim
    HINTS "${_BSC_LIB_PATH}" ENV BLUESPECDIR)

  if(BLUESIM_BSPRIME)
    message(STATUS "Found bsprim: ${BLUESIM_BSPRIME}")
    add_library(BSC::bsprim INTERFACE IMPORTED)
    set_target_properties(BSC::bsprim
      PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${_BSC_LIB_PATH}"
        INTERFACE_LINK_LIBRARIES "${BLUESIM_BSPRIME}")
  else()
    message("bsprim not found. This can be fixed by setting BLUESPECDIR (environment) variable")
    message(FATAL_ERROR "bsprim not found")
  endif()
endif()
