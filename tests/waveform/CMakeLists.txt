cmake_minimum_required(VERSION 3.30)
project(RegressionWaveform LANGUAGES NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../../BluespecCMake.cmake")

bsc_add_bluesim_executable(sim TOP mkWaveTb SOURCE bsv/WaveTb.bsv)

bsc_add_waveform(wave SIM_TARGET sim SIM_FLAGS -m 100)
