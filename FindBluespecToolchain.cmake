cmake_minimum_required(VERSION 3.22)

macro(_bsc_find_bin _name _var)
  if(NOT ${_var})
    find_program(${_var} NAMES ${_name} HINTS ENV BLUESPEC_HOME DOC "Path to ${_name}")
    if(NOT ${_var})
      message(FATAL_ERROR "${_name} binary not found!")
    endif()
    message(STATUS "Found ${_name}: ${${_var}}")
  endif()
endmacro()

macro(_bsc_find_library _lib_name)
  set(_target "BSC::${_lib_name}")
  if(NOT TARGET ${_target})
    get_filename_component(_BIN_DIR "${BSC_BIN}" PATH)
    set(_LIB_HINT "${_BIN_DIR}/../lib/Bluesim")

    find_library(LIB_${_lib_name} NAMES ${_lib_name} HINTS "${_LIB_HINT}" ENV BLUESPECDIR)

    if(LIB_${_lib_name})
      message(STATUS "Found ${_lib_name}: ${LIB_${_lib_name}}")
      add_library(${_target} INTERFACE IMPORTED GLOBAL)
      set_target_properties(${_target} PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${_LIB_HINT}"
        INTERFACE_LINK_LIBRARIES "${LIB_${_lib_name}}"
      )
    else()
      message(FATAL_ERROR "${_lib_name} not found! Check BLUESPECDIR.")
    endif()
  endif()
endmacro()

_bsc_find_bin(bsc     BSC_BIN)
_bsc_find_bin(bluetcl BLUETCL_BIN)

_bsc_find_library(bskernel)
_bsc_find_library(bsprim)
