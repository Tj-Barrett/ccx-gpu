"""Compare viscoelastic RVE runs increment by increment against a reference run.
usage: python compare_visco.py ref.dat other.dat ..."""
import sys

def history(path):
    """{(step time index, set, quantity): (x, y, z)} for every increment"""
    data, lines = [], open(path).read().split('\n')
    for i, l in enumerate(lines):
        if ' for set RP-' in l and ('displacements' in l or 'forces' in l):
            p = lines[i + 2].split()
            data.append((l.split()[0], l.split('set ')[1].split()[0], [float(x) for x in p[1:4]]))
    return data

ref = history(sys.argv[1])
scale = {q: max(abs(v) for qq, _, vec in ref if qq == q for v in vec) for q in ('displacements', 'forces')}
print(f'{sys.argv[1]}: {len(ref) // 6} increments')
for f in sys.argv[2:]:
    h = history(f)
    if len(h) != len(ref):
        print(f'{f}: {len(h) // 6} increments -- MISMATCH in number of increments')
        continue
    worst = {q: 0.0 for q in scale}
    for (q, s, a), (_, _, b) in zip(ref, h):
        worst[q] = max(worst[q], max(abs(x - y) for x, y in zip(a, b)) / scale[q])
    print(f'{f:32s} max rel diff  U: {worst["displacements"]:.1e}  RF: {worst["forces"]:.1e}')

# relaxation curve of the reference: RP-Z reaction force per increment
fz = [vec[2] for q, s, vec in ref if q == 'forces' and s == 'RP-Z']
print('RP-Z fz history (reference):', ' '.join(f'{v:.4g}' for v in fz))
