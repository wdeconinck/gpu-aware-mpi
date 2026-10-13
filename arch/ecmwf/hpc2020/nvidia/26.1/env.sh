# SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
# SPDX-License-Identifier: Apache-2.0

module is-loaded prgenv/nvidia || module load prgenv/nvidia
module load nvidia/26.1

# Match the CUDA Host compiler to the gcc toolchain used by nvc++
GCC_TOOLCHAIN=$(echo "" | nvc++ -v -E -x c++ - 2>&1 | grep -oE '/usr/local/apps/gcc/[^/]+' | head -n 1)
export CUDAHOSTCXX=$GCC_TOOLCHAIN/bin/g++

# Set the CUDA architecture for A100
export CUDAARCHS=80 

# The hpcx-openmpi module is not compiled with cuda support
#module load hpcx-openmpi

# But the hpcx bundled within NVHPC_ROOT works
HPCX_MODULES=$(find $NVHPC_ROOT/comm_libs -type d -name "modulefiles")
module use "$HPCX_MODULES"
module load hpcx-ompi


