# Multi-Paradigm GPU-Aware MPI Roundtrip Benchmarks

This repository contains micro-benchmarks designed to evaluate and profile **GPU-aware MPI roundtrip performance** across multiple modern accelerated computing paradigms. 

By utilizing direct GPU-to-GPU communication via MPI, these benchmarks bypass staging data through host (CPU) memory, maximizing throughput and minimizing latency on distributed GPU clusters.

## Quick Start

On ECMWF HPC2020, quickly configure, compile, and test the project using the NVIDIA 26.1 workflow:

```bash
./scripts/workflow.sh --preset nvidia-26.1
```

## Supported Paradigms & Executables

The project compiles into three separate executable binaries, allowing direct comparison of programming models using the exact same hardware allocation:

1. **`roundtrip_cpp_cuda`**: C++ implementation utilizing native CUDA kernels and CUDA streams.
2. **`roundtrip_fort_acc`**: Fortran implementation utilizing OpenACC directives (`!$acc parallel loop`, `!$acc host_data`).
3. **`roundtrip_fort_omp`**: Fortran implementation utilizing modern OpenMP target offloading (`!$omp target`, `!$omp target data`).

## Repository Layout

```text
.
|-- CMakeLists.txt                      # Build configuration for all three benchmarks
|-- CMakePresets.json                   # Configure, build, and test presets
|-- README.md
|-- AGENTS.md                           # Contributor and coding-agent guidance
|-- cmake/
|   |-- RunSlurmTest.cmake              # Allocation-aware CTest launcher
|   `-- ShowCudaHostCompiler.cmake      # Configure-time CUDA host compiler introspection
|-- arch/
|   `-- ecmwf/hpc2020/nvidia/           # Cluster-specific NVIDIA HPC SDK setup
|       |-- 24.5/env.sh
|       `-- 26.1/env.sh
|-- scripts/
|   |-- configure.sh                   # Configure with a required --preset
|   |-- build.sh                       # Build with a required --preset
|   |-- test.sh                        # Test with a required --preset
|   |-- workflow.sh                    # Configure, build, and test in sequence
|   `-- run-preset.sh                  # Shared environment and preset helper
`-- src/
	|-- roundtrip_cuda.cu              # C++ / CUDA benchmark
	|-- roundtrip_acc.F90              # Fortran / OpenACC benchmark
	`-- roundtrip_omp.F90              # Fortran / OpenMP benchmark
```

Benchmark sources live in `src/`. Environment scripts are grouped by organisation,
cluster, compiler, and version under `arch/`. Build directories are local,
generated artifacts and are excluded from version control by `.gitignore`.

---

## Prerequisites & Environment

The code relies on the **NVIDIA HPC SDK** and a **GPU-aware MPI implementation** (e.g., OpenMPI built with UCX and CUDA support). 

The supplied environment scripts are specific to **ECMWF HPC2020** and its
module system. On that cluster, you **must source one of these files** from the
repository root before compiling or running tests:

* **NVIDIA HPC SDK 24.5:** `source arch/ecmwf/hpc2020/nvidia/24.5/env.sh`
* **NVIDIA HPC SDK 26.1:** `source arch/ecmwf/hpc2020/nvidia/26.1/env.sh`

On other clusters, load an equivalent compiler, CUDA, and GPU-aware MPI stack;
these scripts are not portable environment installers.

---

## Build System (CMake)

The project uses CMake to safely map languages, compilers, and accelerator flags. To keep compiler objects isolated between the two supported SDK versions, **always build within an environment-specific directory**.

### Building for NVIDIA 24.5
```bash
source arch/ecmwf/hpc2020/nvidia/24.5/env.sh
cmake -S . -B build-nvidia-24.5
cmake --build build-nvidia-24.5
```

### Building for NVIDIA 26.1
```bash
source arch/ecmwf/hpc2020/nvidia/26.1/env.sh
cmake -S . -B build-nvidia-26.1
cmake --build build-nvidia-26.1
```

---

## Cluster Execution (Slurm)

To run the benchmarks across multiple nodes and leverage GPU-aware MPI, use Slurm's `srun` orchestrator. Ensure your target environment remains sourced so runtime libraries match your compiled binary.

Navigate to your active build directory and execute your choice of paradigm:

```bash
# Example using the 26.1 build directory
cd build-nvidia-26.1

# 1. Run C++ CUDA Benchmark
srun --nodes=2 --tasks-per-node=4 --cpus-per-task=64 --gpus-per-task=1 ./roundtrip_cpp_cuda

# 2. Run Fortran OpenACC Benchmark
srun --nodes=2 --tasks-per-node=4 --cpus-per-task=64 --gpus-per-task=1 ./roundtrip_fort_acc

# 3. Run Fortran OpenMP Benchmark
srun --nodes=2 --tasks-per-node=4 --cpus-per-task=64 --gpus-per-task=1 ./roundtrip_fort_omp
```

### Slurm Parameter Breakdown
* `--nodes=2`: Spans the job across 2 discrete cluster nodes.
* `--tasks-per-node=4`: Spawns 4 MPI ranks per node (8 total ranks).
* `--gpus-per-task=1`: Allocates exactly 1 GPU per MPI rank (maps perfectly to multi-GPU nodes).
* `--cpus-per-task=64`: Reserves hardware threads per rank for efficient CPU-side compute or asynchronous transfers.

---

## Testing (CTest)

### Preset Workflow

`CMakePresets.json` provides `nvidia-24.5` and `nvidia-26.1` configure, build,
test, and workflow presets, each selecting its matching `build-nvidia-*` directory.
Test presets enable extra-verbose output (`-VV`), run serially, and fail if no
tests are discovered. The preset schema requires CMake 3.25 or newer.

Native presets cannot source shell scripts or invoke `salloc` around CTest.
Use the scripts under `scripts/` with a required `--preset` argument to load the full compiler/MPI environment
and select allocation defaults from vendor metadata (requires `jq`):

```bash
./scripts/configure.sh --preset nvidia-26.1
./scripts/build.sh --preset nvidia-26.1 -j 3
./scripts/test.sh --preset nvidia-26.1
```

Replace `nvidia-26.1` with `nvidia-24.5` for the other supported stack. Extra
arguments are forwarded to CMake or CTest, for example `-R roundtrip_cpp_cuda`
after the preset name. Configure and build before testing. All four scripts
delegate to `scripts/run-preset.sh` and can be invoked from any working directory.

To configure, build, and test in one command:

```bash
./scripts/workflow.sh --preset nvidia-26.1
```

The workflow stops if any step fails. The wrapper loads the matching environment
and reuses an existing Slurm allocation or requests one for the entire workflow
using the same-name test preset's `sallocArguments`. This reserves resources
during configure and build as well as testing. Additional arguments are forwarded
to `cmake --workflow`, not to individual steps; set build parallelism in the build
preset or through `CMAKE_BUILD_PARALLEL_LEVEL`, and test filters in the test preset.
Native `cmake --workflow --preset nvidia-26.1` requires an already-loaded
environment and does not interpret the custom allocation metadata.

The helper reads `vendor["ecmwf.int/gpu-aware-mpi/1.0"]` in
`CMakePresets.json`. Configure presets specify `environmentFile`; concrete test
presets specify an optional `sallocArguments` array. For example, a test preset
can contain:

```json
"vendor": {
    "ecmwf.int/gpu-aware-mpi/1.0": {
        "sallocArguments": ["-q", "dg", "--nodes=1", "--gpus-per-task=1", "--tasks-per-node=4", "--cpus-per-task=1"]
    }
}
```

Environment-file paths are relative to the repository root, or can be absolute.
Environment scripts only load the software stack; they no longer define preset
names or allocation defaults. Omit `sallocArguments` to run CTest directly;
an empty array uses `salloc` with no default arguments. The helper reads metadata
directly from concrete presets, not inherited vendor fields. Native CMake and
CMake Tools ignore this custom metadata.

The helper reuses an allocation when `SLURM_JOB_ID` is set. Otherwise it runs
one CTest process through `salloc -q dg --nodes=1 --gpus-per-task=1
--tasks-per-node=4 --cpus-per-task=1`, releasing the allocation after testing.
The test preset supplies the build directory, so `--test-dir` is unnecessary.

To change allocation resources, edit `sallocArguments` in the selected test
preset. Extra helper arguments are passed directly to CTest, for example:

```bash
./scripts/test.sh --preset nvidia-26.1 -R roundtrip_cpp_cuda
```

In CMake Tools, select matching configure, build, and test presets. Native
preset selection alone does not load ECMWF modules: the extension must already
have the matching environment. Loading modules in its terminal does not update
the extension process. The helper provides the self-contained command-line
workflow; native presets remain available in an appropriately initialized IDE.

### Allocation And Requirements

CTest is enabled by default through CMake's `BUILD_TESTING` option. Build the
executables before running tests. Three integration tests are registered:
`roundtrip_cpp_cuda`, `roundtrip_fort_acc`, and `roundtrip_fort_omp`.

On ECMWF HPC2020, first obtain an allocation in the GPU QoS:

```bash
salloc -q dg --nodes=1 --gpus-per-task=1 --tasks-per-node=4 --cpus-per-task=1
```

Wait for the allocation to be granted before running tests. If the test process
inherits `SLURM_JOB_ID`, each test uses plain `srun <executable>`, inheriting the
allocation's resources without overriding them.

Without an existing allocation, each test instead launches:

```text
srun -q dg --nodes=1 --tasks-per-node=4 --cpus-per-task=64 --gpus-per-task=1 <executable>
```

The launcher checks for an allocation at test execution time, not configure
time. Load the matching NVIDIA environment before running tests. These are GPU
integration tests, not CPU-only unit tests.

Tests run serially and have a 300-second timeout, including any allocation or
job-step wait. Preallocating resources avoids using this timeout for queueing.
Each rank checks every payload element and aborts MPI on corruption or missing
GPUs. CUDA runtime errors also fail the CUDA test. The OpenMP test sets
`OMP_TARGET_OFFLOAD=MANDATORY` to prevent host fallback.

To build without registering tests or requiring `srun` at configure time:

```bash
cmake -S . -B build-nvidia-26.1 -DBUILD_TESTING=OFF
```

Use `-DBUILD_TESTING=ON` when configuring to re-enable tests.

---

## License

Copyright 2026- European Centre for Medium-Range Weather Forecasts (ECMWF).

This project is licensed under the [Apache Licence, Version 2.0](LICENSE).
See [NOTICE](NOTICE) for attribution and ECMWF's privileges-and-immunities
statement.

## Developer Implementation Notes

### OpenMP Target Offloading (`roundtrip_fort_omp`)
* **Standard Enforcement:** The code implements modern **OpenMP 5.0+** syntax.
* **Deprecation Notice:** Older implementations using `use_device_ptr` will throw compiler warnings (`NVFORTRAN-W-1288`). The Fortran codebase strictly utilizes **`use_device_addr`** to robustly pass device references into MPI calls.

### OpenACC (`roundtrip_fort_acc`)
* To expose device memory pointers directly to the MPI layer, code paths passing variables to MPI routines are strictly enclosed within `!$acc host_data use_device(...)` directives.

### C++ with CUDA (`roundtrip_cpp_cuda`)
* Leverages CMake's native `enable_language(CUDA)` support.
* Interoperability boundaries with Fortran structures adhere strictly to the `ISO_C_BINDING` standard to ensure flawless Virtual Address Space alignment.
