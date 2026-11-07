# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Thomas J. Barrett
"""Copy an RVE benchmark deck and make the matrix viscoelastic: same ZZ tensile
displacement ramped over 1 s, then held for 40 s (relaxation). Fixed increments so
every solver takes identical steps.  usage: python make_visco_rve.py <in_pbc.inp> <out.inp>"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()

# viscoelastic matrix replaces the elastic one (fibers stay elastic)
mat = re.search(r'\*Material, name=MATRIX\n.*?(?=\n\*Material|\n\*Solid Section)', s, re.S)
s = s[:mat.start()] + open('visco_material.inc').read().rstrip('\n') + s[mat.end():]
s = s.replace('*Solid Section, elset=MATRIX, material=MATRIX',
              '*Solid Section, elset=MATRIX, material=ABAQUS_VISCO')

# replace the load step(s) with ramp + hold
head = s[:s.index('*STEP')]
uz = re.search(r'RP-Z,3,3,([-+0-9.eE]+)', s).group(1)
steps = f'''** Ramp: ZZ tensile displacement over 1 s (10 increments)
*STEP
*STATIC, DIRECT
0.1, 1.0
*BOUNDARY
RP-X,2,2,0.0
RP-X,3,3,0.0
RP-Y,1,1,0.0
RP-Y,3,3,0.0
RP-Z,1,1,0.0
RP-Z,2,2,0.0
RP-Z,3,3,{uz}
*NODE PRINT, NSET=RP-X
U, RF
*NODE PRINT, NSET=RP-Y
U, RF
*NODE PRINT, NSET=RP-Z
U, RF
*END STEP
** Hold: displacement fixed for 40 s, the matrix relaxes (20 increments)
*STEP
*STATIC, DIRECT
2.0, 40.0
*NODE PRINT, NSET=RP-X
U, RF
*NODE PRINT, NSET=RP-Y
U, RF
*NODE PRINT, NSET=RP-Z
U, RF
*END STEP
'''
open(dst, 'w').write(head + steps)
print(f'{dst}: viscoelastic matrix, RP-Z u3={uz} ramp 1 s + hold 40 s')
