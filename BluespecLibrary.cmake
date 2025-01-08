cmake_minimum_required(VERSION 3.22)

if(_BLUESPEC_LIBRARY)
  return()
endif()
set(_BLUESPEC_LIBRARY)

include(BluespecUtils)

# Function: add_bsc_library
#   Compile *.bsv files to *.bo binary representation.
#
# Arguments:
#   ROOT_SOURCE - Source to the root compilation unit.
#   BSC_FLAGS   - Multiple flags to be appended during compilation.
#   SRC_DIRS    - List of directories for *.bsv and *.bo.
#   LINK_LIBS   - List of targets to link against.
#
# Generates:
#   A target whose name is the package name of the source.
function(add_bsc_library ROOT_SOURCE)
  cmake_parse_arguments(BO ""
                           ""
                           "BSC_FLAGS;SRC_DIRS;LINK_LIBS"
                           ${ARGN})
  # Use absolute path
  get_filename_component(ROOT_SOURCE ${ROOT_SOURCE} ABSOLUTE)

  # Get package name and set it as target
  bsc_package_name(TARGET ${ROOT_SOURCE})

  # Determine BDIR
  if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(BDIR ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/Libraries)
  elseif(CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
    set(BDIR ${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/Libraries)
  else()
    set(BDIR ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir)
  endif()
  file(MAKE_DIRECTORY ${BDIR})

  # Determine output library path and set it as the target's dependency
  set(GENERATED_BLUESIM_LIB ${BDIR}/${TARGET}.bo)
  add_custom_target(${TARGET} ALL DEPENDS ${GENERATED_BLUESIM_LIB})

  # Add dependencies if specified
  if(BO_LINK_LIBS)
    add_dependencies(${TARGET} ${BO_LINK_LIBS})
  endif()

  # To link with the target, one should search for the BDIR (LINK_DIRECTORIES)
  set_target_properties(
    ${TARGET}
    PROPERTIES
      LINK_DIRECTORIES ${BDIR}
  )

  bsc_setup_path_flags(BO_BSC_FLAGS
    BDIR ${BDIR}
    INFO_DIR ${BDIR}
    SRC_DIRS ${BO_SRC_DIRS}
    LINK_LIBS ${BO_LINK_LIBS}
  )

  # Compile to *.bo
  bsc_pre_elaboration(BLUESPEC_OBJECTS ${ROOT_SOURCE}
    BSC_FLAGS ${BO_BSC_FLAGS}
  )
endfunction()
