# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Thomas J. Barrett
# cmake -DPATCHES="a.patch|b.patch" -P apply_patches.cmake   (run in the source tree)
# Uses patch(1) rather than git apply: git apply silently skips files when the
# source tree happens to sit inside another git work tree.
find_program(PATCH_EXECUTABLE patch REQUIRED)
string(REPLACE "|" ";" PATCHES "${PATCHES}")
foreach(p IN LISTS PATCHES)
  execute_process(COMMAND ${PATCH_EXECUTABLE} -p1 --forward --batch -i ${p} RESULT_VARIABLE rc)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "failed to apply ${p}")
  endif()
  message(STATUS "applied ${p}")
endforeach()
