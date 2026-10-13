# SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.22)
project(gpu-aware-mpi LANGUAGES C CXX CUDA Fortran)

include(CTest)

# 1. Enforce C++ and CUDA standards
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)
if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES 80 CACHE STRING "Target GPU Architecture")
endif()

# 2. Find MPI (Requesting both CXX and Fortran components)
set(MPI_DEBUG ON)
find_package(MPI REQUIRED COMPONENTS CXX Fortran)

# 3. Find OpenACC (Usually provided by the Fortran compiler, e.g., NVHPC)
find_package(OpenACC REQUIRED COMPONENTS Fortran)

#4. Find CUDAToolkit
find_package(CUDAToolkit REQUIRED)

set(introspect_cuda_compiler_default OFF)
if(NOT CMAKE_CUDA_HOST_COMPILER)
    set(introspect_cuda_compiler_default ON)
endif()
option(INTROSPECT_CUDA_COMPILER "Inspect NVCC host compiler commands during configuration" ${introspect_cuda_compiler_default})
message(STATUS "CUDA compiler introspection: INTROSPECT_CUDA_COMPILER=${INTROSPECT_CUDA_COMPILER}")
message(STATUS "Use -DINTROSPECT_CUDA_COMPILER=ON to print the introspected host compiler path and NVCC commands; use -DINTROSPECT_CUDA_COMPILER=OFF to disable. Default is ON when CMAKE_CUDA_HOST_COMPILER is empty, otherwise OFF; cached choices are preserved.")

function(introspect_cuda_host_compiler output_variable)
    set(CUDA_COMPILER "${CMAKE_CUDA_COMPILER}")
    set(CUDA_HOST_COMPILER "${CMAKE_CUDA_HOST_COMPILER}")
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ShowCudaHostCompiler.cmake")
    set(${output_variable} "${INTROSPECTED_CUDA_HOST_COMPILER}" PARENT_SCOPE)
endfunction()

introspect_cuda_host_compiler(introspected_cuda_host_compiler)
set(cuda_host_compiler_summary "${CMAKE_CUDA_HOST_COMPILER}")
if(NOT cuda_host_compiler_summary)
    if(introspected_cuda_host_compiler)
        set(cuda_host_compiler_summary "${introspected_cuda_host_compiler} (introspected from NVCC)")
    else()
        set(cuda_host_compiler_summary "Unknown (NVCC default; introspection disabled or unsuccessful)")
    endif()
endif()

# ==========================================
# Target 1: C++ + CUDA GPU-Aware MPI
# ==========================================
add_executable(roundtrip_cpp_cuda src/roundtrip_cuda.cu)

# Link MPI and CUDA runtime libraries
target_link_libraries(roundtrip_cpp_cuda
    PRIVATE 
        MPI::MPI_CXX
        CUDA::cudart
)

# Tell CMake to compile this file using the CUDA compiler if it contains CUDA syntax
#set_source_files_properties(ping_pong.cpp PROPERTIES LANGUAGE CUDA)

# ==========================================
# Target 2: Fortran + OpenACC GPU-Aware MPI
# ==========================================
add_executable(roundtrip_fort_acc src/roundtrip_acc.F90)

# Link MPI and OpenACC libraries
target_link_libraries(roundtrip_fort_acc
    PRIVATE 
        MPI::MPI_Fortran
        OpenACC::OpenACC_Fortran
)

# If using NVIDIA HPC SDK, explicitly pass the GPU target flag to Fortran compiler
if(CMAKE_Fortran_COMPILER_ID STREQUAL "NVHPC")
    target_compile_options(roundtrip_fort_acc PRIVATE -gpu=cc${CMAKE_CUDA_ARCHITECTURES})
    target_link_options(roundtrip_fort_acc PRIVATE -gpu=cc${CMAKE_CUDA_ARCHITECTURES})
endif()


# ==========================================
# Target 3: Fortran + OpenMP Offload GPU-Aware MPI
# ==========================================
find_package(OpenMP REQUIRED COMPONENTS Fortran)

add_executable(roundtrip_fort_omp src/roundtrip_omp.F90)

# Link MPI and the native OpenMP target libraries
target_link_libraries(roundtrip_fort_omp
    PRIVATE
        MPI::MPI_Fortran
        OpenMP::OpenMP_Fortran
)

# Handle NVHPC hardware target mapping specifically for OpenMP Offload
if(CMAKE_Fortran_COMPILER_ID STREQUAL "NVHPC")
    # -mp=gpu enables OpenMP target offloading to NVIDIA GPUs
    # -gpu=ccXX ensures it matches your exact hardware compute capability
    target_compile_options(roundtrip_fort_omp PRIVATE -mp=gpu -gpu=cc${CMAKE_CUDA_ARCHITECTURES})
    target_link_options(roundtrip_fort_omp PRIVATE -mp=gpu -gpu=cc${CMAKE_CUDA_ARCHITECTURES})
endif()

if(BUILD_TESTING)
    find_program(SLURM_SRUN_EXECUTABLE NAMES srun REQUIRED)
    foreach(benchmark IN ITEMS roundtrip_cpp_cuda roundtrip_fort_acc roundtrip_fort_omp)
        add_test(NAME ${benchmark}
            COMMAND ${CMAKE_COMMAND}
                "-DSRUN_EXECUTABLE=${SLURM_SRUN_EXECUTABLE}"
                "-DBENCHMARK_EXECUTABLE=$<TARGET_FILE:${benchmark}>"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSlurmTest.cmake"
        )
        set_tests_properties(${benchmark} PROPERTIES
            LABELS "gpu;mpi;slurm"
            RUN_SERIAL TRUE
            TIMEOUT 300
            ENVIRONMENT "OMP_TARGET_OFFLOAD=MANDATORY"
        )
    endforeach()
endif()

message(STATUS "C Compiler: ${CMAKE_C_COMPILER}")
message(STATUS "C++ Compiler: ${CMAKE_CXX_COMPILER}")
message(STATUS "Fortran Compiler: ${CMAKE_Fortran_COMPILER}")
message(STATUS "CUDA Compiler: ${CMAKE_CUDA_COMPILER}")
message(STATUS "CUDA Host Compiler: ${cuda_host_compiler_summary}")
message(STATUS "MPI libraries: ${MPI_CXX_LIBRARIES}")
