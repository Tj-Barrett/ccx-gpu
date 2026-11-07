# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Thomas J. Barrett
cmake_minimum_required(VERSION 3.20)
project(ccx_gpu_superbuild NONE)

# Superbuild: CalculiX ccx with PARDISO and (optionally) the GPU-capable PaStiX solver.
# Fetches PaRSEC and PaStiX4CalculiX at pinned commits, applies patches/ and installs
# everything into CMAKE_INSTALL_PREFIX.

include(ExternalProject)
find_package(Git REQUIRED)

option(CCX_WITH_PASTIX "Build PaRSEC + PaStiX4CalculiX (CUDA) and enable SOLVER=PASTIX" ON)
option(CCX_PASTIX_METIS "Also build METIS (64-bit idx_t) for PaStiX: PASTIX_ORDERING=metis at run time" ON)
set(CCX_VERSION "2.23" CACHE STRING "CalculiX ccx version")
set(CCX_CUDA_ARCH "86" CACHE STRING "CUDA compute capability for the PaStiX kernels (80, 86, 89, 90, ...)")
set(CCX_UMAT_SOURCE "" CACHE FILEPATH "Optional ABAQUS-style UMAT compiled into ccx (materials named ABAQUS*)")
set(CCX_BLA_VENDOR "Intel10_64lp" CACHE STRING "BLA_VENDOR used by PaStiX to find CBLAS/LAPACKE")
set(CUDA_TOOLKIT_ROOT_DIR "/usr/local/cuda" CACHE PATH "CUDA toolkit")

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "$ENV{HOME}/opt/ccx-gpu" CACHE PATH "Install prefix" FORCE)
endif()
set(PREFIX "${CMAKE_INSTALL_PREFIX}")

set(CCX_URL "https://www.dhondt.de/ccx_${CCX_VERSION}.src.tar.bz2" CACHE STRING "ccx source tarball")
set(CCX_SHA256 "9c88385c10fb04f5dc6c4e98027a51bebdd8aee3920e05190d6c1dd08357d6e7" CACHE STRING "")

# METIS 5.1.0 (the Debian/Ubuntu source, GKlib included), built with 64-bit idx_t to match
# the 64-bit PaStiX
set(METIS_URL "http://archive.ubuntu.com/ubuntu/pool/universe/m/metis/metis_5.1.0.dfsg.orig.tar.xz"
    CACHE STRING "METIS source tarball")
set(METIS_SHA256 "c50a88b92b01fa3972c5c92cf50117f126c62589b8f793657c7d865c59c23615" CACHE STRING "")

set(PARSEC_REPO "https://bitbucket.org/mfaverge/parsec.git")
set(PARSEC_COMMIT "6022a61dc96c25f11dd2aeabff2a5b3d7bce867d")  # branch mymaster; master lacks pushout hints
set(PASTIX_REPO "https://github.com/Dhondtguido/PaStiX4CalculiX.git")
set(PASTIX_COMMIT "d6b493bc431ecf860b3578a2ee6a25f392eb44be")

file(GLOB PARSEC_PATCHES "${CMAKE_CURRENT_SOURCE_DIR}/patches/parsec/*.patch")
file(GLOB PASTIX_PATCHES "${CMAKE_CURRENT_SOURCE_DIR}/patches/pastix/*.patch")
file(GLOB CCX_PATCHES "${CMAKE_CURRENT_SOURCE_DIR}/patches/ccx/*.patch")
list(SORT PARSEC_PATCHES)
list(SORT PASTIX_PATCHES)
list(SORT CCX_PATCHES)
# ExternalProject would split a ;-list into separate arguments: pass it |-separated
string(REPLACE ";" "|" CCX_PATCHES_ARG "${CCX_PATCHES}")

# 64-bit PaStiX: with 32-bit integers its factor offsets overflow at ~600k equations.
# Scotch must use the same integer size (Debian/Ubuntu libscotch-dev ships scotch-int64).
set(SCOTCH_INT64_INCDIR "/usr/include/scotch-int64" CACHE PATH "64-bit Scotch headers")
set(SCOTCH_INT64_LIBDIR "/usr/lib/x86_64-linux-gnu/scotch-int64" CACHE PATH "64-bit Scotch libraries")

# Old CMake code in the dependencies: FindCUDA and pre-3.5 policies
set(_legacy_cmake -DCMAKE_POLICY_DEFAULT_CMP0146=OLD -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

set(_ccx_deps "")
if(CCX_WITH_PASTIX)
  set(_pastix_deps parsec)
  set(_pastix_metis -DPASTIX_ORDERING_METIS=OFF)
  if(CCX_PASTIX_METIS)
    ExternalProject_Add(metis
      URL               ${METIS_URL}
      URL_HASH          SHA256=${METIS_SHA256}
      PATCH_COMMAND     sed -i "s/^#define IDXTYPEWIDTH 32/#define IDXTYPEWIDTH 64/" include/metis.h
      CMAKE_ARGS
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=${PREFIX}
        -DSHARED=OFF
        -DGKLIB_PATH=<SOURCE_DIR>/GKlib
        ${_legacy_cmake})
    list(APPEND _pastix_deps metis)
    set(_pastix_metis -DPASTIX_ORDERING_METIS=ON -DMETIS_DIR=${PREFIX})
  endif()

  ExternalProject_Add(parsec
    GIT_REPOSITORY    ${PARSEC_REPO}
    GIT_TAG           ${PARSEC_COMMIT}
    GIT_SHALLOW       OFF
    UPDATE_DISCONNECTED ON
    PATCH_COMMAND     ${GIT_EXECUTABLE} apply ${PARSEC_PATCHES}
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_INSTALL_PREFIX=${PREFIX}
      -DCMAKE_C_FLAGS=-fcommon
      -DBUILD_SHARED_LIBS=ON
      -DBUILD_TESTING=OFF
      -DPARSEC_WITH_DEVEL_HEADERS=ON
      -DPARSEC_DIST_WITH_MPI=OFF
      -DPARSEC_GPU_WITH_CUDA=ON
      -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
      -DCUDA_USE_STATIC_CUDA_RUNTIME=OFF
      ${_legacy_cmake})

  ExternalProject_Add(pastix
    DEPENDS           ${_pastix_deps}
    GIT_REPOSITORY    ${PASTIX_REPO}
    GIT_TAG           ${PASTIX_COMMIT}
    GIT_SHALLOW       OFF
    UPDATE_DISCONNECTED ON
    PATCH_COMMAND     ${GIT_EXECUTABLE} apply ${PASTIX_PATCHES}
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_INSTALL_PREFIX=${PREFIX}
      "-DCMAKE_C_FLAGS=-fopenmp -fPIC -fcommon"
      -DBUILD_SHARED_LIBS=OFF
      -DPASTIX_INT64=ON
      -DPASTIX_ORDERING_SCOTCH=ON
      -DSCOTCH_INCDIR=${SCOTCH_INT64_INCDIR}
      -DSCOTCH_LIBDIR=${SCOTCH_INT64_LIBDIR}
      ${_pastix_metis}
      -DPASTIX_WITH_PARSEC=ON
      -DPARSEC_DIR=${PREFIX}
      -DPASTIX_WITH_CUDA=ON
      -DPASTIX_CUDA_ARCH=${CCX_CUDA_ARCH}
      -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
      -DCUDA_DIR=${CUDA_TOOLKIT_ROOT_DIR}
      -DPASTIX_WITH_STARPU=OFF
      -DPASTIX_WITH_MPI=OFF
      -DPASTIX_WITH_FORTRAN=OFF
      -DBLA_VENDOR=${CCX_BLA_VENDOR}
      ${_legacy_cmake})
  set(_ccx_deps pastix)
endif()

ExternalProject_Add(ccx_source
  URL               ${CCX_URL}
  URL_HASH          SHA256=${CCX_SHA256}
  PATCH_COMMAND     ${CMAKE_COMMAND} -DPATCHES=${CCX_PATCHES_ARG} -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/apply_patches.cmake
  CONFIGURE_COMMAND ""
  BUILD_COMMAND     ""
  INSTALL_COMMAND   "")
ExternalProject_Get_Property(ccx_source SOURCE_DIR)

ExternalProject_Add(ccx
  DEPENDS           ccx_source ${_ccx_deps}
  SOURCE_DIR        ${CMAKE_CURRENT_SOURCE_DIR}/ccx
  CMAKE_ARGS
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=${PREFIX}
    -DCCX_VERSION=${CCX_VERSION}
    -DCCX_SRC_DIR=${SOURCE_DIR}/ccx_${CCX_VERSION}/src
    -DCCX_PASTIX=${CCX_WITH_PASTIX}
    -DPASTIX_ROOT=${PREFIX}
    -DPARSEC_ROOT=${PREFIX}
    -DMETIS_ROOT=${PREFIX}
    -DSCOTCH_LIBDIR=${SCOTCH_INT64_LIBDIR}
    -DCCX_UMAT_SOURCE=${CCX_UMAT_SOURCE}
  BUILD_ALWAYS      ON)
