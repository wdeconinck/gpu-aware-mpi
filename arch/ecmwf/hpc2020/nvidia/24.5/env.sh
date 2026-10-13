# SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
# SPDX-License-Identifier: Apache-2.0

module is-loaded prgenv/nvidia || module load prgenv/nvidia
module load nvidia/24.5
module load hpcx-openmpi
export CUDAARCHS=80  # for A100

GCC_TOOLCHAIN=$(echo "" | nvc++ -v -E -x c++ - 2>&1 | grep -oE '/usr/local/apps/gcc/[^/]+' | head -n 1)
export CUDAHOSTCXX=$GCC_TOOLCHAIN/bin/g++
