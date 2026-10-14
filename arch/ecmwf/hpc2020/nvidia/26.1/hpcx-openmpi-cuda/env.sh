# SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
# SPDX-License-Identifier: Apache-2.0

module is-loaded prgenv/nvidia || module load prgenv/nvidia
module load nvidia/26.1

# The hpcx-openmpi module with cuda support
module load hpcx-openmpi/2.21.3-cuda

# Match the CUDA Host compiler to the gcc toolchain used by nvc++, respecting any possible localrc file read by nvc++ (check `nvc++ -dryrun`)
GCC_TOOLCHAIN=$(echo | nvc++ -v -E -x c++ - 2>&1 | grep -oE -e '--sys_include /[^ ]+/lib/gcc/[^ ]+' | head -n 1 | awk '{print $2}' | sed 's|/lib/gcc/.*||')
export CUDAHOSTCXX=$GCC_TOOLCHAIN/bin/g++

# Set the CUDA architecture for A100
export CUDAARCHS=80

