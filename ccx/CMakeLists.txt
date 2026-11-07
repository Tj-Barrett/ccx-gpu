# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Thomas J. Barrett
cmake_minimum_required(VERSION 3.20)
project(calculix_ccx C Fortran)

# CalculiX only ships Makefiles; this builds ccx from an unpacked source tree.
set(CCX_VERSION "2.23" CACHE STRING "CalculiX ccx version")
set(CCX_SRC_DIR "" CACHE PATH "ccx source directory (…/CalculiX/ccx_<version>/src)")
if(NOT EXISTS "${CCX_SRC_DIR}/ccx_${CCX_VERSION}.c")
  message(FATAL_ERROR "Set CCX_SRC_DIR to the ccx_${CCX_VERSION} src directory")
endif()

option(CCX_SPOOLES "Enable SPOOLES solver" ON)
option(CCX_PARDISO "Enable PARDISO solver (Intel MKL)" ON)
option(CCX_PASTIX  "Enable PaStiX solver (PaStiX4CalculiX + PaRSEC + CUDA)" OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(OpenMP REQUIRED COMPONENTS C Fortran)
find_package(Threads REQUIRED)

# Source list comes from upstream Makefile.inc so it stays in sync with the release
file(READ "${CCX_SRC_DIR}/Makefile.inc" _mkinc)
string(REGEX MATCH "SCCXF = ([^=]*)SCCXC" _f "${_mkinc}")
string(REGEX MATCH "SCCXC = ([^=]*)SCCXCXX" _c "${_mkinc}")
string(REGEX MATCHALL "[A-Za-z0-9_.]+\\.f" CCX_F_SOURCES "${_f}")
string(REGEX MATCHALL "[A-Za-z0-9_.]+\\.c" CCX_C_SOURCES "${_c}")
list(TRANSFORM CCX_F_SOURCES PREPEND "${CCX_SRC_DIR}/")
list(TRANSFORM CCX_C_SOURCES PREPEND "${CCX_SRC_DIR}/")
# Makefile.inc lists some objects (e.g. mafillmm.c) whose only source is the .f
list(FILTER CCX_C_SOURCES EXCLUDE REGEX "/mafillmm\\.c$")
# Optional ABAQUS-style user material (subroutine umat) in place of ccx's empty umat.f;
# used by materials whose name starts with ABAQUS
set(CCX_UMAT_SOURCE "" CACHE FILEPATH "Fortran file with an ABAQUS-style subroutine umat")
if(CCX_UMAT_SOURCE)
  if(NOT EXISTS "${CCX_UMAT_SOURCE}")
    message(FATAL_ERROR "CCX_UMAT_SOURCE not found: ${CCX_UMAT_SOURCE}")
  endif()
  list(FILTER CCX_F_SOURCES EXCLUDE REGEX "/umat\\.f$")
  list(APPEND CCX_F_SOURCES "${CCX_UMAT_SOURCE}")
  message(STATUS "user material: ${CCX_UMAT_SOURCE}")
endif()
list(REMOVE_DUPLICATES CCX_F_SOURCES)
list(REMOVE_DUPLICATES CCX_C_SOURCES)
list(LENGTH CCX_F_SOURCES _nf)
list(LENGTH CCX_C_SOURCES _nc)
message(STATUS "ccx ${CCX_VERSION}: ${_nf} Fortran, ${_nc} C sources")

add_library(ccx_core STATIC ${CCX_F_SOURCES} ${CCX_C_SOURCES})
add_executable(ccx "${CCX_SRC_DIR}/ccx_${CCX_VERSION}.c")
set_target_properties(ccx PROPERTIES
  OUTPUT_NAME "ccx_${CCX_VERSION}"
  LINKER_LANGUAGE Fortran)

set(CCX_DEFS ARCH=Linux ARPACK MATRIXSTORAGE USE_MT=1)
set(CCX_INCS "")
set(CCX_LIBS "")

target_compile_options(ccx_core PRIVATE
  $<$<COMPILE_LANGUAGE:Fortran>:-cpp -fallow-argument-mismatch -w>
  $<$<COMPILE_LANGUAGE:C>:-w>)

# --- ARPACK (LP64) ---
find_library(ARPACK_LIB arpack REQUIRED)
list(APPEND CCX_LIBS ${ARPACK_LIB})

# --- SPOOLES ---
if(CCX_SPOOLES)
  find_path(SPOOLES_INC spooles/MT/spoolesMT.h REQUIRED)
  find_library(SPOOLES_LIB spooles REQUIRED)
  list(APPEND CCX_DEFS SPOOLES)
  list(APPEND CCX_INCS "${SPOOLES_INC}/spooles")
  list(APPEND CCX_LIBS ${SPOOLES_LIB})
endif()

# --- PARDISO via MKL (GNU threading, LP64) ---
if(CCX_PARDISO)
  find_path(MKL_INC mkl_service.h PATHS /usr/include/mkl $ENV{MKLROOT}/include REQUIRED)
  foreach(_l mkl_gf_lp64 mkl_gnu_thread mkl_core)
    find_library(${_l}_LIB ${_l} PATHS $ENV{MKLROOT}/lib/intel64 $ENV{MKLROOT}/lib REQUIRED)
  endforeach()
  list(APPEND CCX_DEFS PARDISO)
  list(APPEND CCX_INCS "${MKL_INC}")
  list(APPEND CCX_LIBS -Wl,--start-group ${mkl_gf_lp64_LIB} ${mkl_gnu_thread_LIB}
       ${mkl_core_LIB} -Wl,--end-group ${CMAKE_DL_LIBS})
else()
  find_package(LAPACK REQUIRED)
  list(APPEND CCX_LIBS ${LAPACK_LIBRARIES})
endif()

# --- PaStiX (PaStiX4CalculiX fork + PaRSEC + CUDA) ---
# The fork hard-requires PaRSEC and CUDA, so there is no CPU-only variant; the GPU
# is selected at run time with PASTIX_GPU=1 (and PASTIX_MIXED_PRECISION=0 for FP64).
# PaStiX should be built with PASTIX_INT64=ON: its factor offsets are pastix_int_t and
# overflow 32 bits around 600k equations. ccx keeps ITG=int; patches/ccx widens the
# CSC arrays it hands to PaStiX.
if(CCX_PASTIX)
  set(PASTIX_ROOT "${CMAKE_INSTALL_PREFIX}" CACHE PATH "PaStiX4CalculiX install prefix")
  set(PARSEC_ROOT "${CMAKE_INSTALL_PREFIX}" CACHE PATH "PaRSEC install prefix")
  if(NOT CCX_PARDISO)
    message(FATAL_ERROR "CCX_PASTIX needs CCX_PARDISO (MKL provides CBLAS/LAPACKE)")
  endif()
  find_package(CUDAToolkit REQUIRED)
  find_path(PASTIX_INC pastix.h PATHS ${PASTIX_ROOT}/include NO_DEFAULT_PATH REQUIRED)
  foreach(_l pastix pastix_kernels pastix_parsec pastix_kernels_cuda spm)
    find_library(${_l}_LIB ${_l} PATHS ${PASTIX_ROOT} PATH_SUFFIXES lib lib64 NO_DEFAULT_PATH REQUIRED)
  endforeach()
  find_library(PARSEC_LIB parsec PATHS ${PARSEC_ROOT} PATH_SUFFIXES lib lib64 NO_DEFAULT_PATH REQUIRED)
  find_library(HWLOC_LIB hwloc REQUIRED)
  # Scotch's integer size must match PaStiX's (Debian/Ubuntu ship both in libscotch-dev)
  file(STRINGS "${PASTIX_INC}/pastix/config.h" _int64 REGEX "^#define PASTIX_INT64")
  if(_int64)
    set(_scotch_hint /usr/lib/${CMAKE_LIBRARY_ARCHITECTURE}/scotch-int64)
  else()
    set(_scotch_hint /usr/lib/${CMAKE_LIBRARY_ARCHITECTURE})
  endif()
  set(SCOTCH_LIBDIR "${_scotch_hint}" CACHE PATH "Scotch libraries matching PaStiX's integer size")
  # static: the int32 and int64 shared libraries have the same soname, so the loader
  # could otherwise pick the wrong one at run time
  find_library(SCOTCH_LIB NAMES libscotch.a scotch PATHS ${SCOTCH_LIBDIR} NO_DEFAULT_PATH REQUIRED)
  find_library(SCOTCHERR_LIB NAMES libscotcherr.a scotcherr PATHS ${SCOTCH_LIBDIR} NO_DEFAULT_PATH REQUIRED)
  message(STATUS "PaStiX integers: ${_int64}  Scotch: ${SCOTCH_LIB}")
  # PaStiX built with PASTIX_ORDERING_METIS needs METIS (idx_t as wide as pastix_int_t);
  # ccx selects it at run time with PASTIX_ORDERING=metis (patches/ccx 0007)
  file(STRINGS "${PASTIX_INC}/pastix/config.h" _metis REGEX "^#define PASTIX_ORDERING_METIS")
  set(_metis_lib "")
  if(_metis)
    set(METIS_ROOT "${CMAKE_INSTALL_PREFIX}" CACHE PATH "METIS install prefix")
    find_library(METIS_LIB NAMES libmetis.a metis PATHS ${METIS_ROOT} PATH_SUFFIXES lib lib64 NO_DEFAULT_PATH REQUIRED)
    set(_metis_lib "${METIS_LIB}")
    message(STATUS "PaStiX METIS ordering: ${METIS_LIB}")
  endif()
  list(APPEND CCX_DEFS PASTIX)
  # PaStiX first: pastix.c includes <pastix.h>, which ccx's own src/pastix.h would shadow
  set(CCX_INCS_FIRST "${PASTIX_INC}")
  # PaStiX archives depend on each other circularly; MKL (linked after) supplies CBLAS/LAPACKE
  list(PREPEND CCX_LIBS
    -Wl,--start-group ${pastix_LIB} ${pastix_kernels_LIB} ${pastix_parsec_LIB}
    ${pastix_kernels_cuda_LIB} ${spm_LIB} -Wl,--end-group
    ${PARSEC_LIB} ${HWLOC_LIB} ${SCOTCH_LIB} ${SCOTCHERR_LIB} ${_metis_lib} z
    CUDA::cublas CUDA::cudart CUDA::cuda_driver stdc++ rt)
  get_filename_component(_parsec_libdir "${PARSEC_LIB}" DIRECTORY)
  set_target_properties(ccx PROPERTIES BUILD_RPATH "${_parsec_libdir}"
                                       INSTALL_RPATH "${_parsec_libdir}")
endif()

foreach(_t ccx_core ccx)
  target_compile_definitions(${_t} PRIVATE $<$<COMPILE_LANGUAGE:C>:${CCX_DEFS}>)
  target_include_directories(${_t} BEFORE PRIVATE ${CCX_INCS_FIRST})
  target_include_directories(${_t} PRIVATE ${CCX_SRC_DIR} ${CCX_INCS})
endforeach()

target_link_libraries(ccx PRIVATE ccx_core ${CCX_LIBS}
  OpenMP::OpenMP_C OpenMP::OpenMP_Fortran Threads::Threads m)

install(TARGETS ccx RUNTIME DESTINATION bin)
install(CODE "execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink
  ccx_${CCX_VERSION} \$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/bin/ccx)")
