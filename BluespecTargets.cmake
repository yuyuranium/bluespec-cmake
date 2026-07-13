cmake_minimum_required(VERSION 3.30)
include_guard(GLOBAL)

if(NOT DEFINED BLUESPEC_CMAKE_ROOT)
  set(BLUESPEC_CMAKE_ROOT "${CMAKE_CURRENT_LIST_DIR}")
endif()

set(_BSC_CUSTOM_TRANSITIVE_PROPERTIES
  BSC_COMPILE_DEFINITIONS
  BSC_COMPILE_OPTIONS
  BSC_LINK_OPTIONS
  BSC_NATIVE_SOURCES
  BSC_NATIVE_LIBRARIES
)

if(CMAKE_CONFIGURATION_TYPES)
  message(FATAL_ERROR
    "BluespecCMake Phase 1 supports single-config generators only; "
    "use Ninja or Ninja Multi-Config after the Phase 2 implementation.")
endif()
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug CACHE STRING "BluespecCMake build type" FORCE)
endif()
set(BSC_CMAKE_CONFIG "${CMAKE_BUILD_TYPE}" CACHE INTERNAL "BluespecCMake configuration" FORCE)

if(NOT CMAKE_GENERATOR MATCHES "Ninja")
  message(FATAL_ERROR "BluespecCMake requires a Ninja generator")
endif()

# The finalization callback is deferred until the directory scope closes.
# Keep the tool path in the cache so it remains visible from that deferred
# call (ordinary include-scope variables are not reliable there).
set(BSC_GRAPH_TOOL "${BLUESPEC_GRAPH_TOOL}" CACHE INTERNAL
  "BluespecCMake graph tool" FORCE)
if(NOT EXISTS "${BSC_GRAPH_TOOL}")
  message(FATAL_ERROR "BluespecCMake graph tool not found: ${BSC_GRAPH_TOOL}")
endif()

# BSC package compilation can have a very large per-process memory footprint.
# Keep it in a dedicated pool without constraining endpoint or unrelated
# native compilation scheduled by the outer Ninja process.
set(BSC_CMAKE_PACKAGE_JOBS 1 CACHE STRING
  "Maximum concurrent BSV package compilations")
if(NOT "${BSC_CMAKE_PACKAGE_JOBS}" MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR "BSC_CMAKE_PACKAGE_JOBS must be a positive integer")
endif()
set_property(GLOBAL APPEND PROPERTY JOB_POOLS
  "bsc_package=${BSC_CMAKE_PACKAGE_JOBS}")

function(_bsc_require_target TARGET)
  if(NOT TARGET "${TARGET}")
    message(FATAL_ERROR "BluespecCMake: target '${TARGET}' does not exist")
  endif()
endfunction()

function(_bsc_target_work_directory OUT TARGET)
  _bsc_require_target("${TARGET}")
  get_target_property(_work "${TARGET}" BSC_WORK_DIRECTORY)
  if(NOT _work OR _work MATCHES "-NOTFOUND$")
    set(_work "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir")
    set_property(TARGET "${TARGET}" PROPERTY BSC_WORK_DIRECTORY "${_work}")
  endif()
  set(${OUT} "${_work}" PARENT_SCOPE)
endfunction()

function(_bsc_require_bsc_target TARGET)
  _bsc_require_target("${TARGET}")
  get_target_property(_kind "${TARGET}" BSC_TARGET_KIND)
  if(NOT _kind)
    message(FATAL_ERROR
      "BluespecCMake: '${TARGET}' is not a BSV component or endpoint target")
  endif()
endfunction()

function(_bsc_set_transitive_properties TARGET)
  set_property(TARGET "${TARGET}" PROPERTY
    TRANSITIVE_COMPILE_PROPERTIES "${_BSC_CUSTOM_TRANSITIVE_PROPERTIES}")
  set_property(TARGET "${TARGET}" PROPERTY
    TRANSITIVE_LINK_PROPERTIES "${_BSC_CUSTOM_TRANSITIVE_PROPERTIES}")
endfunction()

function(_bsc_append_target_property TARGET PROPERTY)
  _bsc_require_target("${TARGET}")
  get_target_property(_old "${TARGET}" "${PROPERTY}")
  if(NOT _old OR _old MATCHES "-NOTFOUND$")
    set(_old "")
  endif()
  set(_new "${_old}")
  foreach(_value IN LISTS ARGN)
    if(NOT "${_value}" STREQUAL "")
      list(APPEND _new "${_value}")
    endif()
  endforeach()
  # Compiler and linker options are ordered token streams.  Repeated option
  # markers can be significant, for example:
  #
  #   -Xc++ -I/path/to/systemc -Xc++ --coverage
  #
  # Removing duplicate tokens would drop the second -Xc++ and make BSC parse
  # --coverage as a source file.  Other properties contain unordered sets of
  # sources or target names and can still be deduplicated safely.
  if(NOT "${PROPERTY}" MATCHES "^(INTERFACE_)?BSC_(COMPILE|LINK)_OPTIONS$")
    list(REMOVE_DUPLICATES _new)
  endif()
  set_property(TARGET "${TARGET}" PROPERTY "${PROPERTY}" "${_new}")
endfunction()

function(_bsc_check_option OPTION API)
  if("${OPTION}" MATCHES "^-D($|.)" OR "${OPTION}" IN_LIST _BSC_DRIVER_FLAGS)
    message(FATAL_ERROR
      "${API}: '${OPTION}' is managed by BluespecCMake. "
      "Use the corresponding bsc_target_* API instead.")
  endif()
endfunction()

set(_BSC_DRIVER_FLAGS
  -D -p -bdir -simdir -vdir -info-dir -g -e -o -u -elab
  -sim -verilog -systemc -parallel-sim-link -I -L -l
)

function(_bsc_parse_scoped TARGET PROPERTY)
  set(_scope PRIVATE)
  foreach(_item IN LISTS ARGN)
    if(_item STREQUAL "PRIVATE" OR _item STREQUAL "PUBLIC" OR _item STREQUAL "INTERFACE")
      set(_scope "${_item}")
      continue()
    endif()

    if("${PROPERTY}" STREQUAL "BSC_COMPILE_OPTIONS" OR
       "${PROPERTY}" STREQUAL "BSC_LINK_OPTIONS")
      _bsc_check_option("${_item}" "${PROPERTY}")
    endif()

    if(_scope STREQUAL "PRIVATE" OR _scope STREQUAL "PUBLIC")
      _bsc_append_target_property("${TARGET}" "${PROPERTY}" "${_item}")
    endif()
    if(_scope STREQUAL "PUBLIC" OR _scope STREQUAL "INTERFACE")
      _bsc_append_target_property("${TARGET}" "INTERFACE_${PROPERTY}" "${_item}")
      get_target_property(_interface "${TARGET}" BSC_INTERFACE_TARGET)
      if(_interface AND NOT _interface MATCHES "-NOTFOUND$")
        _bsc_append_target_property(
          "${_interface}" "INTERFACE_${PROPERTY}" "${_item}")
      endif()
    endif()

    get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
    if(_self AND (_scope STREQUAL "PRIVATE" OR _scope STREQUAL "PUBLIC"))
      _bsc_append_target_property("${_self}" "${PROPERTY}" "${_item}")
    endif()
  endforeach()
endfunction()

function(_bsc_collect_components TARGET)
  get_property(_seen GLOBAL PROPERTY BSC_COMPONENT_COLLECT_SEEN)
  if(NOT _seen)
    set(_seen "")
  endif()
  if("${TARGET}" IN_LIST _seen)
    return()
  endif()
  list(APPEND _seen "${TARGET}")
  set_property(GLOBAL PROPERTY BSC_COMPONENT_COLLECT_SEEN "${_seen}")

  get_target_property(_kind "${TARGET}" BSC_TARGET_KIND)
  if(_kind STREQUAL "COMPONENT")
    get_property(_components GLOBAL PROPERTY BSC_COMPONENT_COLLECT_RESULT)
    list(APPEND _components "${TARGET}")
    set_property(GLOBAL PROPERTY BSC_COMPONENT_COLLECT_RESULT "${_components}")
    get_target_property(_public "${TARGET}" BSC_PUBLIC_LINK_LIBRARIES)
    get_target_property(_private "${TARGET}" BSC_PRIVATE_LINK_LIBRARIES)
    foreach(_dep IN LISTS _public _private)
      if(TARGET "${_dep}")
        _bsc_collect_components("${_dep}")
      endif()
    endforeach()
  elseif(_kind STREQUAL "ENDPOINT")
    get_target_property(_links "${TARGET}" BSC_LINK_LIBRARIES)
    foreach(_dep IN LISTS _links)
      if(TARGET "${_dep}")
        _bsc_collect_components("${_dep}")
      endif()
    endforeach()
  endif()
endfunction()

function(_bsc_refresh_endpoint_components TARGET)
  set_property(GLOBAL PROPERTY BSC_COMPONENT_COLLECT_SEEN "")
  set_property(GLOBAL PROPERTY BSC_COMPONENT_COLLECT_RESULT "")
  _bsc_collect_components("${TARGET}")
  get_property(_components GLOBAL PROPERTY BSC_COMPONENT_COLLECT_RESULT)
  set_property(TARGET "${TARGET}" PROPERTY BSC_COMPONENTS "${_components}")

  set(_requests "")
  set(_request_targets "")
  foreach(_component IN LISTS _components)
    get_target_property(_request "${_component}" BSC_COMPONENT_REQUEST)
    if(_request)
      list(APPEND _requests "${_request}")
    endif()
    get_target_property(_request_target "${_component}" BSC_COMPONENT_REQUEST_TARGET)
    if(_request_target AND NOT _request_target MATCHES "-NOTFOUND$")
      list(APPEND _request_targets "${_request_target}")
    endif()
  endforeach()
  set_property(TARGET "${TARGET}" PROPERTY BSC_COMPONENT_REQUESTS "${_requests}")
  set_property(TARGET "${TARGET}" PROPERTY BSC_COMPONENT_REQUEST_TARGETS "${_request_targets}")
endfunction()

function(_bsc_refresh_all_endpoints)
  get_property(_endpoints GLOBAL PROPERTY BSC_ENDPOINTS)
  foreach(_endpoint IN LISTS _endpoints)
    _bsc_refresh_endpoint_components("${_endpoint}")
  endforeach()
endfunction()

function(_bsc_schedule_finalize TARGET)
  get_target_property(_binary_directory "${TARGET}" BSC_BINARY_DIRECTORY)
  get_target_property(_source_directory "${TARGET}" BSC_SOURCE_DIRECTORY)
  get_property(_scheduled GLOBAL PROPERTY BSC_FINALIZE_DIRECTORIES)
  if(NOT _scheduled)
    set(_scheduled "")
  endif()
  list(FIND _scheduled "${_binary_directory}" _index)
  if(_index EQUAL -1)
    list(APPEND _scheduled "${_binary_directory}")
    set_property(GLOBAL PROPERTY BSC_FINALIZE_DIRECTORIES "${_scheduled}")
    # Custom-command outputs must be registered from the directory that owns
    # them. Schedule one finalizer per directory containing BSC targets.
    cmake_language(DEFER DIRECTORY "${_source_directory}"
      CALL _bsc_finalize)
  endif()
endfunction()

function(_bsc_component_request TARGET)
  get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
  _bsc_target_work_directory(_work "${TARGET}")
  set(_request "${_work}/component.request")
  file(MAKE_DIRECTORY "${_work}")
  # file(GENERATE) is configure-time output and therefore has no Ninja rule
  # that can recreate the request after `cmake --build --target clean`.
  # Keep its template outside the cleaned target work directory, then make
  # the request itself an ordinary custom-command output.
  set(_template "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.component.request.in")
  file(GENERATE OUTPUT "${_template}" CONTENT
"schema=1
kind=component
name=${TARGET}
sources_begin
$<JOIN:$<TARGET_PROPERTY:${TARGET},BSC_PACKAGE_SOURCES>,\n>
sources_end
definitions_begin
$<JOIN:$<TARGET_PROPERTY:${_self},BSC_COMPILE_DEFINITIONS>,\n>
$<JOIN:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_COMPILE_DEFINITIONS>,\n>
definitions_end
compile_options_begin
$<JOIN:$<TARGET_PROPERTY:${_self},BSC_COMPILE_OPTIONS>,\n>
$<JOIN:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_COMPILE_OPTIONS>,\n>
compile_options_end
native_sources_begin
$<JOIN:$<TARGET_PROPERTY:${_self},BSC_NATIVE_SOURCES>,\n>
$<JOIN:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_NATIVE_SOURCES>,\n>
native_sources_end
native_libraries_begin
$<JOIN:$<GENEX_EVAL:$<TARGET_PROPERTY:${_self},BSC_NATIVE_LIBRARIES>>,\n>
$<JOIN:$<GENEX_EVAL:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_NATIVE_LIBRARIES>>,\n>
native_libraries_end
")
  add_custom_command(
    OUTPUT "${_request}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${_template}" "${_request}"
    DEPENDS "${_template}"
    VERBATIM)
  # A named producer keeps this cross-directory OUTPUT visible to CMake when
  # an endpoint in a child directory consumes the component request.
  set(_request_target "${TARGET}__bsc_component_request")
  add_custom_target("${_request_target}" DEPENDS "${_request}")
  set_property(TARGET "${TARGET}" PROPERTY BSC_COMPONENT_REQUEST "${_request}")
  set_property(TARGET "${TARGET}" PROPERTY BSC_COMPONENT_REQUEST_TARGET "${_request_target}")
endfunction()

function(_bsc_endpoint_request TARGET BACKEND TOP SOURCE)
  get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
  _bsc_target_work_directory(_work "${TARGET}")
  set(_request "${_work}/endpoint.request")
  file(MAKE_DIRECTORY "${_work}")
  set(_template "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.endpoint.request.in")
  file(GENERATE OUTPUT "${_template}" CONTENT
"schema=1
kind=endpoint
target=${TARGET}
backend=${BACKEND}
top_module=${TOP}
top_source=${SOURCE}
configuration=${BSC_CMAKE_CONFIG}
work_directory=${_work}
bsc=${BSC_BIN}
bluetcl=${BLUETCL_BIN}
ar=${CMAKE_AR}
component_requests_begin
$<JOIN:$<TARGET_PROPERTY:${TARGET},BSC_COMPONENT_REQUESTS>,\n>
component_requests_end
definitions_begin
$<JOIN:$<TARGET_PROPERTY:${_self},BSC_COMPILE_DEFINITIONS>,\n>
$<JOIN:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_COMPILE_DEFINITIONS>,\n>
definitions_end
compile_options_begin
$<JOIN:$<TARGET_PROPERTY:${_self},BSC_COMPILE_OPTIONS>,\n>
$<JOIN:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_COMPILE_OPTIONS>,\n>
compile_options_end
link_options_begin
$<JOIN:$<TARGET_PROPERTY:${_self},BSC_LINK_OPTIONS>,\n>
$<JOIN:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_LINK_OPTIONS>,\n>
link_options_end
translate_off_regex=$<TARGET_PROPERTY:${TARGET},BSC_TRANSLATE_OFF_REGEX>
require_translate_off_match=$<TARGET_PROPERTY:${TARGET},BSC_REQUIRE_TRANSLATE_OFF_MATCH>
native_sources_begin
$<JOIN:$<TARGET_PROPERTY:${_self},BSC_NATIVE_SOURCES>,\n>
$<JOIN:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_NATIVE_SOURCES>,\n>
native_sources_end
native_libraries_begin
$<JOIN:$<GENEX_EVAL:$<TARGET_PROPERTY:${_self},BSC_NATIVE_LIBRARIES>>,\n>
$<JOIN:$<GENEX_EVAL:$<TARGET_PROPERTY:${_self},INTERFACE_BSC_NATIVE_LIBRARIES>>,\n>
native_libraries_end
")
  add_custom_command(
    OUTPUT "${_request}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${_template}" "${_request}"
    DEPENDS "${_template}"
    VERBATIM)
  set_property(TARGET "${TARGET}" PROPERTY BSC_REQUEST_FILE "${_request}")
endfunction()

function(_bsc_create_endpoint TARGET BACKEND TOP SOURCE LINKABLE)
  if(TARGET "${TARGET}")
    message(FATAL_ERROR "BluespecCMake: endpoint target '${TARGET}' already exists")
  endif()
  if(LINKABLE STREQUAL "STATIC")
    # The generated archive is represented as an imported static target so
    # CMake can attach the artifact-producing custom target to the actual
    # link item consumed by native targets.
    add_library("${TARGET}" STATIC IMPORTED GLOBAL)
  elseif(LINKABLE)
    add_library("${TARGET}" INTERFACE)
  else()
    add_custom_target("${TARGET}")
  endif()
  set_target_properties("${TARGET}" PROPERTIES
    BSC_TARGET_KIND ENDPOINT
    BSC_ENDPOINT_BACKEND "${BACKEND}"
    BSC_ENDPOINT_TOP "${TOP}"
    BSC_ENDPOINT_SOURCE "${SOURCE}"
    BSC_BINARY_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    BSC_SOURCE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    BSC_WORK_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir")
  add_library("${TARGET}__bsc_self" INTERFACE)
  set_target_properties("${TARGET}__bsc_self" PROPERTIES BSC_TARGET_KIND SELF)
  set_property(TARGET "${TARGET}" PROPERTY BSC_SELF_TARGET "${TARGET}__bsc_self")
  set_property(TARGET "${TARGET}__bsc_self" PROPERTY BSC_LINK_OPTIONS "")
  _bsc_set_transitive_properties("${TARGET}")
  _bsc_set_transitive_properties("${TARGET}__bsc_self")
  set_property(TARGET "${TARGET}" PROPERTY BSC_LINK_LIBRARIES "")
  set_property(GLOBAL APPEND PROPERTY BSC_ENDPOINTS "${TARGET}")
  _bsc_endpoint_request("${TARGET}" "${BACKEND}" "${TOP}" "${SOURCE}")
endfunction()

function(bsc_add_library TARGET)
  if(TARGET "${TARGET}")
    message(FATAL_ERROR "BluespecCMake: target '${TARGET}' already exists")
  endif()
  cmake_parse_arguments(ARG "" "" "SOURCES" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "bsc_add_library(${TARGET}): use the explicit SOURCES keyword")
  endif()
  if(NOT ARG_SOURCES)
    message(FATAL_ERROR "bsc_add_library(${TARGET}): SOURCES is required")
  endif()

  set(_sources "")
  foreach(_source IN LISTS ARG_SOURCES)
    get_filename_component(_absolute "${_source}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    list(APPEND _sources "${_absolute}")
  endforeach()
  add_custom_target("${TARGET}")
  add_library("${TARGET}__bsc_interface" INTERFACE)
  add_library("${TARGET}__bsc_self" INTERFACE)
  set_target_properties("${TARGET}" PROPERTIES
    BSC_TARGET_KIND COMPONENT
    BSC_INTERFACE_TARGET "${TARGET}__bsc_interface"
    BSC_SELF_TARGET "${TARGET}__bsc_self"
    BSC_BINARY_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    BSC_SOURCE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    BSC_WORK_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir"
    BSC_PACKAGE_SOURCES "${_sources}"
    BSC_SELF_LINK_LIBRARIES ""
    BSC_PUBLIC_LINK_LIBRARIES ""
    BSC_PRIVATE_LINK_LIBRARIES "")
  set_target_properties(
    "${TARGET}__bsc_interface" "${TARGET}__bsc_self"
    PROPERTIES BSC_TARGET_KIND SELF)
  _bsc_set_transitive_properties("${TARGET}")
  _bsc_set_transitive_properties("${TARGET}__bsc_interface")
  _bsc_set_transitive_properties("${TARGET}__bsc_self")
  _bsc_component_request("${TARGET}")
  add_custom_target("${TARGET}__bsc_packages")
  set_property(TARGET "${TARGET}" PROPERTY
    BSC_PACKAGE_TARGET "${TARGET}__bsc_packages")
  add_dependencies("${TARGET}" "${TARGET}__bsc_packages")
  set_property(GLOBAL APPEND PROPERTY BSC_COMPONENT_TARGETS "${TARGET}")
  _bsc_schedule_finalize("${TARGET}")
  _bsc_target_work_directory(_work "${TARGET}")
  set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "${_work}/component.request")
endfunction()

function(bsc_target_sources TARGET)
  _bsc_require_bsc_target("${TARGET}")
  cmake_parse_arguments(ARG "" "" "SOURCES" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "bsc_target_sources(${TARGET}): use the explicit SOURCES keyword")
  endif()
  set(_sources "")
  foreach(_source IN LISTS ARG_SOURCES)
    get_filename_component(_absolute "${_source}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    list(APPEND _sources "${_absolute}")
  endforeach()
  _bsc_append_target_property("${TARGET}" BSC_PACKAGE_SOURCES ${_sources})
endfunction()

function(bsc_target_link_libraries TARGET)
  _bsc_require_bsc_target("${TARGET}")
  set(_scope PRIVATE)
  get_target_property(_kind "${TARGET}" BSC_TARGET_KIND)
  foreach(_item IN LISTS ARGN)
    if(_item STREQUAL "PRIVATE" OR _item STREQUAL "PUBLIC" OR _item STREQUAL "INTERFACE")
      set(_scope "${_item}")
      continue()
    endif()
    _bsc_require_bsc_target("${_item}")
    if(_kind STREQUAL "COMPONENT")
      get_target_property(_interface "${TARGET}" BSC_INTERFACE_TARGET)
      get_target_property(_dependency_interface "${_item}" BSC_INTERFACE_TARGET)
      if(_scope STREQUAL "PRIVATE")
        _bsc_append_target_property("${TARGET}" BSC_PRIVATE_LINK_LIBRARIES "${_item}")
      else()
        _bsc_append_target_property("${TARGET}" BSC_PUBLIC_LINK_LIBRARIES "${_item}")
        target_link_libraries("${_interface}" INTERFACE "${_dependency_interface}")
      endif()
      if(_scope STREQUAL "PRIVATE" OR _scope STREQUAL "PUBLIC")
        _bsc_append_target_property("${TARGET}" BSC_SELF_LINK_LIBRARIES "${_item}")
        get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
        target_link_libraries("${_self}" INTERFACE "${_dependency_interface}")
        add_dependencies("${TARGET}" "${_item}")
      endif()
    elseif(_kind STREQUAL "ENDPOINT")
      _bsc_append_target_property("${TARGET}" BSC_LINK_LIBRARIES "${_item}")
      if(TARGET "${_item}")
        add_dependencies("${TARGET}" "${_item}")
        # Keep a hidden interface view for CMake's custom transitive
        # properties.  The driver still receives one request per component,
        # but endpoint-owned top sources must see PUBLIC usage requirements
        # from their linked component closure.
        get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
        get_target_property(_dependency_interface
          "${_item}" BSC_INTERFACE_TARGET)
        target_link_libraries("${_self}" INTERFACE "${_dependency_interface}")
      endif()
    else()
      message(FATAL_ERROR "bsc_target_link_libraries: '${TARGET}' is not linkable")
    endif()
  endforeach()
  if(_kind STREQUAL "ENDPOINT")
    _bsc_refresh_endpoint_components("${TARGET}")
    # Component request files are generated outputs.  The endpoint request
    # contains their paths, but the artifact target must also depend on the
    # named producers so a clean cross-directory build cannot start scanning
    # before a component.request exists.
    get_target_property(_request_targets
      "${TARGET}" BSC_COMPONENT_REQUEST_TARGETS)
    if(_request_targets AND NOT _request_targets MATCHES "-NOTFOUND$" AND
       TARGET "${TARGET}_artifact")
      add_dependencies("${TARGET}_artifact" ${_request_targets})
    endif()
  else()
    _bsc_refresh_all_endpoints()
  endif()
endfunction()

function(bsc_target_compile_definitions TARGET)
  _bsc_require_bsc_target("${TARGET}")
  _bsc_parse_scoped("${TARGET}" BSC_COMPILE_DEFINITIONS ${ARGN})
endfunction()

function(bsc_target_compile_options TARGET)
  _bsc_require_bsc_target("${TARGET}")
  _bsc_parse_scoped("${TARGET}" BSC_COMPILE_OPTIONS ${ARGN})
endfunction()

function(bsc_target_link_options TARGET)
  _bsc_require_bsc_target("${TARGET}")
  _bsc_parse_scoped("${TARGET}" BSC_LINK_OPTIONS ${ARGN})
endfunction()

function(bsc_target_native_sources TARGET)
  _bsc_require_bsc_target("${TARGET}")
  set(_scope PRIVATE)
  foreach(_item IN LISTS ARGN)
    if(_item STREQUAL "PRIVATE" OR _item STREQUAL "PUBLIC" OR _item STREQUAL "INTERFACE")
      set(_scope "${_item}")
      continue()
    endif()
    if(_scope STREQUAL "PRIVATE" OR _scope STREQUAL "PUBLIC")
      _bsc_append_target_property("${TARGET}" BSC_NATIVE_SOURCES "${_item}")
      get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
      if(_self)
        _bsc_append_target_property("${_self}" BSC_NATIVE_SOURCES "${_item}")
      endif()
    endif()
    if(_scope STREQUAL "PUBLIC" OR _scope STREQUAL "INTERFACE")
      _bsc_append_target_property("${TARGET}" INTERFACE_BSC_NATIVE_SOURCES "${_item}")
      get_target_property(_interface "${TARGET}" BSC_INTERFACE_TARGET)
      if(_interface AND NOT _interface MATCHES "-NOTFOUND$")
        _bsc_append_target_property(
          "${_interface}" INTERFACE_BSC_NATIVE_SOURCES "${_item}")
      endif()
      get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
      if(_self)
        _bsc_append_target_property("${_self}" INTERFACE_BSC_NATIVE_SOURCES "${_item}")
      endif()
    endif()
  endforeach()
endfunction()

function(bsc_target_link_native_libraries TARGET)
  _bsc_require_bsc_target("${TARGET}")
  get_target_property(_kind "${TARGET}" BSC_TARGET_KIND)
  set(_scope PRIVATE)
  foreach(_item IN LISTS ARGN)
    if(_item STREQUAL "PRIVATE" OR _item STREQUAL "PUBLIC" OR _item STREQUAL "INTERFACE")
      set(_scope "${_item}")
      continue()
    endif()
    _bsc_require_target("${_item}")
    if(_scope STREQUAL "PRIVATE" OR _scope STREQUAL "PUBLIC")
      _bsc_append_target_property("${TARGET}" BSC_NATIVE_LIBRARIES "$<TARGET_FILE:${_item}>")
      get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
      if(_self)
        _bsc_append_target_property("${_self}" BSC_NATIVE_LIBRARIES "$<TARGET_FILE:${_item}>")
      endif()
      add_dependencies("${TARGET}" "${_item}")
      if(_kind STREQUAL "ENDPOINT" AND TARGET "${TARGET}_artifact")
        add_dependencies("${TARGET}_artifact" "${_item}")
      endif()
    endif()
    if(_scope STREQUAL "PUBLIC" OR _scope STREQUAL "INTERFACE")
      _bsc_append_target_property("${TARGET}" INTERFACE_BSC_NATIVE_LIBRARIES "$<TARGET_FILE:${_item}>")
      get_target_property(_interface "${TARGET}" BSC_INTERFACE_TARGET)
      if(_interface AND NOT _interface MATCHES "-NOTFOUND$")
        _bsc_append_target_property(
          "${_interface}" INTERFACE_BSC_NATIVE_LIBRARIES
          "$<TARGET_FILE:${_item}>")
      endif()
      get_target_property(_self "${TARGET}" BSC_SELF_TARGET)
      if(_self)
        _bsc_append_target_property("${_self}" INTERFACE_BSC_NATIVE_LIBRARIES "$<TARGET_FILE:${_item}>")
      endif()
    endif()
  endforeach()
endfunction()

function(_bsc_add_endpoint_common TARGET BACKEND TOP SOURCE)
  set(_linkable FALSE)
  if(ARGN)
    set(_linkable "${ARGN}")
  endif()
  _bsc_create_endpoint("${TARGET}" "${BACKEND}" "${TOP}" "${SOURCE}" "${_linkable}")
  _bsc_target_work_directory(_work "${TARGET}")
  set(_stamp "${_work}/.success")
  set(_depfile "${_work}/depfile.d")
  set(_artifact_dir "${_work}/artifacts")
  add_custom_target("${TARGET}_artifact" ALL DEPENDS "${_stamp}")
  add_dependencies("${TARGET}" "${TARGET}_artifact")
  set_target_properties("${TARGET}" PROPERTIES
    BSC_ARTIFACT_DIRECTORY "${_artifact_dir}"
    BSC_STAMP "${_stamp}"
    BSC_DEPFILE "${_depfile}")
  set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "${_work}/contexts"
    "${_work}/artifacts"
    "${_work}/bo"
    "${_work}/info"
    "${_work}/scan"
    "${_work}/endpoint.request"
    "${_stamp}"
    "${_depfile}")
  _bsc_schedule_finalize("${TARGET}")
endfunction()

function(_bsc_collect_component_build_closure TARGET)
  get_property(_seen GLOBAL PROPERTY BSC_COMPONENT_BUILD_SEEN)
  if(NOT _seen)
    set(_seen "")
  endif()
  if("${TARGET}" IN_LIST _seen)
    return()
  endif()
  list(APPEND _seen "${TARGET}")
  set_property(GLOBAL PROPERTY BSC_COMPONENT_BUILD_SEEN "${_seen}")
  get_property(_result GLOBAL PROPERTY BSC_COMPONENT_BUILD_RESULT)
  list(APPEND _result "${TARGET}")
  set_property(GLOBAL PROPERTY BSC_COMPONENT_BUILD_RESULT "${_result}")
  get_target_property(_dependencies "${TARGET}" BSC_SELF_LINK_LIBRARIES)
  foreach(_dependency IN LISTS _dependencies)
    _bsc_collect_component_build_closure("${_dependency}")
  endforeach()
endfunction()

function(_bsc_component_build_closure TARGET OUT)
  set_property(GLOBAL PROPERTY BSC_COMPONENT_BUILD_SEEN "")
  set_property(GLOBAL PROPERTY BSC_COMPONENT_BUILD_RESULT "")
  _bsc_collect_component_build_closure("${TARGET}")
  get_property(_result GLOBAL PROPERTY BSC_COMPONENT_BUILD_RESULT)
  set(${OUT} "${_result}" PARENT_SCOPE)
endfunction()

function(_bsc_component_output_paths TARGET OUT_SOURCES OUT_PACKAGES OUT_OUTPUTS)
  get_target_property(_sources "${TARGET}" BSC_PACKAGE_SOURCES)
  _bsc_target_work_directory(_work "${TARGET}")
  set(_packages "")
  set(_outputs "")
  foreach(_source IN LISTS _sources)
    get_filename_component(_package "${_source}" NAME_WE)
    if(_package IN_LIST _packages)
      message(FATAL_ERROR
        "BluespecCMake: component '${TARGET}' provides package '${_package}' more than once")
    endif()
    list(APPEND _packages "${_package}")
    list(APPEND _outputs "${_work}/bo/${_package}.bo")
  endforeach()
  set(${OUT_SOURCES} "${_sources}" PARENT_SCOPE)
  set(${OUT_PACKAGES} "${_packages}" PARENT_SCOPE)
  set(${OUT_OUTPUTS} "${_outputs}" PARENT_SCOPE)
endfunction()

function(_bsc_finalize_component TARGET)
  _bsc_component_build_closure("${TARGET}" _closure)
  _bsc_component_output_paths(
    "${TARGET}" _sources _packages _package_outputs)
  if(NOT _sources)
    message(FATAL_ERROR
      "BluespecCMake component '${TARGET}' has no explicit BSV sources")
  endif()

  _bsc_target_work_directory(_work "${TARGET}")
  get_target_property(_request "${TARGET}" BSC_COMPONENT_REQUEST)
  get_target_property(_request_target "${TARGET}" BSC_COMPONENT_REQUEST_TARGET)
  get_target_property(_package_target "${TARGET}" BSC_PACKAGE_TARGET)
  set(_topology "${_work}/topology.json")
  set(_cache "${_work}/scan-cache.json")
  set(_scan_dir "${_work}/scan")
  set(_bo_dir "${_work}/bo")
  set(_info_dir "${_work}/info")
  file(MAKE_DIRECTORY "${_work}")

  set(_dependency_requests "")
  set(_dependency_request_targets "")
  set(_dependency_bo_dirs "")
  set(_dependency_package_targets "")
  set(_provider_packages "")
  set(_provider_sources "")
  set(_provider_targets "")
  set(_provider_outputs "")
  foreach(_component IN LISTS _closure)
    _bsc_component_output_paths(
      "${_component}" _component_sources _component_packages _component_outputs)
    list(LENGTH _component_packages _component_count)
    if(_component_count GREATER 0)
      math(EXPR _component_last "${_component_count} - 1")
      foreach(_index RANGE 0 ${_component_last})
        list(GET _component_packages ${_index} _package)
        list(GET _component_sources ${_index} _source)
        list(GET _component_outputs ${_index} _output)
        list(FIND _provider_packages "${_package}" _provider_index)
        if(_provider_index GREATER -1)
          list(GET _provider_sources ${_provider_index} _previous_source)
          list(GET _provider_targets ${_provider_index} _previous_target)
          if(NOT "${_previous_target}" STREQUAL "${_component}")
            message(FATAL_ERROR
              "BluespecCMake: package '${_package}' has multiple providers in "
              "component '${TARGET}' closure: '${_previous_target}' "
              "('${_previous_source}') and '${_component}' ('${_source}')")
          endif()
        else()
          list(APPEND _provider_packages "${_package}")
          list(APPEND _provider_sources "${_source}")
          list(APPEND _provider_targets "${_component}")
          list(APPEND _provider_outputs "${_output}")
        endif()
      endforeach()
    endif()
    if(NOT "${_component}" STREQUAL "${TARGET}")
      get_target_property(_dependency_request
        "${_component}" BSC_COMPONENT_REQUEST)
      get_target_property(_dependency_request_target
        "${_component}" BSC_COMPONENT_REQUEST_TARGET)
      get_target_property(_dependency_package_target
        "${_component}" BSC_PACKAGE_TARGET)
      _bsc_target_work_directory(_dependency_work "${_component}")
      list(APPEND _dependency_requests "${_dependency_request}")
      list(APPEND _dependency_request_targets "${_dependency_request_target}")
      list(APPEND _dependency_bo_dirs "${_dependency_work}/bo")
      list(APPEND _dependency_package_targets "${_dependency_package_target}")
    endif()
  endforeach()
  list(REMOVE_DUPLICATES _dependency_requests)
  list(REMOVE_DUPLICATES _dependency_request_targets)
  list(REMOVE_DUPLICATES _dependency_bo_dirs)
  list(REMOVE_DUPLICATES _dependency_package_targets)

  if(NOT EXISTS "${_topology}")
    set(_init_command
      "${Python3_EXECUTABLE}" "${BSC_GRAPH_TOOL}" init
      --output "${_topology}")
    foreach(_source IN LISTS _sources)
      list(APPEND _init_command --source "${_source}")
    endforeach()
    execute_process(COMMAND ${_init_command} RESULT_VARIABLE _init_result)
    if(NOT _init_result EQUAL 0)
      message(FATAL_ERROR
        "BluespecCMake: failed to initialize component topology ${_topology}")
    endif()
  endif()

  file(READ "${_topology}" _topology_json)
  string(JSON _topology_count ERROR_VARIABLE _topology_error
    LENGTH "${_topology_json}" packages)
  if(_topology_error)
    message(FATAL_ERROR
      "BluespecCMake: invalid component topology '${_topology}': ${_topology_error}")
  endif()
  if(_topology_count GREATER 0)
    math(EXPR _topology_last "${_topology_count} - 1")
    foreach(_index RANGE 0 ${_topology_last})
      string(JSON _package GET "${_topology_json}" packages ${_index} name)
      string(JSON _import_count LENGTH "${_topology_json}" packages ${_index} imports)
      set(_imports "")
      if(_import_count GREATER 0)
        math(EXPR _last_import "${_import_count} - 1")
        foreach(_import_index RANGE 0 ${_last_import})
          string(JSON _import GET "${_topology_json}"
            packages ${_index} imports ${_import_index})
          list(APPEND _imports "${_import}")
        endforeach()
      endif()
      set(_component_imports_${_package} "${_imports}")
      string(JSON _input_count LENGTH "${_topology_json}" packages ${_index} inputs)
      set(_inputs "")
      if(_input_count GREATER 0)
        math(EXPR _last_input "${_input_count} - 1")
        foreach(_input_index RANGE 0 ${_last_input})
          string(JSON _input GET "${_topology_json}"
            packages ${_index} inputs ${_input_index})
          list(APPEND _inputs "${_input}")
        endforeach()
      endif()
      set(_component_inputs_${_package} "${_inputs}")
    endforeach()
  endif()

  set(_scan_command
    "${Python3_EXECUTABLE}" "${BSC_GRAPH_TOOL}" scan-component
    --request "${_request}"
    --output "${_topology}"
    --cache "${_cache}"
    --scan-dir "${_scan_dir}"
    --bsc "${BSC_BIN}"
    --bluetcl "${BLUETCL_BIN}")
  foreach(_dependency_request IN LISTS _dependency_requests)
    list(APPEND _scan_command --dependency-request "${_dependency_request}")
  endforeach()
  add_custom_command(
    OUTPUT "${_topology}"
    COMMAND ${_scan_command}
    # Only the component's own sources can change this component's direct
    # import topology.  Dependency components are represented by their
    # request producers; depending on every transitive source here would make
    # a change in a shared library invalidate every consumer's scanner and
    # would cause unnecessary configure-dependency checks.
    DEPENDS "${_request}" "${_request_target}"
      ${_dependency_requests} ${_dependency_request_targets}
      "${BSC_GRAPH_TOOL}" ${_sources}
    COMMENT "Scanning Bluespec component graph for ${TARGET}"
    VERBATIM)
  set(_topology_target "${TARGET}__bsc_topology")
  add_custom_target("${_topology_target}" DEPENDS "${_topology}")
  add_dependencies("${_package_target}" "${_topology_target}")
  if(_dependency_package_targets)
    add_dependencies("${_package_target}" ${_dependency_package_targets})
  endif()
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_topology}")

  list(LENGTH _packages _package_count)
  math(EXPR _package_last "${_package_count} - 1")
  foreach(_index RANGE 0 ${_package_last})
    list(GET _packages ${_index} _package)
    list(GET _sources ${_index} _source)
    list(GET _package_outputs ${_index} _bo)
    set(_depends
      "${_source}" "${_request}" "${_request_target}"
      ${_dependency_requests} ${_dependency_request_targets}
      "${BSC_GRAPH_TOOL}" "${BSC_BIN}")
    foreach(_import IN LISTS _component_imports_${_package})
      list(FIND _provider_packages "${_import}" _provider_index)
      if(_provider_index EQUAL -1)
        message(FATAL_ERROR
          "BluespecCMake: package '${_package}' imports '${_import}', but no "
          "provider exists in component '${TARGET}' build closure")
      endif()
      list(GET _provider_outputs ${_provider_index} _import_output)
      list(APPEND _depends "${_import_output}")
    endforeach()
    list(APPEND _depends ${_component_inputs_${_package}})
    set(_compile_command
      "${Python3_EXECUTABLE}" "${BSC_GRAPH_TOOL}" compile-component
      --request "${_request}"
      --source "${_source}"
      --output "${_bo}"
      --bo-dir "${_bo_dir}"
      --info-dir "${_info_dir}"
      --bsc "${BSC_BIN}")
    foreach(_dependency_request IN LISTS _dependency_requests)
      list(APPEND _compile_command --dependency-request "${_dependency_request}")
    endforeach()
    foreach(_dependency_bo_dir IN LISTS _dependency_bo_dirs)
      list(APPEND _compile_command --dependency-bo-dir "${_dependency_bo_dir}")
    endforeach()
    file(RELATIVE_PATH _display_bo "${CMAKE_BINARY_DIR}" "${_bo}")
    add_custom_command(
      OUTPUT "${_bo}"
      COMMAND ${_compile_command}
      DEPENDS ${_depends}
      JOB_POOL bsc_package
      COMMENT "Building Bluespec object ${_display_bo}"
      VERBATIM)
    set(_node_target "${TARGET}__bsc_bo_${_package}")
    add_custom_target("${_node_target}" DEPENDS "${_bo}")
    add_dependencies("${_node_target}" "${_topology_target}")
    add_dependencies("${_package_target}" "${_node_target}")
  endforeach()

  set_target_properties("${TARGET}" PROPERTIES
    BSC_BO_DIRECTORY "${_bo_dir}"
    BSC_PACKAGE_OUTPUTS "${_package_outputs}"
    BSC_TOPOLOGY "${_topology}")
  set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "${_topology}" "${_cache}" "${_scan_dir}" "${_bo_dir}" "${_info_dir}")
endfunction()

function(_bsc_finalize_endpoint TARGET)
  _bsc_refresh_endpoint_components("${TARGET}")
  _bsc_target_work_directory(_work "${TARGET}")
  get_target_property(_request "${TARGET}" BSC_REQUEST_FILE)
  get_target_property(_component_requests "${TARGET}" BSC_COMPONENT_REQUESTS)
  get_target_property(_component_request_targets
    "${TARGET}" BSC_COMPONENT_REQUEST_TARGETS)
  if(NOT _component_requests OR _component_requests MATCHES "-NOTFOUND$")
    set(_component_requests "")
  endif()
  if(NOT _component_request_targets OR
     _component_request_targets MATCHES "-NOTFOUND$")
    set(_component_request_targets "")
  endif()
  get_target_property(_backend "${TARGET}" BSC_ENDPOINT_BACKEND)
  get_target_property(_top "${TARGET}" BSC_ENDPOINT_TOP)
  get_target_property(_top_source "${TARGET}" BSC_ENDPOINT_SOURCE)
  set(_stamp "${_work}/.success")
  set(_depfile "${_work}/depfile.d")
  set(_artifact_dir "${_work}/artifacts")
  set(_topology "${_work}/topology.json")
  set(_cache "${_work}/scan-cache.json")
  set(_scan_dir "${_work}/scan")
  set(_bo_dir "${_work}/bo")
  set(_info_dir "${_work}/info")
  file(MAKE_DIRECTORY "${_work}")
  set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "${_topology}" "${_cache}" "${_scan_dir}" "${_bo_dir}" "${_info_dir}")

  set(_package_outputs "")
  set(_package_targets "")
  set(_package_bo_dirs "")
  get_target_property(_components "${TARGET}" BSC_COMPONENTS)
  if(NOT _components OR _components MATCHES "-NOTFOUND$")
    set(_components "")
  endif()
  foreach(_component IN LISTS _components)
    _bsc_component_output_paths(
      "${_component}" _sources _packages _outputs)
    get_target_property(_package_target "${_component}" BSC_PACKAGE_TARGET)
    _bsc_target_work_directory(_component_work "${_component}")
    list(APPEND _package_outputs ${_outputs})
    list(APPEND _package_targets "${_package_target}")
    list(APPEND _package_bo_dirs "${_component_work}/bo")
  endforeach()
  list(REMOVE_DUPLICATES _package_outputs)
  list(REMOVE_DUPLICATES _package_targets)
  list(REMOVE_DUPLICATES _package_bo_dirs)
  set(_endpoint_package_bo_args "")
  foreach(_package_bo_dir IN LISTS _package_bo_dirs)
    list(APPEND _endpoint_package_bo_args
      --package-bo-dir "${_package_bo_dir}")
  endforeach()
  if(_package_targets)
    add_dependencies("${TARGET}_artifact" ${_package_targets})
  endif()

  if(_backend STREQUAL "check")
    add_custom_command(
      OUTPUT "${_stamp}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${_artifact_dir}"
      COMMAND "${CMAKE_COMMAND}" -E touch "${_stamp}"
      DEPENDS "${_request}" ${_component_requests}
        ${_component_request_targets} ${_package_targets} ${_package_outputs}
      COMMENT "Checking Bluespec component closure for ${TARGET}"
      VERBATIM)
    set_target_properties("${TARGET}" PROPERTIES
      BSC_BO_DIRECTORIES "${_package_bo_dirs}"
      BSC_PACKAGE_OUTPUTS "${_package_outputs}")
    return()
  endif()

  if(NOT _top_source)
    message(FATAL_ERROR
      "BluespecCMake endpoint '${TARGET}' requires an explicit SOURCE")
  endif()
  if(NOT EXISTS "${_topology}")
    execute_process(
      COMMAND "${Python3_EXECUTABLE}" "${BSC_GRAPH_TOOL}" init
        --output "${_topology}" --source "${_top_source}"
      RESULT_VARIABLE _init_result)
    if(NOT _init_result EQUAL 0)
      message(FATAL_ERROR
        "BluespecCMake: failed to initialize endpoint topology ${_topology}")
    endif()
  endif()
  file(READ "${_topology}" _topology_json)
  string(JSON _topology_count ERROR_VARIABLE _topology_error
    LENGTH "${_topology_json}" packages)
  if(_topology_error)
    message(FATAL_ERROR
      "BluespecCMake: invalid endpoint topology '${_topology}': ${_topology_error}")
  endif()
  set(_topology_inputs "")
  if(_topology_count GREATER 0)
    math(EXPR _topology_last "${_topology_count} - 1")
    foreach(_index RANGE 0 ${_topology_last})
      string(JSON _input_count LENGTH "${_topology_json}" packages ${_index} inputs)
      if(_input_count GREATER 0)
        math(EXPR _last_input "${_input_count} - 1")
        foreach(_input_index RANGE 0 ${_last_input})
          string(JSON _input GET "${_topology_json}"
            packages ${_index} inputs ${_input_index})
          list(APPEND _topology_inputs "${_input}")
        endforeach()
      endif()
    endforeach()
  endif()
  list(REMOVE_DUPLICATES _topology_inputs)
  add_custom_command(
    OUTPUT "${_topology}"
    COMMAND "${Python3_EXECUTABLE}" "${BSC_GRAPH_TOOL}" scan-endpoint
      --request "${_request}"
      --output "${_topology}"
      --cache "${_cache}"
      --scan-dir "${_scan_dir}"
    DEPENDS "${_request}" ${_component_requests}
      ${_component_request_targets} ${_package_targets}
      "${BSC_GRAPH_TOOL}" "${_top_source}" ${_topology_inputs}
    COMMENT "Scanning Bluespec endpoint graph for ${TARGET}"
    VERBATIM)

  set(_byproducts "")
  if(_backend STREQUAL "bluesim")
    list(APPEND _byproducts
      "${_artifact_dir}/${TARGET}"
      "${_artifact_dir}/${TARGET}.so")
  elseif(_backend STREQUAL "verilog")
    list(APPEND _byproducts
      "${_artifact_dir}/${_top}.v"
      "${_artifact_dir}/${TARGET}.f")
  elseif(_backend STREQUAL "systemc")
    list(APPEND _byproducts "${_artifact_dir}/lib${TARGET}.a")
  endif()
  add_custom_command(
    OUTPUT "${_stamp}"
    COMMAND "${Python3_EXECUTABLE}" "${BLUESPEC_CMAKE_DRIVER}" build
      --request "${_request}"
      --stamp "${_stamp}"
      --depfile "${_depfile}"
      --artifact-dir "${_artifact_dir}"
      --bo-dir "${_bo_dir}"
      --topology "${_topology}"
      ${_endpoint_package_bo_args}
    DEPENDS
      "${_request}"
      "${BLUESPEC_CMAKE_DRIVER}"
      "${BSC_GRAPH_TOOL}"
      "${_topology}"
      "${_top_source}"
      ${_component_requests}
      ${_component_request_targets}
      ${_package_targets}
      ${_package_outputs}
    BYPRODUCTS ${_byproducts}
    DEPFILE "${_depfile}"
    COMMENT "Building Bluespec ${_backend} endpoint ${TARGET}"
    VERBATIM)
  set_target_properties("${TARGET}" PROPERTIES
    BSC_TOPOLOGY "${_topology}"
    BSC_BO_DIRECTORIES "${_package_bo_dirs}"
    BSC_PACKAGE_OUTPUTS "${_package_outputs}")
endfunction()

function(_bsc_finalize)
  # A deferred call executes in the directory requested above, so its binary
  # directory is the endpoint directory that owns the custom-command outputs.
  set(_binary_directory "${CMAKE_CURRENT_BINARY_DIR}")
  get_property(_components GLOBAL PROPERTY BSC_COMPONENT_TARGETS)
  foreach(_component IN LISTS _components)
    get_target_property(_component_directory
      "${_component}" BSC_BINARY_DIRECTORY)
    if("${_component_directory}" STREQUAL "${_binary_directory}")
      _bsc_finalize_component("${_component}")
    endif()
  endforeach()
  get_property(_endpoints GLOBAL PROPERTY BSC_ENDPOINTS)
  foreach(_endpoint IN LISTS _endpoints)
    get_target_property(_endpoint_directory
      "${_endpoint}" BSC_BINARY_DIRECTORY)
    if("${_endpoint_directory}" STREQUAL "${_binary_directory}")
      _bsc_finalize_endpoint("${_endpoint}")
    endif()
  endforeach()
endfunction()

function(bsc_add_check TARGET)
  cmake_parse_arguments(ARG "" "" "LIBRARIES" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "bsc_add_check(${TARGET}): use LIBRARIES keyword")
  endif()
  _bsc_add_endpoint_common("${TARGET}" check "" "")
  if(ARG_LIBRARIES)
    bsc_target_link_libraries("${TARGET}" PRIVATE ${ARG_LIBRARIES})
  endif()
endfunction()

function(bsc_add_bluesim_executable TARGET)
  cmake_parse_arguments(ARG "EXCLUDE_FROM_ALL" "TOP;SOURCE" "" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "bsc_add_bluesim_executable(${TARGET}): use TOP and SOURCE keywords")
  endif()
  if(NOT ARG_TOP OR NOT ARG_SOURCE)
    message(FATAL_ERROR "bsc_add_bluesim_executable(${TARGET}) requires TOP and SOURCE")
  endif()
  get_filename_component(_source "${ARG_SOURCE}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
  _bsc_add_endpoint_common("${TARGET}" bluesim "${ARG_TOP}" "${_source}")
  _bsc_target_work_directory(_work "${TARGET}")
  set(_artifact_dir "${_work}/artifacts")
  set_target_properties("${TARGET}" PROPERTIES
    BSC_EXECUTABLE "${_artifact_dir}/${TARGET}"
    BSC_SHARED_LIBRARY "${_artifact_dir}/${TARGET}.so")
  if(ARG_EXCLUDE_FROM_ALL)
    set_property(TARGET "${TARGET}_artifact" PROPERTY EXCLUDE_FROM_ALL TRUE)
  endif()
endfunction()

function(bsc_add_verilog TARGET)
  cmake_parse_arguments(ARG "EXCLUDE_FROM_ALL;REQUIRE_TRANSLATE_OFF_MATCH" "TOP;SOURCE;TRANSLATE_OFF_MATCH_REGEX" "" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "bsc_add_verilog(${TARGET}): use TOP, SOURCE, and translation keywords")
  endif()
  if(NOT ARG_TOP OR NOT ARG_SOURCE)
    message(FATAL_ERROR "bsc_add_verilog(${TARGET}) requires TOP and SOURCE")
  endif()
  get_filename_component(_source "${ARG_SOURCE}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
  _bsc_add_endpoint_common("${TARGET}" verilog "${ARG_TOP}" "${_source}")
  _bsc_target_work_directory(_work "${TARGET}")
  set(_artifact_dir "${_work}/artifacts")
  set_target_properties("${TARGET}" PROPERTIES
    BSC_PRIMARY_VERILOG "${_artifact_dir}/${ARG_TOP}.v"
    BSC_VERILOG_DIRECTORY "${_artifact_dir}/rtl"
    BSC_VERILOG_FILELIST "${_artifact_dir}/${TARGET}.f"
    BSC_TRANSLATE_OFF_REGEX "${ARG_TRANSLATE_OFF_MATCH_REGEX}"
    BSC_REQUIRE_TRANSLATE_OFF_MATCH "${ARG_REQUIRE_TRANSLATE_OFF_MATCH}")
  if(ARG_EXCLUDE_FROM_ALL)
    set_property(TARGET "${TARGET}_artifact" PROPERTY EXCLUDE_FROM_ALL TRUE)
  endif()
endfunction()

function(bsc_add_systemc_library TARGET)
  cmake_parse_arguments(ARG "EXCLUDE_FROM_ALL" "TOP;SOURCE" "" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "bsc_add_systemc_library(${TARGET}): use TOP and SOURCE keywords")
  endif()
  if(NOT ARG_TOP OR NOT ARG_SOURCE)
    message(FATAL_ERROR "bsc_add_systemc_library(${TARGET}) requires TOP and SOURCE")
  endif()
  if(NOT TARGET SystemC::systemc)
    message(FATAL_ERROR
      "bsc_add_systemc_library(${TARGET}) requires a SystemC::systemc target. "
      "Enable SystemC or call find_package(SystemCLanguage CONFIG REQUIRED) first.")
  endif()
  get_filename_component(_source "${ARG_SOURCE}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
  _bsc_add_endpoint_common("${TARGET}" systemc "${ARG_TOP}" "${_source}" STATIC)
  _bsc_target_work_directory(_work "${TARGET}")
  set(_artifact_dir "${_work}/artifacts")
  file(MAKE_DIRECTORY "${_artifact_dir}")
  set_target_properties("${TARGET}" PROPERTIES
    IMPORTED_LOCATION "${_artifact_dir}/lib${TARGET}.a"
    BSC_SYSTEMC_ARCHIVE "${_artifact_dir}/lib${TARGET}.a"
    BSC_SYSTEMC_HEADER "${_artifact_dir}/${ARG_TOP}_systemc.h"
    BSC_SYSTEMC_INCLUDE_DIRECTORY "${_artifact_dir}")
  if(TARGET SystemC::systemc)
    # BSC invokes the host C++ compiler for SystemC-generated objects. Pass
    # SystemC's public include directories to that invocation as an endpoint
    # implementation detail rather than exposing them as user flags.
    get_target_property(_systemc_includes SystemC::systemc
      INTERFACE_INCLUDE_DIRECTORIES)
    if(_systemc_includes AND NOT _systemc_includes MATCHES "-NOTFOUND$")
      foreach(_systemc_include IN LISTS _systemc_includes)
        if(_systemc_include MATCHES "^\\$<BUILD_INTERFACE:(.*)>$")
          set(_systemc_include "${CMAKE_MATCH_1}")
        elseif(_systemc_include MATCHES "^\\$<INSTALL_INTERFACE:")
          continue()
        elseif(_systemc_include MATCHES "^\\$<")
          message(FATAL_ERROR
            "BluespecCMake: SystemC::systemc has a generator-expression "
            "include directory; use a concrete SystemC target for the "
            "SystemC endpoint.")
        endif()
        _bsc_append_target_property("${TARGET}__bsc_self" BSC_LINK_OPTIONS
          "-Xc++" "-I${_systemc_include}")
      endforeach()
    endif()
    set_property(TARGET "${TARGET}" APPEND PROPERTY
      INTERFACE_LINK_LIBRARIES SystemC::systemc Bluespec::bskernel Bluespec::bsprim)
    set_property(TARGET "${TARGET}" APPEND PROPERTY
      INTERFACE_INCLUDE_DIRECTORIES "${_artifact_dir}")
  endif()
  if(ARG_EXCLUDE_FROM_ALL)
    set_property(TARGET "${TARGET}_artifact" PROPERTY EXCLUDE_FROM_ALL TRUE)
  endif()
endfunction()

function(bsc_add_waveform TARGET)
  cmake_parse_arguments(ARG "" "SIM_TARGET" "SIM_FLAGS" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "bsc_add_waveform(${TARGET}): use SIM_TARGET and SIM_FLAGS keywords")
  endif()
  if(NOT ARG_SIM_TARGET)
    message(FATAL_ERROR "bsc_add_waveform(${TARGET}) requires SIM_TARGET")
  endif()
  _bsc_require_bsc_target("${ARG_SIM_TARGET}")
  get_target_property(_sim "${ARG_SIM_TARGET}" BSC_EXECUTABLE)
  if(NOT _sim)
    message(FATAL_ERROR "bsc_add_waveform: '${ARG_SIM_TARGET}' is not a Bluesim endpoint")
  endif()
  set(_work "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${TARGET}.dir")
  set(_waveform "${_work}/artifacts/${TARGET}.vcd")
  add_custom_command(
    OUTPUT "${_waveform}"
    COMMAND "${_sim}" -V "${_waveform}" ${ARG_SIM_FLAGS}
    DEPENDS "${ARG_SIM_TARGET}"
    VERBATIM)
  add_custom_target("${TARGET}" ALL DEPENDS "${_waveform}")
  set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${_work}")
endfunction()
