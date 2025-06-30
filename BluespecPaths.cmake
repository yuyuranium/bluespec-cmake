cmake_minimum_required(VERSION 3.22)

if(_BLUESPEC_LIBRARY)
  return()
endif()
set(_BLUESPEC_LIBRARY)

include(BluespecUtils)

# Function: bsc_bdir_path
#   Obtain a list of bdir for all bluespec targets.
#
# Arguments:
#   BSC_BDIR - (Output) a list of bdir for all bluespec targets.
function(bsc_bdir_path BSC_BDIR)
  set(${BSC_BDIR} ${_BSC_BDIR} PARENT_SCOPE)
endfunction()
