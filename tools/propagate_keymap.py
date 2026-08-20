#!/usr/bin/env python3
"""
Map the eyeslash Corne keymap (48 keys) onto the other three keyboards.

Corne physical index layout (48):
  row0:  L 0..5   | C 6            | R 7..12
  row1:  L 13..18 | C 19,20,21     | R 22..27
  row2:  L 28..33 | C 34,35        | R 36..41
  thumb: 42..47

  "alpha core" = the 36 non-centre alphas
  "centre cluster" = 6,19,20,21,34,35  (mmv/mkp/SPACE — eyeslash-specific)
  "thumbs" = 42..47
"""
import re, sys, os

CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config")

AROW0 = list(range(0, 6))   + list(range(7, 13))
AROW1 = list(range(13, 19)) + list(range(22, 28))
AROW2 = list(range(28, 34)) + list(range(36, 42))
THUMBS = list(range(42, 48))
CENTRE = [6, 19, 20, 21, 34, 35]

O = "ORIG"   # sentinel: take the original keyboard's binding at this position


# ---------------------------------------------------------------- parsing
def split_bindings(body):
    """Split a bindings body into individual '&foo ARG ARG' tokens."""
    body = re.sub(r'//[^\n]*', ' ', body)
    body = re.sub(r'/\*.*?\*/', ' ', body, flags=re.S)
    parts = re.split(r'(?=&)', body)
    return [' '.join(p.split()) for p in parts if p.strip()]


def parse_layers(path):
    """Return [(layer_node_name, [bindings...], raw_layer_text), ...]"""
    s = open(path).read()
    i = s.find('keymap {')
    if i < 0:
        return []
    depth, j = 0, i
    while j < len(s):
        if s[j] == '{':
            depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0:
                break
        j += 1
    km = s[i:j]
    # skip past the outer node's own header, otherwise the first layer
    # gets named after the `keymap` node itself
    c = km.find('compatible = "zmk,keymap";')
    if c >= 0:
        km = km[c + len('compatible = "zmk,keymap";'):]
    out = []
    for m in re.finditer(r'(\w+)\s*\{(.*?)bindings = <(.*?)>;(.*?)\n\s*\};', km, re.S):
        name, pre, body, post = m.groups()
        out.append((name, split_bindings(body), pre + post))
    return out


def layer_meta(pre_post, fallback_name):
    """Pull display-name / label out of a layer's non-bindings text."""
    d = re.search(r'display-name = "([^"]*)"', pre_post)
    l = re.search(r'label = "([^"]*)"', pre_post)
    lines = []
    if d:
        lines.append(f'            display-name = "{d.group(1)}";')
    if l:
        lines.append(f'            label = "{l.group(1)}";')
    return lines


def sensor_of(pre_post):
    m = re.search(r'sensor-bindings = <([^>]*)>;', pre_post)
    return m.group(1).strip() if m else None


# ---------------------------------------------------------------- mappings
def build_map(target):
    """Return a list of length target_keycount; each entry is a corne index or O."""
    if target == 'charybdis':                      # 42
        return AROW0 + AROW1 + AROW2 + THUMBS

    if target == 'anywhy_flake':                   # 46
        return (AROW0 + AROW1 + AROW2 +
                [O, O] + THUMBS + [O, O])

    if target == 'eyelash_sofle':                  # 64
        return ([O] * 13 +                          # number row: untouched
                AROW0 + [O] +                       # 12 alphas + 1 outer extra
                AROW1 + [O] +
                AROW2 + [O] +
                [O, O, O] + THUMBS + [O, O, O])     # 12-key bottom row

    raise ValueError(target)


TARGETS = {
    # name             file                    keys  encoder  row widths
    'charybdis':     ('charybdis.keymap',        42,  False, [12, 12, 12, 6]),
    'anywhy_flake':  ('anywhy_flake.keymap',     46,  False, [12, 12, 12, 10]),
    'eyelash_sofle': ('eyelash_sofle.keymap',    64,  True,  [13, 13, 13, 13, 12]),
}


# ---------------------------------------------------------------- emit
def remap_positions(raw, idxmap):
    """Translate corne key positions into target positions, dropping the unmapped."""
    inv = {c: t for t, c in enumerate(idxmap) if c is not O}
    nums = [int(n) for n in re.findall(r'\d+', raw)]
    return sorted({inv[n] for n in nums if n in inv})


def emit(target, corne_layers, corne_src):
    fname, nkeys, has_enc, widths = TARGETS[target]
    path = os.path.join(CONFIG, fname)
    idxmap = build_map(target)
    assert len(idxmap) == nkeys, f"{target}: map is {len(idxmap)}, need {nkeys}"
    assert sum(widths) == nkeys

    orig = parse_layers(path)

    # --- header: reuse the corne preamble up to the keymap node ---
    head = corne_src[:corne_src.find('    keymap {')]

    # remap the home-row-mod trigger positions for this geometry
    for beh in ('hrm_left', 'hrm_right'):
        m = re.search(beh + r'.*?hold-trigger-key-positions = <([^>]*)>;', head, re.S)
        if m:
            new = ' '.join(str(x) for x in remap_positions(m.group(1), idxmap))
            head = head[:m.start(1)] + new + head[m.end(1):]

    # drop encoder behaviours on boards with no encoder
    if not has_enc:
        for beh in ('rgb_encoder', 'scroll_encoder'):
            head = re.sub(r'\n    ' + beh + r': .*?\n    \};\n', '\n', head, flags=re.S)

    body = [head, '    keymap {', '        compatible = "zmk,keymap";', '']

    for li, (lname, lbind, lmeta) in enumerate(corne_layers):
        assert len(lbind) == 48, f"corne layer {lname} has {len(lbind)}"
        ob = orig[li][1] if li < len(orig) else None

        row = []
        for tgt_i, src in enumerate(idxmap):
            if src is O:
                row.append(ob[tgt_i] if ob and tgt_i < len(ob) else '&trans')
            else:
                row.append(lbind[src])

        body.append(f'        {lname} {{')
        body.extend(layer_meta(lmeta, lname))
        body.append('            bindings = <')
        k = 0
        for w in widths:
            body.append('  ' + '  '.join(row[k:k + w]))
            k += w
        body.append('            >;')

        if has_enc:
            sb = sensor_of(lmeta)
            if sb:
                body.append(f'            sensor-bindings = <{sb}>;')
        body.append('        };')
        body.append('')

    body.append('    };')
    body.append('};')

    open(path, 'w').write('\n'.join(body) + '\n')
    kept = sum(1 for x in idxmap if x is O)
    print(f"  {fname:24s} {nkeys} keys  ({nkeys - kept} from corne, {kept} kept as-is)")


def main():
    csrc = open(os.path.join(CONFIG, 'eyeslash_corne.keymap')).read()
    cl = parse_layers(os.path.join(CONFIG, 'eyeslash_corne.keymap'))
    print(f"Corne base: {len(cl)} layers x {len(cl[0][1])} keys")
    for t in TARGETS:
        emit(t, cl, csrc)


if __name__ == '__main__':
    main()
