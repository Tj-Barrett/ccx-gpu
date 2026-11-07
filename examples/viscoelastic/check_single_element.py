"""Compare the single-element relaxation test with the closed-form hereditary integral.
usage: python check_single_element.py single_element.dat"""
import math
import sys

E0, G, TAU = 30000.0, (0.3, 0.2, 0.1), (0.2, 2.0, 20.0)
EPS0, TR = 0.01, 1.0
GINF = 1.0 - sum(G)

def sigma(t):
    """sigma(t) = int_0^t' E(t-s) eps0/tr ds, t' = min(t, tr)"""
    tp = min(t, TR)
    integral = GINF * tp + sum(g * tau * (math.exp(-(t - tp) / tau) - math.exp(-t / tau))
                               for g, tau in zip(G, TAU))
    return E0 * EPS0 / TR * integral

rows = []
lines = open(sys.argv[1]).read().split('\n')
for i, l in enumerate(lines):
    if 'total force (fx,fy,fz) for set TOP and time' in l:
        t = float(l.split()[-1])
        fz = float(lines[i + 2].split()[2])
        rows.append((t, fz))
# step 2 times restart at 0 in ccx output: make them absolute
out, offset, prev = [], 0.0, -1.0
for t, fz in rows:
    if t <= prev and offset == 0.0:
        offset = TR
    prev = t
    out.append((t + offset, fz))
worst = 0.0
for t, fz in out:
    ref = sigma(t)
    err = abs(fz - ref) / (E0 * EPS0)
    worst = max(worst, err)
    print(f't={t:7.2f}  ccx={fz:10.4f}  exact={ref:10.4f}  err/sigma0={err:.1e}')
print(f'worst relative error: {worst:.1e} over {len(out)} increments')
