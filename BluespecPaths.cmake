cmake_minimum_required(VERSION 3.22)

include_guard(GLOBAL)

include(BluespecUtils)

# Function: bsc_bdir_path
#   Obtain a list of bdir for all bluespec targets.
#
# Usage:
#   bsc_bdir_path(<BSC_BDIR_VAR>)
#
# Arguments:
#   BSC_BDIR_VAR - (Output) Variable to store the list of bdir paths.
function(bsc_bdir_path BSC_BDIR)
  set(${BSC_BDIR} ${_BSC_BDIR} PARENT_SCOPE)
endfunction()
