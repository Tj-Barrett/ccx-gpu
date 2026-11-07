** SPDX-License-Identifier: MIT
** Copyright (c) 2026 Thomas J. Barrett
** Linear viscoelastic matrix (umat_prony_visco.f): E0, nu, N, (g_i, tau_i)
** E(t) = E0*(1 - sum g_i (1 - exp(-t/tau_i))),  E_inf = 0.4*E0
*Material, name=ABAQUS_VISCO
*User Material, constants=9
30000., 0.3, 3, 0.3, 0.2, 0.2, 2., 0.1
20.
*Depvar
18
*Density
1.200000e-09
