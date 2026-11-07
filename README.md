# ccx-gpu: CalculiX with the GPU PaStiX solver on current toolchains

A CMake superbuild for CalculiX `ccx` 2.23 with:

- **PARDISO** (Intel MKL) and **SPOOLES**, and
- **PaStiX** (`*STATIC, SOLVER=PASTIX`) using the CalculiX fork
  [PaStiX4CalculiX](https://github.com/Dhondtguido/PaStiX4CalculiX) and
  [PaRSEC](https://bitbucket.org/mfaverge/parsec), with CUDA GPU offload.

CalculiX documents a PaStiX build from 2020 (CUDA 10.2, 64-bit integers,
hand-edited shell scripts). On a current system (CUDA 12, GCC 13, CMake 3.28,
Python 3.12, Ampere GPUs) that build fails, and parts that do build give wrong
results on the GPU. This repository pins the dependencies, carries the fixes as
patches, and builds everything with one command.

## Requirements

Tested on Ubuntu 24.04, GCC 13.3, CMake 3.28, CUDA 12.8, NVIDIA driver 580,
RTX 3090 / 3090 Ti.

```
sudo apt install build-essential gfortran cmake git python3 flex bison \
    libspooles-dev libarpack2-dev libmkl-dev libhwloc-dev libscotch-dev
```

plus the CUDA toolkit (default location `/usr/local/cuda`).

## Build

```
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=$HOME/opt/ccx-gpu -DCCX_CUDA_ARCH=86
cmake --build build -j
```

This installs `ccx` (a symlink to `ccx_2.23`), PaRSEC and PaStiX into the prefix.
`cmake --build` builds and installs each stage, so there is no separate install step.

| Option | Default | |
|---|---|---|
| `CCX_CUDA_ARCH` | `86` | GPU compute capability: 80 A100, 86 RTX 30xx/A40, 89 RTX 40xx/L40, 90 H100 |
| `CCX_WITH_PASTIX` | `ON` | `OFF` builds a PARDISO + SPOOLES ccx only (no CUDA needed) |
| `CCX_PASTIX_METIS` | `ON` | also build METIS 5.1.0 (64-bit `idx_t`) and PaStiX with METIS ordering, selected at run time with `PASTIX_ORDERING=metis` |
| `CUDA_TOOLKIT_ROOT_DIR` | `/usr/local/cuda` | |
| `CMAKE_INSTALL_PREFIX` | `~/opt/ccx-gpu` | |
| `CCX_UMAT_SOURCE` | (none) | Fortran file with an ABAQUS-style `subroutine umat`, compiled in place of ccx's empty `umat.f`; used by materials named `ABAQUS*` |

`ccx/` can also be used on its own (`-DCCX_SRC_DIR=…/ccx_2.23/src`) to build
ccx with CMake against an existing PaStiX/PaRSEC installation.

## Use

```
*STATIC, SOLVER=PASTIX
```

| Environment | Effect |
|---|---|
| `PASTIX_GPU=<n>` | offload factorization tasks to the first *n* GPUs (default 0: CPU only); select cards with `CUDA_VISIBLE_DEVICES` |
| `PASTIX_ORDERING=metis` | METIS nested dissection instead of Scotch (needs `CCX_PASTIX_METIS`); default Scotch. ccx prints the ordering in use |
| `PASTIX_MIXED_PRECISION=0` | factorize in FP64 (default in ccx: FP32 factorization + GMRES refinement to FP64 accuracy) |
| `OMP_NUM_THREADS` | CPU threads |

**Note:** when PaStiX is compiled in, it becomes ccx's default solver for
`*STATIC` without `SOLVER=` (CalculiX's own priority, `ini_cal.c`). Use a
separate prefix if existing decks should keep using PARDISO.

Consumer GPUs (GeForce) run FP64 at 1/64 of FP32. The default mixed-precision
mode is what makes them useful here.

**Memory.** PaStiX prints `Number of nonzeroes in L structure`. The LU factor
needs about 2 × that × 4 bytes in mixed precision, or × 8 bytes in FP64, of host
RAM. If it doesn't fit, ccx stops with a message such as

```
PaStiX error: cudaMallocHost of 32938114220 bytes (30.68 GB) failed at .../pastix_task_sopalin.c:317
```

**Ordering.** On large tetrahedral meshes METIS can give much less fill than
Scotch: for a 2.9M-equation periodic box (linear tets), Scotch gives 5.8e9
nonzeros in L (46 GB mixed precision). Compare the `Number of nonzeroes in L
structure` line of both orderings on a smaller model of the same kind before
a large run.

Example: a 1.26M-equation RVE has 3.5e9 nonzeros in L, which needs 28 GB in
mixed precision (runs on a 62 GB machine) but 56 GB in FP64 (does not).

## Benchmark

Linear static step on periodic 2.5D fiber-network RVEs (C3D10 matrix + B32 fibers,
`*EQUATION` periodic BCs) on a Ryzen 9 5950X (16 cores, 32 threads, 62 GB) and an
RTX 3090 Ti. PaStiX runs use the default mixed precision. Wall time is for the whole
ccx run.

| Equations | PARDISO | PaStiX CPU | PaStiX 1 GPU | PaStiX 2 GPUs | 1 GPU vs PARDISO | Host RAM (1 GPU) |
|---:|---:|---:|---:|---:|---:|---:|
| 172k | 7.9 s | 7.7 s | 8.5 s | 8.7 s | 0.9× | 3 GB |
| 556k | 88.8 s | 37.1 s | 29.8 s | 29.5 s | 3.0× | 14 GB |
| 1.26M | 531 s | 155 s | 86.4 s | 87.7 s | 6.1× | 41 GB |
| 1.49M | 773 s* | 222 s | 107.9 s | 111.5 s | 7.2× | 51 GB |

PaStiX results agree with PARDISO to ≤3e-11 relative (reference-point forces and
displacements) up to 1.26M equations. The GPU pays off from roughly 500k
equations.

\*With unpatched ccx. At 1.49M equations, ccx's PARDISO returned a wrong solution: 8e-4 relative
error, with the reaction-force pair RP-X f<sub>y</sub> / RP-Y f<sub>x</sub>
(−104.3 vs 7.85) violating the symmetry of the system. All PaStiX runs (CPU,
1 GPU, 2 GPUs) agree with each other, satisfy that symmetry (7.6117 / 7.6117),
and report a backward error of 4e-14 after refinement. ccx calls PARDISO with
default parameters (symmetric indefinite, 1e-8 pivot perturbation, no matching
or scaling) and does not check its residual. ccx patch 3 fixes this: the
patched PARDISO agrees with PaStiX to 7e-13 on this model, in the same 773 s.

**Two GPUs:** no gain over one. Both cards receive tasks, but average GPU
utilization stays at 7–12%: the factorization is limited by its CPU-side tasks and
scheduling, not GPU throughput. A second GPU is more useful for running a second
independent job (`CUDA_VISIBLE_DEVICES=1`), within host RAM.

**Memory:** in FP64 the 1.26M model needs 56 GB for L+U alone and does not fit in
62 GB.

## Viscoelastic verification

`examples/viscoelastic/` holds a linear viscoelastic (Prony series) UMAT,
`umat_prony_visco.f`, for `-DCCX_UMAT_SOURCE`, plus the tests used to check
that every solver gives the same history-dependent result.

- `single_element.inp` + `check_single_element.py`: uniaxial ramp (1 s) and
  relaxation (40 s) of one C3D8, compared with the closed-form hereditary
  integral. Agreement 1.7e-7 over 30 increments (ccx prints 7 digits).
- `make_visco_rve.py` turns a periodic RVE deck into the same tensile load
  with a viscoelastic matrix: ramp 1 s, hold 40 s, 30 fixed increments.
  `compare_visco.py` compares reference-point displacements and reaction forces
  increment by increment.

Results on the 172k-equation fiber RVE, with ccx Newton tolerances tightened to
1e-8 (`*CONTROLS, PARAMETERS=FIELD`) so the comparison measures the linear
solvers, not where Newton happened to stop:

| Solver | Wall time | Max difference vs PARDISO |
|---|---:|---:|
| PARDISO (patched) | 439 s | reference |
| PaStiX CPU | 498 s | 2.5e-15 |
| PaStiX 1 GPU | 417 s | 2.3e-15 |
| PaStiX 2 GPUs | 374 s | 2.1e-15 |
| SPOOLES | 1480 s | 1.6e-8 |

With ccx's default tolerances the solvers agree to 5e-7, the footprint of Newton
stopping on different iterations. SPOOLES does no iterative refinement and needs
up to 8 Newton iterations per increment, where the others need 3.

## What the patches fix

All patches are in `patches/`: `git format-patch` series against the pinned
PaRSEC and PaStiX commits, and against the ccx release tarball. Each patch
message gives the details.

**PaRSEC** (`mfaverge/parsec`, branch `mymaster` @ 6022a61)

The CalculiX install notes say to clone `master`, but `master`'s PTG compiler
ignores the `pushout=` hint that PaStiX uses for its overlapping column-block and
block data. The GPU then factorizes with stale data: the residual after
factorization was about 1e-2 instead of 1e-8. `mymaster` honours it.

1. Skip thread binding (as in CalculiX's `make_parsec.sh`).
2. Make DPLASMA optional: it isn't needed, and it requires Python 2.
3. Recognise sm_80/86/87/89/90. Otherwise every Ampere and newer GPU is
   skipped as "Unsupported GPU" and all work runs on the CPU.
4. Skip flows without data in GPU pop and push-complete (segfault with PaStiX's 2D tasks).

**PaStiX4CalculiX** (@ d6b493b)

1. Examples and tests optional (they break configuration on CMake ≥ 3.27).
2. Precision code generator runs on Python 3.12 (an `imp` import, invalid `re`
   escapes, and diagnostics printed into CMake's dependency list).
3. Accept `Threads::Threads` from modern FindCUDA.
4. CUDA architecture configurable (was hard-wired to sm_35, which CUDA 12 dropped).
5. LightSpMV ported to `__shfl_*_sync` with correct per-vector and live-lane
   masks, plus `__syncwarp` for shared-memory hand-off. Volta and later no
   longer run a warp in lockstep.
6. LightSpMV index arrays follow `pastix_int_t`. It hard-coded `int64_t`, so a
   32-bit PaStiX fed 32-bit indices to 64-bit kernels.
7. Check host allocations. Upstream never checks `malloc`, nor the pinned
   `cudaMallocHost` used for the L/U factors, so running out of memory showed up
   as a segfault from many threads. A force-included header now routes
   `malloc`/`calloc`/`realloc` to checked wrappers, including in the
   PaRSEC-generated task code, and the CUDA allocations check their status.
8. One cuBLAS handle per GPU. A single handle, bound to device 0, was shared by
   every GPU task, so cuBLAS tasks scheduled on a second GPU used device 0's
   handle and workspace.

**CalculiX** (ccx 2.23 tarball)

1. `pastix.c` hands PaStiX index arrays of PaStiX's own integer type. Upstream
   passes ccx's `int` arrays straight through, which forces a 32-bit PaStiX. A
   32-bit PaStiX overflows its factor offsets once L+U exceeds 2^31 entries:
   about 600k equations for C3D10 fiber RVEs, where it segfaults during analysis.
2. `PASTIX_GPU` is read as a number of GPUs. Upstream only recognised `1`.
3. PARDISO parameters are set explicitly and its result is checked. Upstream
   used all defaults (`iparm[0]=0`) and ignored PARDISO's error code. On a
   1.49M-equation RVE, PARDISO silently perturbed 27 pivots and returned a
   solution with 8e-4 relative error. Scaling, weighted matching and up to 10
   refinement steps fix this at no measurable cost (773 s before and after), and
   ccx now reports perturbed pivots and stops on PARDISO errors. Error -4 in the
   solve phase (refinement short of PARDISO's tolerance, typical for small Newton
   corrections) is accepted only if the computed backward error is below 1e-10.
4. PaStiX: refactorize before giving up. Between Newton iterations ccx reuses an
   earlier LU as a GMRES preconditioner. When GMRES failed in double precision,
   ccx exited with status 5 without factorizing the current matrix. It now
   refactorizes first. (Seen with a viscoelastic UMAT: a 2-GPU run stopped at
   3.8e-12 against the 1e-12 target.)
5. PaStiX: accept a stalled refinement with a small residual. PaStiX uses static
   pivoting; on an RVE with beam fibers and `*EQUATION` constraints, GMRES
   stalled at 2.4e-11 on fresh double-precision factorizations, and ccx
   exited. A solution whose relative residual is below 1e-9 is now accepted
   with a note.

**Integer size.** PaStiX is built with 64-bit integers (`PASTIX_INT64=ON`)
against the distribution's 64-bit Scotch (`scotch-int64`, linked statically because
both Scotch builds share a soname). ccx itself keeps `ITG=int`, so SPOOLES,
ARPACK and MKL are the stock LP64 packages. CalculiX's own instructions
(`Makefile_i8`) instead rebuild everything with 64-bit integers.

## Licenses

CalculiX: GPL-2.0. PaStiX: CeCILL-C. PaRSEC: BSD-3-Clause. Each patch is
distributed under the license of the project it modifies. The build files in
this repository are GPL-2.0, like CalculiX.
