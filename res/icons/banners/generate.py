import re, sys, os
sys.path.insert(0, os.path.expanduser("~/tmp/logo-concepts/r2"))
from tt import TT

ICON = os.path.expanduser("~/git/santoku-docs/res/icons/icon.svg")
FONT = os.path.expanduser("~/tmp/logo-concepts/r2/roboto-500Medium.ttf")

src = open(ICON).read()
defs = re.search(r"<defs>(.*)</defs>", src, re.S).group(1)
knife = re.search(r'(<g transform="translate\(-6 2\).*</g>)</g></svg>', src, re.S).group(1)
assert knife.count("<g") == knife.count("</g>"), "knife group tags unbalanced"

f = TT(FONT)

MARK = 64.0
GAP = 18.0
GAP_R = GAP * 1.5
ROW1, ROW1_SIZE, ROW1_TRACK, ROW1_CY = "SANTOKU", 11.0, 0.14, 21.0
ROW2_SIZE, ROW2_TRACK, ROW2_CY = 23.0, 0.005, 40.5
COL1, COL2 = "#93a7c0", "#ffffff"

def ink(txt, size, track):
    sc = size / f.upem
    pen, xs = 0.0, []
    for ch in txt:
        g = f.gid(ch)
        x0, _, x1, _ = f.bbox(g)
        if x1 > x0:
            xs += [x0 * sc + pen * sc, x1 * sc + pen * sc]
        pen += f.adv(g) + track * f.upem
    return (min(xs), max(xs)) if xs else (0.0, 0.0)

def ink_width(txt, size, track):
    lo, hi = ink(txt, size, track)
    return hi - lo

def uniquify(svg, uid):
    ids = set(re.findall(r'id="([^"]+)"', svg))
    for i in sorted(ids, key=len, reverse=True):
        svg = svg.replace('id="%s"' % i, 'id="%s-%s"' % (i, uid))
        svg = svg.replace('url(#%s)' % i, 'url(#%s-%s)' % (i, uid))
    return svg

def banner(libname):
    left = MARK + GAP
    w1 = ink_width(ROW1, ROW1_SIZE, ROW1_TRACK)
    w2 = ink_width(libname, ROW2_SIZE, ROW2_TRACK)
    w = left + max(w1, w2) + GAP_R
    p1 = f.place(ROW1, ROW1_SIZE, ROW1_TRACK, left=left, cy=ROW1_CY)
    p2 = f.place(libname, ROW2_SIZE, ROW2_TRACK, left=left, cy=ROW2_CY)
    svg = (
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.2f 64" width="%.2f" height="64">'
      '<defs>%s<clipPath id="bn"><rect width="%.2f" height="64" rx="14"/></clipPath>'
      '<clipPath id="kn"><rect width="64" height="64"/></clipPath></defs>'
      '<g clip-path="url(#bn)"><rect width="%.2f" height="64" fill="url(#gt)"/>'
      '<g clip-path="url(#kn)">%s</g>'
      '<path fill="%s" d="%s"/><path fill="%s" d="%s"/></g></svg>'
    ) % (w, w, defs, w, w, knife, COL1, p1, COL2, p2)
    return uniquify(svg, re.sub(r'[^a-z0-9]+', '', libname))

def gaps(libname):
    left = MARK + GAP
    w1 = ink_width(ROW1, ROW1_SIZE, ROW1_TRACK)
    w2 = ink_width(libname, ROW2_SIZE, ROW2_TRACK)
    wide = max(w1, w2)
    w = left + wide + GAP_R
    return left - MARK, w - (left + wide), w
