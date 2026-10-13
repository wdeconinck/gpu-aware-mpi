# AGENTS.md

## Project Context
- **Languages:** Fortran (Modern) • C++ (C++17/C++20)
- **Accelerators:** OpenMP (Target offloading) • OpenACC • CUDA C++
- **Interoperability:** GPU-aware MPI across all paradigms
- **Orchestrator:** Slurm
- **Build System:** CMake

## Environment Setup
The repository is tested with two specific NVIDIA HPC SDK versions. You must source **one** of these environment files before configuring or building the project:

```bash
# Option 1: NVIDIA 24.5 Environment
source arch/ecmwf/hpc2020/nvidia/24.5/env.sh

# Option 2: NVIDIA 26.1 Environment
source arch/ecmwf/hpc2020/nvidia/26.1/env.sh
```

These environment scripts are specific to ECMWF HPC2020 and its module system.
Source them from the repository root. Benchmark sources live in `src/`.

## Compilation Instructions
To prevent cache corruption between compiler versions, **always use an isolated, environment-specific build directory**.

### Build Variant 1: NVIDIA 24.5
```bash
source arch/ecmwf/hpc2020/nvidia/24.5/env.sh
cmake -S . -B build-nvidia-24.5
cmake --build build-nvidia-24.5
```

### Build Variant 2: NVIDIA 26.1
```bash
source arch/ecmwf/hpc2020/nvidia/26.1/env.sh
cmake -S . -B build-nvidia-26.1
cmake --build build-nvidia-26.1
```

## Execution Instructions
Navigate to the active environment's build directory and execute using Slurm's `srun` with the exact allocation parameters required for multi-node, multi-GPU evaluation:

### Running C++ with CUDA
```bash
srun --nodes=2 --tasks-per-node=4 --cpus-per-task=64 --gpus-per-task=1 ./roundtrip_cpp_cuda
```

### Running Fortran with OpenACC
```bash
srun --nodes=2 --tasks-per-node=4 --cpus-per-task=64 --gpus-per-task=1 ./roundtrip_fort_acc
```

### Running Fortran with OpenMP
```bash
srun --nodes=2 --tasks-per-node=4 --cpus-per-task=64 --gpus-per-task=1 ./roundtrip_fort_omp
```

## Testing

On ECMWF HPC2020, build all three executables first, then run tests from the
repository root. Source the environment matching the build directory and launch
a single CTest process through `salloc`:

### NVIDIA 26.1
```bash
source arch/ecmwf/hpc2020/nvidia/26.1/env.sh && \
salloc -q dg --nodes=1 --gpus-per-task=1 --tasks-per-node=4 --cpus-per-task=1 \
ctest --test-dir build-nvidia-26.1 -VV
```

### NVIDIA 24.5
```bash
source arch/ecmwf/hpc2020/nvidia/24.5/env.sh && \
salloc -q dg --nodes=1 --gpus-per-task=1 --tasks-per-node=4 --cpus-per-task=1 \
ctest --test-dir build-nvidia-24.5 -VV
```

`--test-dir` selects the generated tests when running from the repository root;
it can be omitted if already inside the matching build directory. `salloc`
waits for resources, runs CTest once, and releases the allocation afterward.
Do not launch CTest with `srun`, which would start one CTest process per task.

At test execution time, the launcher
checks `SLURM_JOB_ID`. Inside an allocation it uses plain `srun <executable>`.
Otherwise it uses `srun -q dg --nodes=1 --tasks-per-node=4 --cpus-per-task=64
--gpus-per-task=1 <executable>` to request resources.

CTest integration tests are enabled by default (`BUILD_TESTING=ON`).
The test process must inherit any preallocated resources and the matching
NVIDIA/MPI environment. A terminal allocation is not automatically inherited
by an already-running VS Code extension process. Each test
runs serially and times out after 300 seconds, including allocation or job-step
waits. These tests require GPUs and GPU-aware MPI; do not run them as CPU-only
tests. Use `-DBUILD_TESTING=OFF` to configure without tests or a Slurm launcher.

## Quality Gates & Constraints

### 1. Fortran Parallelism (OpenMP & OpenACC)
- **OpenMP Mapping:** Use OpenMP 5.0+ syntax. **Do not** use `use_device_ptr`; always use `use_device_addr` when preparing device pointers for MPI routines in `roundtrip-fort-omp`.
- **OpenACC Mapping:** When passing OpenACC-managed variables to MPI routines in `roundtrip-fort-acc`, wrap the call inside an `!$acc host_data use_device(...)` block.

### 2. C++ & CUDA Interoperability
- **CUDA Compilation:** Ensure `nvcc` or `nvc++` handles `.cu` files correctly via CMake's native `enable_language(CUDA)` support for `roundtrip-cpp-cuda`.
- **Data Sharing:** When passing data between Fortran and C++, ensure device pointers match down to the raw Virtual Address Space. Use Fortran's `ISO_C_BINDING` for all inter-language API boundaries.

### 3. Build Tooling
- **Clean Builds:** Never run `cmake ..` directly in the project root. 
- **Compiler Consistency:** Ensure CMake automatically hooks the active `nvfortran` and `nvc++` exported by your sourced `.sh` environment files.


