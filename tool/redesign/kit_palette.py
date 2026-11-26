"""tool/redesign/kit_palette.py - the redesign kit's palette, derived from the two logo seeds (KIT_SPEC.md section 1).

    py -3.12 tool/redesign/kit_palette.py            # the markdown tables of KIT_SPEC.md section 1
    py -3.12 tool/redesign/kit_palette.py --json     # the `kit` map (theme field names) -> tool/redesign/kit_palette.json
    py -3.12 tool/redesign/kit_palette.py --check    # exit 1 when a pair is under its contrast floor

Everything is computed: change a seed or a rule here, run it again, and copy the JSON into
lib/config/theme/kit_palette_defaults.dart and (back) features/platform/theme_kit_defaults.py. The functional colours
(the six accents, subjects, status) are shared by every product that uses this code; the brand block is this product's.
"""
from __future__ import annotations

import colorsys
import json
import os
import sys

WHITE = "#FFFFFF"
AA = 4.5

# ── seeds (assets/images/logo.png) ──────────────────────────────────────────
GREEN = "#186848"
GOLD = "#C08838"

# ── shared functional colours (DESIGN_SYSTEM 1.4) ───────────────────────────
ACCENTS = {"sun": "#FFC53D", "mint": "#19C29B", "grape": "#7A4DF0", "pink": "#FF5FA2", "lime": "#9BD728",
           "sky": "#3DA5FF"}
# (tint, ink) as the design gives them; an ink under the floor is darkened by the script and reported
ACCENT_GIVEN = {"sun": ("#FFF4CC", "#7A5200"), "mint": ("#D9F7EE", "#0C6B55"), "grape": ("#ECE5FF", "#4A28B8"),
                "pink": ("#FFE3EF", "#A81E5E"), "lime": ("#EEF9D2", "#4C6B05"), "sky": ("#E0F0FF", "#0F5CA8")}
SUBJECTS = {"math": "#FF7A59", "physics": "#7A4DF0", "chem": "#19C29B", "bio": "#2FB5A8", "english": "#07B8EE",
            "arabic": "#0F6E6D", "qudurat": "#FFB020", "code": "#1979C1", "quran": "#1D9A63", "islamic": "#B7791F",
            "other": "#64748B"}
SUBJECT_GIVEN = {"math": ("#FFEAE4", "#A8381C"), "physics": ("#EAE3FD", "#4A28B8"), "chem": ("#DAF5EF", "#0C6B55"),
                 "bio": ("#DEF3F1", "#126B63"), "english": ("#D7F4FC", "#06678A"), "arabic": ("#D9E8E8", "#0F6E6D"),
                 "qudurat": ("#FFF2DB", "#7A5200"), "code": ("#DAEAF5", "#135F9A"), "quran": ("#DBEFE6", "#11633F"),
                 "islamic": ("#F3EADB", "#7A4F10")}
LIVE, ERROR, LOCK = "#F2545B", "#C2410C", "#C9D6E6"
LIVE_GIVEN = ("#FFE3E0", "#B23A2E")
QURAN_DEEP = "#0F6E6D"
ROLE_SHARED = {"teacher": ("#5F3DC4", "#8B6CF0"), "parent": ("#0B8FB8", "#2FB5A8")}

# dark surfaces stay the theme's neutral grey (D-650)
DARK_BG, DARK_CARD, DARK_TEXT = "#121414", "#1E2021", "#F5EFE6"

FIXED = []   # (what, given ink, used ink): design inks the script had to darken


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hx(t):
    return "#%02X%02X%02X" % tuple(max(0, min(255, round(v))) for v in t)


def mix(a, b, t):
    """a moved t of the way to b (sRGB)."""
    ra, rb = rgb(a), rgb(b)
    return hx(tuple(x + (y - x) * t for x, y in zip(ra, rb)))


def lum(h):
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def cr(a, b):
    la, lb = lum(a), lum(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def hls(h):
    r, g, b = (v / 255 for v in rgb(h))
    return colorsys.rgb_to_hls(r, g, b)


def from_hls(h, l, s):
    return hx(tuple(v * 255 for v in colorsys.hls_to_rgb(h % 1.0, max(0, min(1, l)), max(0, min(1, s)))))


def hue(h):
    return round(hls(h)[0] * 360)


def darken_until(color, against, floor=AA + 0.1):
    """color scaled toward black (hue and saturation kept) until every colour of `against` reads on it at `floor`."""
    c, f = color, 1.0
    while min(cr(c, a) for a in against) < floor and f > 0.05:
        f -= 0.005
        c = hx(tuple(v * f for v in rgb(color)))
    return c


def lighten_until(color, against, floor=AA + 0.1):
    c, t = color, 0.0
    while min(cr(c, a) for a in against) < floor and t < 1:
        t += 0.01
        c = mix(color, WHITE, t)
    return c


def tint_of(color):
    return mix(color, WHITE, 0.86)


def tint_dark(color):
    return mix(DARK_CARD, color, 0.18)


def triple(color, given=None, what=""):
    """colour + tint + ink (+ the dark pair). `given` = the design's own (tint, ink): kept when the ink reads."""
    if given:
        t, ink = given
        used = darken_until(ink, [t, WHITE], AA)
        if used != ink:
            FIXED.append((what, ink, used))
        ink = used
    else:
        t = tint_of(color)
        ink = darken_until(color, [t, WHITE])
    td = tint_dark(color)
    return {"c": color, "tint": t, "ink": ink, "tint_dark": td,
            "ink_dark": lighten_until(color, [td, DARK_CARD])}


# ── brand roles ─────────────────────────────────────────────────────────────
def brand():
    gh, gl, gs = hls(GREEN)
    ink = from_hls(gh, 0.153, 0.62)        # deep green: text on light, hero base (the reference's navy)
    deep = from_hls(gh, 0.09, 0.66)        # darkest green: hero end, player chrome
    partner = from_hls(gh - 4 / 360, 0.41, 0.55)   # a lighter, fresher green: gradients, focus ring
    hot = darken_until(GOLD, [WHITE])      # deep gold: white reads on it
    b = {"ink": ink, "deep": deep, "primary": GREEN, "partner": partner, "warm": GOLD, "hot": hot}
    for k in ("primary", "partner", "warm", "hot"):
        t = triple(b[k])
        b[k + "_tint"], b[k + "_ink"] = t["tint"], t["ink"]
        b[k + "_tint_dark"], b[k + "_ink_dark"] = t["tint_dark"], t["ink_dark"]
    b["page"] = mix(GREEN, WHITE, 0.955)
    b["text"] = from_hls(gh, 0.115, 0.45)
    b["muted"] = darken_until(from_hls(gh, 0.36, 0.12), [b["page"], b["primary_tint"]])
    b["line"] = mix(GREEN, WHITE, 0.86)
    b["well"] = mix(GREEN, WHITE, 0.975)
    b["track"] = mix(GREEN, WHITE, 0.90)
    b["field_edge"] = mix(GREEN, WHITE, 0.78)
    b["top_bar"] = ink
    # the gold kicker line / squiggle on a hero: 4.5 on the ink, 3.0 (large text) on the logo green
    b["warm_on_dark"] = lighten_until(lighten_until(GOLD, [ink], AA), [GREEN], 3.0)
    # the ONE forward button: gold with the deep ink (white is 3.1:1 on the logo gold)
    b["hot_a"], b["hot_b"], b["hot_fg"] = mix(GOLD, WHITE, 0.22), GOLD, deep
    return b


def mint_for(b):
    """Mint sits 10 degrees from the brand green: move it to 174 (teal) so success / Quran do not read as brand."""
    h, l, s = hls(ACCENTS["mint"])
    return from_hls(174 / 360, l, s)


def hero_mid(hero_a, br, yellow):
    """The hero's middle stop (45 %): the accent darkened until white reads on it at 6:1, then moved toward the deep
    green ink: 30 % for cool accents, 12 % for the yellow family (yellow + green at 30 % is olive mud; it stays a
    bronze, a grade of gold)."""
    return mix(darken_until(hero_a, [WHITE], 6.0), br["ink"], 0.12 if yellow else 0.30)


def accent_set(a, b_, br, light_fg=False, hero_a=None, yellow=False, given=None, what=""):
    """One area / role: accent pair, hero stops, tint, ink, button stops and its text."""
    hero_a = hero_a or a
    mid = hero_mid(hero_a, br, yellow)
    tr = triple(a, given, what)
    if light_fg:
        fg = br["deep"]
        ba, bb = a, b_
        if cr(bb, fg) < AA:
            bb = lighten_until(bb, [fg])
        if cr(ba, fg) < AA:
            ba = lighten_until(ba, [fg])
    else:
        fg = WHITE
        ba, bb = darken_until(a, [WHITE]), darken_until(b_, [WHITE])
    return {"a": a, "b": b_, "hero_a": hero_a, "hero_mid": mid, "tint": tr["tint"], "ink": tr["ink"],
            "tint_dark": tr["tint_dark"], "ink_dark": tr["ink_dark"], "btn_a": ba, "btn_b": bb, "btn_fg": fg}


def build():
    FIXED.clear()
    br = brand()
    acc = dict(ACCENTS)
    acc["mint"] = mint_for(br)
    A = acc
    G = dict(ACCENT_GIVEN)
    G["mint"] = None          # this product's mint is moved: its tint and ink are derived
    accents = {k: triple(v, G[k], f"accent {k}") for k, v in acc.items()}
    P, PT, W, H = br["primary"], br["partner"], br["warm"], br["hot"]
    areas = {
        "home": accent_set(P, PT, br, hero_a=PT),
        "learn": accent_set(W, H, br, light_fg=True, yellow=True),
        "exam": accent_set(A["grape"], P, br, given=G["grape"]),
        "games": accent_set(A["grape"], A["pink"], br, given=G["grape"]),
        "store": accent_set(A["sun"], W, br, light_fg=True, yellow=True, given=G["sun"]),
        "quran": accent_set(A["mint"], QURAN_DEEP, br),
        "nahw": accent_set(A["lime"], A["mint"], br, light_fg=True, given=G["lime"]),
        "sched": accent_set(A["sky"], A["mint"], br, given=G["sky"]),
        "chat": accent_set(A["pink"], W, br, given=G["pink"]),
        "money": accent_set(A["sun"], A["mint"], br, light_fg=True, yellow=True, given=G["sun"]),
        "me": accent_set(P, A["grape"], br, hero_a=PT),
    }
    # learn's button IS the hot button
    areas["learn"]["btn_a"], areas["learn"]["btn_b"] = br["hot_a"], br["hot_b"]
    roles = {
        "teacher": accent_set(*ROLE_SHARED["teacher"], br),
        "parent": accent_set(*ROLE_SHARED["parent"], br),
        "admin": accent_set(P, W, br, hero_a=PT),
        "super": accent_set(H, W, br, yellow=True),
    }
    subjects = {}
    for k, c in SUBJECTS.items():
        t = triple(c, SUBJECT_GIVEN.get(k), f"subject {k}")
        t["fg"] = WHITE if cr(c, WHITE) >= 3 else br["deep"]
        subjects[k] = t
    live_t = triple(LIVE, LIVE_GIVEN, "status live")
    ok, warn = accents["mint"], accents["sun"]
    err = triple(ERROR)
    status = {
        "live": LIVE, "live_fill": darken_until(LIVE, [WHITE]), "live_tint": live_t["tint"], "live_ink": live_t["ink"],
        "live_tint_dark": live_t["tint_dark"], "live_ink_dark": live_t["ink_dark"],
        "ok": acc["mint"], "ok_tint": ok["tint"], "ok_ink": ok["ink"], "ok_tint_dark": ok["tint_dark"],
        "ok_ink_dark": ok["ink_dark"],
        "warn": acc["sun"], "warn_tint": warn["tint"], "warn_ink": warn["ink"], "warn_tint_dark": warn["tint_dark"],
        "warn_ink_dark": warn["ink_dark"],
        "lock": LOCK, "lock_ink": darken_until("#7C8CA3", [WHITE, mix(LOCK, WHITE, 0.6)]),
        "lock_dark": "#3A4046", "lock_ink_dark": "#A9B4C2",
        "error": ERROR, "error_ink": err["ink"], "error_tint": err["tint"], "error_tint_dark": err["tint_dark"],
        "error_ink_dark": err["ink_dark"],
    }
    return {"v": 1, "brand": br, "accents": accents, "status": status, "areas": areas, "roles": roles,
            "subjects": subjects}


# ── reference design values (kit.css), for the comparison column only ──────
REF = {"ink": "#00205E", "deep": "#001440", "primary": "#1979C1", "primary_tint": "#E2EFFA", "primary_ink": "#135F9A",
       "partner": "#07B8EE", "partner_tint": "#DDF6FE", "partner_ink": "#06678A", "warm": "#FF9F5A",
       "warm_tint": "#FFE8D6", "warm_ink": "#A3480A", "hot": "#F2545B", "hot_tint": "#FFE3E0", "hot_ink": "#B23A2E",
       "page": "#F3F8FD", "text": "#0E2350", "muted": "#4A5878", "line": "#E2EAF4", "well": "#F8FBFE",
       "track": "#EAF0F6", "field_edge": "#D5E3F2", "top_bar": "#001A4E", "hot_a": "#FF9F5A", "hot_b": "#F2545B",
       "hot_fg": "#FFFFFF", "warm_on_dark": "#FF9F5A"}
REF_AREAS = {"home": ("#1979C1", "#07B8EE", "#1979C1", "#093F81"), "learn": ("#FF9F5A", "#F2545B", "#FF8A4C", "#7A2E5E"),
             "exam": ("#7A4DF0", "#1979C1", "#7A4DF0", "#2B3091"), "games": ("#7A4DF0", "#FF5FA2", "#8E4DF0", "#3A1F8F"),
             "store": ("#FFC53D", "#FF9F5A", "#FF9F5A", "#8C2F5A"), "quran": ("#19C29B", "#0F6E6D", "#19C29B", "#0A5C6E"),
             "nahw": ("#9BD728", "#19C29B", "#8BCB1E", "#1F6B55"), "sched": ("#3DA5FF", "#07B8EE", "#3DA5FF", "#154F96"),
             "chat": ("#FF5FA2", "#FF9F5A", "#FF5FA2", "#6A2E7E"), "money": ("#FFC53D", "#19C29B", "#FFB020", "#A0442A"),
             "me": ("#1979C1", "#7A4DF0", "#4F6BE8", "#2E2A8C")}


def checks(k):
    """(label, fg, bg, floor) for every pair that carries text."""
    br, st = k["brand"], k["status"]
    rows = [("text on page", br["text"], br["page"], AA), ("text on white", br["text"], WHITE, AA),
            ("muted on page", br["muted"], br["page"], AA), ("muted on white", br["muted"], WHITE, AA),
            ("muted on well", br["muted"], br["well"], AA), ("muted on primary tint", br["muted"], br["primary_tint"], AA),
            ("ink (navy role) on white", br["ink"], WHITE, AA),
            ("white on primary", WHITE, br["primary"], AA), ("white on ink", WHITE, br["ink"], AA),
            ("white on deep", WHITE, br["deep"], AA), ("white on hot", WHITE, br["hot"], AA),
            ("hot_fg on hot_a", br["hot_fg"], br["hot_a"], AA), ("hot_fg on hot_b", br["hot_fg"], br["hot_b"], AA),
            ("warm_on_dark on ink (kicker on a hero)", br["warm_on_dark"], br["ink"], AA),
            ("warm_on_dark on primary (large text)", br["warm_on_dark"], br["primary"], 3.0),
            ("white on live_fill (count badge)", WHITE, st["live_fill"], AA),
            ("error on white", st["error"], WHITE, AA),
            ("error_ink on error tint", st["error_ink"], st["error_tint"], AA),
            ("lock_ink on white", st["lock_ink"], WHITE, AA)]
    for n in ("primary", "partner", "warm", "hot"):
        rows += [(f"{n}_ink on white", br[n + "_ink"], WHITE, AA), (f"{n}_ink on {n}_tint", br[n + "_ink"], br[n + "_tint"], AA),
                 (f"{n}_ink_dark on {n}_tint_dark", br[n + "_ink_dark"], br[n + "_tint_dark"], AA)]
    for n in ("live", "ok", "warn"):
        rows += [(f"{n}_ink on white", st[n + "_ink"], WHITE, AA), (f"{n}_ink on {n}_tint", st[n + "_ink"], st[n + "_tint"], AA),
                 (f"{n}_ink_dark on {n}_tint_dark", st[n + "_ink_dark"], st[n + "_tint_dark"], AA)]
    for n, t in k["accents"].items():
        rows += [(f"{n} ink on white", t["ink"], WHITE, AA), (f"{n} ink on tint", t["ink"], t["tint"], AA),
                 (f"{n} ink_dark on tint_dark", t["ink_dark"], t["tint_dark"], AA)]
    for grp in ("areas", "roles"):
        for n, a in k[grp].items():
            rows += [(f"{grp[:-1]} {n}: white on hero_mid", WHITE, a["hero_mid"], AA),
                     (f"{grp[:-1]} {n}: btn_fg on btn_a", a["btn_fg"], a["btn_a"], AA),
                     (f"{grp[:-1]} {n}: btn_fg on btn_b", a["btn_fg"], a["btn_b"], AA),
                     (f"{grp[:-1]} {n}: ink on tint", a["ink"], a["tint"], AA)]
    for n, t in k["subjects"].items():
        rows += [(f"subject {n}: ink on tint", t["ink"], t["tint"], AA), (f"subject {n}: ink on white", t["ink"], WHITE, AA),
                 (f"subject {n}: fg on colour (cover label, large)", t["fg"], t["c"], 3.0),
                 (f"subject {n}: ink_dark on tint_dark", t["ink_dark"], t["tint_dark"], AA)]
    return rows


def md(k):
    br = k["brand"]
    out = []
    out.append("#### Brand roles\n")
    out.append("| Role (theme key `kit.brand.*`) | NextBrain | Reference design (kit.css) |\n|---|---|---|")
    for key in ("ink", "deep", "primary", "primary_tint", "primary_ink", "partner", "partner_tint", "partner_ink", "warm",
                "warm_tint", "warm_ink", "hot", "hot_tint", "hot_ink", "hot_a", "hot_b", "hot_fg", "page", "text", "muted",
                "line", "well", "track", "field_edge", "top_bar", "warm_on_dark"):
        out.append(f"| `{key}` | `{br[key]}` | `{REF[key]}` |")
    out.append("\n#### Brand roles, dark mode\n")
    out.append("| Key | NextBrain |\n|---|---|")
    for n in ("primary", "partner", "warm", "hot"):
        out.append(f"| `{n}_tint_dark` / `{n}_ink_dark` | `{br[n + '_tint_dark']}` / `{br[n + '_ink_dark']}` |")
    out.append("\n#### Accents (`kit.accents.<name>`)\n")
    out.append("| Accent | `c` | `tint` | `ink` | `tint_dark` | `ink_dark` | hue |\n|---|---|---|---|---|---|---|")
    for n, t in k["accents"].items():
        out.append(f"| {n} | `{t['c']}` | `{t['tint']}` | `{t['ink']}` | `{t['tint_dark']}` | `{t['ink_dark']}` | {hue(t['c'])} |")
    out.append("\n#### Status (`kit.status.*`)\n")
    out.append("| Key | Value |\n|---|---|")
    for key, v in k["status"].items():
        out.append(f"| `{key}` | `{v}` |")
    for grp, title in (("areas", "Areas (`kit.areas.<area>`), hero end stop = `kit.brand.deep`"),
                       ("roles", "Role accents (`kit.roles.<role>`)")):
        out.append(f"\n#### {title}\n")
        out.append("| | `a` | `b` | `hero_a` | `hero_mid` | `tint` | `ink` | `btn_a` | `btn_b` | `btn_fg` | `tint_dark` | `ink_dark` |"
                   "\n|---|---|---|---|---|---|---|---|---|---|---|---|")
        for n, a in k[grp].items():
            out.append(f"| {n} | " + " | ".join(f"`{a[c]}`" for c in ("a", "b", "hero_a", "hero_mid", "tint", "ink", "btn_a",
                                                                      "btn_b", "btn_fg", "tint_dark", "ink_dark")) + " |")
    out.append("\n#### Reference design areas (kit.css), for comparison\n")
    out.append("| | `a` | `b` | `hero_a` | `hero_mid` |\n|---|---|---|---|---|")
    for n, a in REF_AREAS.items():
        out.append(f"| {n} | " + " | ".join(f"`{c}`" for c in a) + " |")
    out.append("\n#### Subjects (`kit.subjects.<key>`)\n")
    out.append("| Subject | `c` | `tint` | `ink` | `fg` | `tint_dark` | `ink_dark` |\n|---|---|---|---|---|---|---|")
    for n, t in k["subjects"].items():
        out.append(f"| {n} | `{t['c']}` | `{t['tint']}` | `{t['ink']}` | `{t['fg']}` | `{t['tint_dark']}` | `{t['ink_dark']}` |")
    out.append("\n#### Contrast (WCAG 2.1 ratio; floor 4.5 unless noted)\n")
    out.append("| Pair | fg | bg | ratio | floor | |\n|---|---|---|---|---|---|")
    for label, fg, bg, floor in checks(k):
        r = cr(fg, bg)
        out.append(f"| {label} | `{fg}` | `{bg}` | {r:.2f} | {floor} | {'ok' if r >= floor else 'FAIL'} |")
    if FIXED:
        out.append("\nDesign inks darkened to reach 4.5 on their own tint: "
                   + "; ".join(f"{w} `{a}` -> `{b}`" for w, a, b in FIXED) + ".")
    out.append(f"\nHues: brand green {hue(GREEN)}, partner {hue(br['partner'])}, mint (shared value) {hue(ACCENTS['mint'])}, "
               f"mint (this product) {hue(k['accents']['mint']['c'])}, lime {hue(ACCENTS['lime'])}, gold {hue(GOLD)}, "
               f"sun {hue(ACCENTS['sun'])}.")
    return "\n".join(out)


def main():
    k = build()
    if "--json" in sys.argv:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kit_palette.json")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(k, f, indent=2)
            f.write("\n")
        print(path)
        return 0
    rows = checks(k)
    bad = [(l, fg, bg, cr(fg, bg), fl) for l, fg, bg, fl in rows if cr(fg, bg) < fl]
    if "--check" in sys.argv:
        for row in bad:
            print("FAIL %s: %s on %s = %.2f (< %s)" % row)
        print("%d pairs checked, %d under the floor" % (len(rows), len(bad)))
        return 1 if bad else 0
    sys.stdout.reconfigure(encoding="utf-8")
    print(md(k))
    return 0


if __name__ == "__main__":
    sys.exit(main())
