"""Tether Sans and Tether Display: cut from Inter 4 (Rasmus Andersson, SIL Open Font License 1.1, no reserved name),
renamed. Inter is drawn in the spirit of San Francisco and splits its optical sizes the same way: Sans is the text cut
(opsz 14, like SF Pro Text), Display the headline cut (opsz 32, like SF Pro Display). Figures stay proportional.
Same method as Mailbag Sans (mailbag/scripts/gen_font.py): pinned release, renamed, OFL beside the fonts, original
copyright kept, fixed timestamps so every build is the same bytes.

    uv run --with fonttools --with brotli scripts/gen_font.py           # fonts/ and web/fonts/
    uv run --with fonttools --with brotli scripts/gen_font.py --check
"""
import io
import os
import shutil
import sys
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT, WEB = os.path.join(HERE, "fonts"), os.path.join(HERE, "web", "fonts")
SOURCE = "https://cdn.jsdelivr.net/npm/@fontsource-variable/inter@5.2.8/"
VARIABLE = "files/inter-latin-opsz-normal.woff2"   # axes: opsz 14-32, wght 100-900
WEIGHTS = {"Regular": 400, "Medium": 500, "Semibold": 600, "Bold": 700}


def fetch(path):
    with urllib.request.urlopen(SOURCE + path, timeout=60) as r:
        return r.read()


def rename(font, family, style):
    """Copyright (0), license (13, 14) and axis names (256 up) stay; everything else says Tether."""
    ps = family.replace(" ", "")
    names = {1: family, 2: style, 3: f"{ps}-{style}", 4: f"{family} {style}", 5: "Version 1.000",
             6: f"{ps}-{style}", 16: family, 17: style}
    table = font["name"]
    table.names = [n for n in table.names if n.nameID in (0, 13, 14) or n.nameID >= 256]
    for nid, text in names.items():
        table.setName(text, nid, 3, 1, 0x409)
        table.setName(text, nid, 1, 0, 0)
    font["head"].created = font["head"].modified = 3_700_000_000
    font["OS/2"].achVendID = "TTHR"


def check():
    assert os.path.exists(os.path.join(OUT, "OFL.txt")), "the OFL must ship with the fonts"
    for style in WEIGHTS:
        f = TTFont(os.path.join(OUT, f"TetherSans-{style}.ttf"))
        assert f["name"].getDebugName(1) == "Tether Sans" and f["name"].getDebugName(6) == f"TetherSans-{style}"
        assert f["name"].getDebugName(0), "the original copyright must stay"
        assert f["hmtx"]["one"][0] < f["hmtx"]["zero"][0], "figures must stay proportional"
    assert "fvar" in TTFont(os.path.join(WEB, "TetherDisplay.woff2")), "the web display cut keeps its weight axis"
    assert TTFont(os.path.join(OUT, "TetherDisplay-Bold.ttf"))["name"].getDebugName(1) == "Tether Display"
    print("font ok: Tether Sans (4 weights) and Tether Display, Inter text and display cuts, OFL, proportional figures")


def main():
    if "--check" in sys.argv:
        return check()
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(WEB, exist_ok=True)
    with open(os.path.join(OUT, "OFL.txt"), "wb") as f:
        f.write(fetch("LICENSE"))
    shutil.copy(os.path.join(OUT, "OFL.txt"), WEB)
    source = fetch(VARIABLE)
    cut = lambda axes: instancer.instantiateVariableFont(TTFont(io.BytesIO(source)), axes)
    for style, weight in WEIGHTS.items():
        font = cut({"opsz": 14, "wght": weight})
        rename(font, "Tether Sans", style)
        font.save(os.path.join(OUT, f"TetherSans-{style}.ttf"), reorderTables=False)
        font.flavor = "woff2"
        font.save(os.path.join(WEB, f"TetherSans-{style}.woff2"), reorderTables=False)
    bold = cut({"opsz": 32, "wght": 700})
    rename(bold, "Tether Display", "Bold")
    bold.save(os.path.join(OUT, "TetherDisplay-Bold.ttf"), reorderTables=False)
    web = cut({"opsz": 32})   # the web keeps the weight axis
    rename(web, "Tether Display", "Regular")
    web.flavor = "woff2"
    web.save(os.path.join(WEB, "TetherDisplay.woff2"), reorderTables=False)
    print("Tether Sans 400-700 and Tether Display written")


if __name__ == "__main__":
    main()
