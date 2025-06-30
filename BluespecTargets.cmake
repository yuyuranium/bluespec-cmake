cmake_minimum_required(VERSION 3.22)

if(__add_bluespec)
  return()
endif()
set(__add_bluespec ON)

include(BluespecUtils)

include(BluespecLibrary)
include(BluesimExecutable)
include(BluespecVerilogGeneration)
include(BluesimSystemC)
include(BluesimWaveform)
include(BluespecPaths)
