# SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
# SPDX-License-Identifier: Apache-2.0

module is-loaded prgenv/nvidia || module load prgenv/nvidia
module load nvidia/24.5
module load hpcx-openmpi

export CUDAARCHS=80  # for A100

# Match the CUDA Host compiler to the gcc toolchain used by nvc++, respecting any possible localrc file read by nvc++ (check `nvc++ -dryrun`)
GCC_TOOLCHAIN=$(echo | nvc++ -v -E -x c++ - 2>&1 | grep -oE -e '--sys_include /[^ ]+/lib/gcc/[^ ]+' | head -n 1 | awk '{print $2}' | sed 's|/lib/gcc/.*||')
export CUDAHOSTCXX=$GCC_TOOLCHAIN/bin/g++
