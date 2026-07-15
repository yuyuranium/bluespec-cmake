cmake_minimum_required(VERSION 3.22)

macro(_bsc_find_bin _name _var)
  if(NOT ${_var})
    find_program(${_var}_TMP NAMES ${_name} HINTS ENV BLUESPEC_HOME DOC "Path to ${_name}")
    if(NOT ${_var}_TMP)
      message(FATAL_ERROR "${_name} binary not found!")
    endif()
    file(REAL_PATH ${${_var}_TMP} ${_var})
    message(STATUS "Found ${_name}: ${${_var}}")
	unset(${_var}_TMP)
  endif()
endmacro()

macro(_bsc_find_library _lib_name)
  set(_target "BSC::${_lib_name}")
  if(NOT TARGET ${_target})
    get_filename_component(_BIN_DIR "${BSC_BIN}" PATH)
    set(_LIB_HINT "${_BIN_DIR}/../lib/Bluesim")

    find_library(LIB_${_lib_name}_TMP NAMES ${_lib_name} HINTS "${_LIB_HINT}" ENV BLUESPECDIR)
    file(REAL_PATH ${LIB_${_lib_name}_TMP} LIB_${_lib_name})

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
    unset(LIB_${_lib_name}_TMP)
  endif()
endmacro()

_bsc_find_bin(bsc     BSC_BIN)
_bsc_find_bin(bluetcl BLUETCL_BIN)

get_filename_component(_BSC_BIN_DIR "${BSC_BIN}" PATH)
get_filename_component(BSC_LIBRARY_DIR "${_BSC_BIN_DIR}/../lib/Verilog" ABSOLUTE)
if(NOT IS_DIRECTORY "${BSC_LIBRARY_DIR}")
  message(FATAL_ERROR "Bluespec Verilog library not found: ${BSC_LIBRARY_DIR}")
endif()

_bsc_find_library(bskernel)
_bsc_find_library(bsprim)
