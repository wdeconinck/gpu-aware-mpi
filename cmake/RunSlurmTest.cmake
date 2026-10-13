# SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
# SPDX-License-Identifier: Apache-2.0

if(NOT DEFINED SRUN_EXECUTABLE OR NOT DEFINED BENCHMARK_EXECUTABLE)
    message(FATAL_ERROR "SRUN_EXECUTABLE and BENCHMARK_EXECUTABLE are required")
endif()

set(slurm_arguments)
if("$ENV{SLURM_JOB_ID}" STREQUAL "")
    list(APPEND slurm_arguments
        -q dg --nodes=1 --tasks-per-node=4 --cpus-per-task=64 --gpus-per-task=1
    )
endif()

execute_process(
    COMMAND "${SRUN_EXECUTABLE}" ${slurm_arguments} "${BENCHMARK_EXECUTABLE}"
    COMMAND_ECHO STDOUT
    RESULT_VARIABLE test_result
)
if(NOT "${test_result}" STREQUAL "0")
    message(FATAL_ERROR "Slurm benchmark failed: ${test_result}")
endif()