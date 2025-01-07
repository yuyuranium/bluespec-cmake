cmake_minimum_required(VERSION 3.22)

# This script finds and exposes the following variables:
# - BSC_BIN
# - BLUETCL_BIN
#
# And following targets:
# - BSC::bskernel
# - BSC::bsprim

#####################
# Bluespec compiler #
#####################
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

###########
# Bluetcl #
###########
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

############################
# Bluesim kernel libraries #
############################
if(NOT TARGET BSC::bskernel OR NOT TARGET BSC::bsprim)
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
