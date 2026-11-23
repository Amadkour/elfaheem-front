"""Reference grader for Games v4 (CONTRACT sections 5-7) and the generator of grading_vectors_v4.json.
Planner tool only (T01): the app code is written by T22 (Python) and T12 (Dart) against the JSON it writes."""
import json
import sys
from datetime import date

MIN_STEP_MS = 400
MAX_TRACE = 500
PROGRAM_RUNS = 3
MAX_STEPS = 200
PAR_S = {"mcq": 12, "true_false": 8, "select_all": 15, "sequence": 4, "classify": 5, "pair": 6, "fraction": 20,
         "program": 45, "combine": 15}
PER_UNIT = ("sequence", "classify", "pair")
DIFF = {"easy": 100, "medium": 125, "hard": 150}
ENDS = ("done", "timer", "lives", "quit")
NO_BONUS_TEMPLATES = ("growing_tree",)


class Bad(ValueError):
    pass


def _int(v, lo, hi, why):
    if isinstance(v, bool) or not isinstance(v, int) or not lo <= v <= hi:
        raise Bad(why)
    return v


def _ints(v, n, why, lo_len=0, hi_len=99):
    if not isinstance(v, list) or not lo_len <= len(v) <= hi_len:
        raise Bad(why)
    out = [_int(x, 0, n - 1, why) for x in v]
    if len(set(out)) != len(out):
        raise Bad(why)
    return out


def item_max(it):
    t, b = it["type"], it["body"]
    if t == "select_all":
        return len(b["answers"])
    if t == "sequence":
        return len(b["blanks"])
    if t == "classify":
        return len(b["tokens"]) + sum(1 for x in b["tokens"] if x.get("case") is not None)
    if t == "pair":
        return len(b["pairs"])
    if t == "program":
        return 2
    return 1


def item_par_s(it):
    t = it["type"]
    return PAR_S[t] * (item_max(it) if t in PER_UNIT else 1)


def _flat_len(cmds):
    n = 0
    for c in cmds:
        n += 1 + (len(c["do"]) if isinstance(c, dict) else 0)
    return n


def check_program(b, a):
    if not isinstance(a, list) or not 1 <= len(a) <= 60:
        raise Bad("program")
    allowed = b["cmds"]
    for c in a:
        if isinstance(c, str):
            if c not in ("F", "L", "R") or c not in allowed:
                raise Bad("program_cmd")
        elif isinstance(c, dict):
            if "LOOP" not in allowed or set(c) != {"loop", "do"}:
                raise Bad("program_cmd")
            _int(c["loop"], 2, 9, "program_loop")
            if not isinstance(c["do"], list) or not 1 <= len(c["do"]) <= 10:
                raise Bad("program_loop")
            for d in c["do"]:
                if not isinstance(d, str) or d not in ("F", "L", "R") or d not in allowed:
                    raise Bad("program_cmd")
        else:
            raise Bad("program_cmd")
    if _flat_len(a) > 60:
        raise Bad("program")


def simulate(b, a):
    """-> {reached, bumped, steps, length, x, y, dir, points}"""
    x, y, d = b["start"]
    gx, gy = b["goal"]
    walls = {tuple(w) for w in b["walls"]}
    flat = []
    for c in a:
        if isinstance(c, dict):
            flat += c["do"] * c["loop"]
        else:
            flat.append(c)
    steps, reached, bumped = 0, False, False
    for c in flat:
        if steps >= MAX_STEPS:
            break
        steps += 1
        if c == "L":
            d = (d + 3) % 4
        elif c == "R":
            d = (d + 1) % 4
        else:
            nx, ny = x + (0, 1, 0, -1)[d], y + (-1, 0, 1, 0)[d]
            if not (0 <= nx < b["w"] and 0 <= ny < b["h"]) or (nx, ny) in walls:
                bumped = True
                break
            x, y = nx, ny
            if (x, y) == (gx, gy):
                reached = True
                break
    length = _flat_len(a)
    pts = 0
    if reached and length <= b["max"]:
        pts = 2 if length <= b["par"] else 1
    return {"reached": reached, "bumped": bumped, "steps": steps, "length": length, "x": x, "y": y, "dir": d,
            "points": pts}


def check_a(it, a):
    """Shape and range of one entry's `a`; -> a unit key (what `first try` is counted by)."""
    t, b = it["type"], it["body"]
    if t == "mcq":
        _int(a, 0, len(b["options"]) - 1, "option")
        return "x"
    if t == "true_false":
        _int(a, 0, 1, "bool")
        return "x"
    if t == "select_all":
        _ints(a, len(b["options"]), "options")
        return "x"
    if t == "sequence":
        if not isinstance(a, list) or len(a) != 2:
            raise Bad("slot")
        slot = _int(a[0], 0, len(b["tokens"]) - 1, "slot")
        if slot not in b["blanks"]:
            raise Bad("slot")
        _int(a[1], 0, len(b["tokens"]) + len(b.get("extra") or []) - 1, "token")
        return "s%d" % slot
    if t == "classify":
        if not isinstance(a, list) or len(a) not in (2, 3):
            raise Bad("classify")
        tok = _int(a[0], 0, len(b["tokens"]) - 1, "token")
        _int(a[1], 0, len(b["buckets"]) - 1, "bucket")
        if len(a) == 3:
            if not b.get("cases") or b["tokens"][tok].get("case") is None:
                raise Bad("case")
            _int(a[2], 0, len(b["cases"]) - 1, "case")
            return "c%d" % tok
        return "b%d" % tok
    if t == "pair":
        if not isinstance(a, list) or len(a) != 2:
            raise Bad("pair")
        ia = _int(a[0], 0, len(b["pairs"]) - 1, "pair")
        _int(a[1], 0, len(b["pairs"]) - 1, "pair")
        return "p%d" % ia
    if t == "fraction":
        if not isinstance(a, list) or len(a) != 2:
            raise Bad("fraction")
        _int(a[0], 0, 999, "fraction")
        _int(a[1], 1, 999, "fraction")
        return "x"
    if t == "program":
        check_program(b, a)
        return "x"
    if t == "combine":
        _ints(a, len(b["ingredients"]), "ingredients", 1)
        return "x"
    raise Bad("type")


def unit_points(it, a):
    t, b = it["type"], it["body"]
    if t == "mcq":
        return int(a == b["answer"])
    if t == "true_false":
        return int(bool(a) == bool(b["answer"]))
    if t == "select_all":
        hits = len(set(a) & set(b["answers"]))
        return max(0, hits - (len(set(a)) - hits))
    if t == "sequence":
        slot, tok = a
        return int(tok < len(b["tokens"]) and b["eq"][tok] == b["eq"][slot])
    if t == "classify":
        tok = b["tokens"][a[0]]
        if len(a) == 3:
            return int(b["cases"][a[2]]["key"] == tok["case"])
        return int(b["buckets"][a[1]]["key"] == tok["bucket"])
    if t == "pair":
        return int(a[0] == a[1])
    if t == "fraction":
        if "op" in b:
            (an, ad), (bn, bd) = b["a"], b["b"]
            rn = an * bd + bn * ad if b["op"] == "add" else an * bd - bn * ad
            rd = ad * bd
        else:
            rn, rd = b["n"], b["d"]
        return int(a[0] * rd == rn * a[1])
    if t == "combine":
        return int({b["ingredients"][k]["key"] for k in a} == set(b["answer"]))
    raise Bad("type")


def grade(items, trace):
    """-> dict(score, max, counted, duration_ms, end, per_item, ghost); raises Bad for a refused trace."""
    if not isinstance(trace, list) or not trace or len(trace) > MAX_TRACE:
        raise Bad("trace")
    n = len(items)
    prev, end = 0, "done"
    seen = set()
    runs = {}
    per = [0] * n
    counted = 0
    ghost = []
    for pos, e in enumerate(trace):
        if not isinstance(e, dict):
            raise Bad("entry")
        ms = e.get("ms")
        if isinstance(ms, bool) or not isinstance(ms, int) or ms < prev:
            raise Bad("ms")
        prev = ms
        i = e.get("i")
        if isinstance(i, bool) or not isinstance(i, int) or not -1 <= i < n:
            raise Bad("i")
        if i == -1:
            if pos != len(trace) - 1 or e.get("a") not in ENDS:
                raise Bad("end")
            end = e["a"]
            continue
        it = items[i]
        unit = check_a(it, e.get("a"))
        if it["type"] == "program":
            k = runs.get(i, 0)
            if k >= PROGRAM_RUNS:
                continue
            runs[i] = k + 1
            pts = 0 if e.get("h") is True else simulate(it["body"], e["a"])["points"]
            if k == 0:
                counted += 1
                ghost.append([ms, int(pts > 0)])
            per[i] = max(per[i], pts)
            continue
        if (i, unit) in seen:
            continue
        seen.add((i, unit))
        counted += 1
        pts = 0 if e.get("h") is True else unit_points(it, e["a"])
        per[i] += pts
        ghost.append([ms, int(pts > 0)])
    if counted == 0:
        raise Bad("empty")
    return {"score": sum(per), "max": sum(item_max(x) for x in items), "counted": counted, "duration_ms": prev,
            "end": end, "per_item": per, "ghost": ghost[:200]}


def stars(score, mx):
    if mx <= 0:
        return 0
    return 3 if score * 10 >= mx * 9 else 2 if score * 10 >= mx * 6 else 1 if score * 10 >= mx * 3 else 0


def rank_points(items, score, mx, d_ms, difficulty, sacred, template):
    if stars(score, mx) == 0:
        return 0
    base = (200 * score + mx) // (2 * mx)
    par_ms = sum(item_par_s(x) for x in items) * 1000
    bonus = 0 if sacred or template in NO_BONUS_TEMPLATES else max(0, 200 - (100 * d_ms) // par_ms)
    return (base * DIFF[difficulty] * (1000 + bonus) + 50000) // 100000


def age_band(dob, grade, today):
    if dob is not None:
        age = today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))
        src = "dob"
    elif grade is not None:
        age, src = grade + 5, "grade"
    else:
        return None, None
    return ("6-9" if age < 10 else "10-13" if age < 14 else "14-17" if age < 18 else "18+"), src


# ── the items used by the cases (snapshot form: CONTRACT section 4) ────────────────────────────────────────────────
L = lambda ar, en: {"ar": ar, "en": en}  # noqa: E731
ITEMS = {
    "mcq_capital": {"type": "mcq", "body": {"options": [{"text": "القاهرة"}, {"text": "الرياض"}, {"text": "عمّان"},
                                                        {"text": "تونس"}], "answer": 0, "show": [2, 0, 3, 1]}},
    "mcq_planet": {"type": "mcq", "body": {"options": [{"text": "Mars"}, {"text": "Venus"}, {"text": "Jupiter"}],
                                           "answer": 2, "show": [1, 2, 0]}},
    "tf_water": {"type": "true_false", "body": {"answer": True}},
    "tf_sun": {"type": "true_false", "body": {"answer": False}},
    "sel_even": {"type": "select_all", "body": {"options": [{"text": "2"}, {"text": "3"}, {"text": "4"}, {"text": "7"},
                                                            {"text": "8"}], "answers": [0, 2, 4],
                                                "show": [4, 1, 0, 3, 2]}},
    # Al-Ikhlas 112:1 as the server resolves it (4 words) + 2 distractor words of the same surah
    "seq_112_1": {"type": "sequence", "sacred": True, "body": {
        "mode": "order", "unit": "word", "tokens": ["قُلْ", "هُوَ", "ٱللَّهُ", "أَحَدٌ"], "eq": [0, 1, 2, 3],
        "blanks": [0, 1, 2, 3], "extra": ["ٱلصَّمَدُ", "كُفُوًا"], "show": [3, 5, 0, 2, 4, 1]}},
    # a repeated word: tokens 0 and 2 are the same string, so they share an eq class and are interchangeable
    "seq_repeat": {"type": "sequence", "body": {
        "mode": "order", "unit": "word", "tokens": ["very", "good", "very", "nice"], "eq": [0, 1, 0, 3],
        "blanks": [0, 1, 2, 3], "extra": [], "show": [1, 3, 0, 2]}},
    "seq_complete": {"type": "sequence", "body": {
        "mode": "complete", "unit": "word", "tokens": ["the", "cat", "sat", "on", "the", "mat"],
        "eq": [0, 1, 2, 3, 0, 5], "blanks": [1, 5], "extra": ["dog"], "show": [6, 5, 1]}},
    "seq_next": {"type": "sequence", "body": {
        "mode": "next_word", "unit": "word", "tokens": ["one", "two", "three", "four", "five"],
        "eq": [0, 1, 2, 3, 4], "blanks": [2, 3, 4], "extra": ["six", "nine"], "show": [3, 6, 2, 5, 4]}},
    "cls_irab": {"type": "classify", "body": {
        "buckets": [{"key": "fail", "label": L("فاعل", "Subject")}, {"key": "fil", "label": L("فعل", "Verb")},
                    {"key": "maful", "label": L("مفعول به", "Object")}],
        "cases": [{"key": "raf", "label": L("رفع", "Raf")}, {"key": "nasb", "label": L("نصب", "Nasb")},
                  {"key": "jarr", "label": L("جرّ", "Jarr")}],
        "tokens": [{"text": "كتبَ", "bucket": "fil", "case": None}, {"text": "الطالبُ", "bucket": "fail", "case": "raf"},
                   {"text": "الدرسَ", "bucket": "maful", "case": "nasb"}], "show": [2, 0, 1]}},
    "cls_animals": {"type": "classify", "body": {
        "buckets": [{"key": "bird", "label": L("طائر", "Bird")}, {"key": "fish", "label": L("سمكة", "Fish")}],
        "cases": None,
        "tokens": [{"text": "Eagle", "bucket": "bird", "case": None}, {"text": "Shark", "bucket": "fish", "case": None},
                   {"text": "Owl", "bucket": "bird", "case": None}], "show": [1, 2, 0]}},
    "pair_caps": {"type": "pair", "body": {"pairs": [{"a": "Egypt", "b": "Cairo"}, {"a": "Jordan", "b": "Amman"},
                                                     {"a": "Tunisia", "b": "Tunis"}],
                                           "show_a": [1, 0, 2], "show_b": [2, 1, 0]}},
    "frac_shape": {"type": "fraction", "body": {"shape": "pizza", "n": 3, "d": 4}},
    "frac_add": {"type": "fraction", "body": {"op": "add", "a": [1, 2], "b": [1, 3]}},
    "frac_sub": {"type": "fraction", "body": {"op": "sub", "a": [3, 4], "b": [1, 4]}},
    # 4 x 4 grid, robot at (0,3) facing north (dir 0), goal (2,1), wall at (0,1)
    "prog_grid": {"type": "program", "body": {"w": 4, "h": 4, "start": [0, 3, 0], "goal": [2, 1], "walls": [[0, 1]],
                                              "cmds": ["F", "L", "R", "LOOP"], "max": 8, "par": 6}},
    "prog_noloop": {"type": "program", "body": {"w": 3, "h": 3, "start": [0, 0, 1], "goal": [2, 0], "walls": [],
                                                "cmds": ["F", "L", "R"], "max": 4, "par": 2}},
    "comb_volcano": {"type": "combine", "body": {
        "ingredients": [{"key": "vinegar", "label": L("خل", "Vinegar")}, {"key": "soda", "label": L("صودا", "Baking soda")},
                        {"key": "water", "label": L("ماء", "Water")}, {"key": "salt", "label": L("ملح", "Salt")}],
        "answer": ["soda", "vinegar"], "fx": "fizz", "result": L("فوران", "Fizzing")}},
}

E = lambda i, a, ms, **k: {"i": i, "a": a, "ms": ms, **k}  # noqa: E731
LOOP = lambda n, do: {"loop": n, "do": do}  # noqa: E731

# name, kind, items, trace, meta (difficulty, template, sacred), expected (None = computed only; else asserted)
CASES = [
    # choose
    ("choose_all_right", "choose", ["mcq_capital", "mcq_planet", "tf_water", "tf_sun"],
     [E(0, 0, 4000), E(1, 2, 9000), E(2, 1, 13000), E(3, 0, 17000)], {}, (4, 4)),
    ("choose_wrong_then_retry", "choose", ["mcq_capital", "mcq_planet", "tf_water", "tf_sun"],
     [E(0, 1, 4000), E(0, 0, 6000), E(1, 2, 9000), E(2, 1, 13000), E(3, 1, 17000), E(3, 0, 19000)], {}, (2, 4)),
    ("choose_timer_ended", "choose", ["mcq_capital", "mcq_planet", "tf_water", "tf_sun"],
     [E(0, 0, 4000), E(1, 0, 20000), E(-1, "timer", 30000)], {}, (1, 4)),
    ("choose_lives_ended", "choose", ["mcq_capital", "mcq_planet", "tf_water", "tf_sun"],
     [E(0, 3, 3000), E(1, 1, 6000), E(2, 0, 9000), E(-1, "lives", 9500)], {}, (0, 4)),
    ("choose_hint_scores_zero", "choose", ["mcq_capital", "tf_water"],
     [E(0, 0, 5000, h=True), E(1, 1, 9000)], {}, (1, 2)),
    ("choose_any_order", "choose", ["mcq_capital", "mcq_planet"], [E(1, 2, 3000), E(0, 0, 8000)], {}, (2, 2)),
    ("choose_bad_option_index", "choose", ["mcq_capital"], [E(0, 4, 3000)], {}, "bad"),
    ("choose_bad_tf_value", "choose", ["tf_water"], [E(0, 2, 3000)], {}, "bad"),
    ("choose_bad_ms_decreasing", "choose", ["mcq_capital", "mcq_planet"], [E(0, 0, 5000), E(1, 2, 4000)], {}, "bad"),
    ("choose_bad_item_index", "choose", ["mcq_capital"], [E(1, 0, 3000)], {}, "bad"),
    ("choose_bad_end_not_last", "choose", ["mcq_capital", "mcq_planet"],
     [E(0, 0, 3000), E(-1, "timer", 4000), E(1, 2, 5000)], {}, "bad"),
    ("choose_bad_end_value", "choose", ["mcq_capital"], [E(0, 0, 3000), E(-1, "boom", 4000)], {}, "bad"),
    ("choose_bad_only_end", "choose", ["mcq_capital"], [E(-1, "timer", 30000)], {}, "bad"),
    ("choose_bad_empty", "choose", ["mcq_capital"], [], {}, "bad"),
    ("choose_bad_bool_answer", "choose", ["mcq_capital"], [E(0, True, 3000)], {}, "bad"),
    # select_all
    ("select_exact", "select_all", ["sel_even"], [E(0, [0, 2, 4], 9000)], {}, (3, 3)),
    ("select_two_right_one_wrong", "select_all", ["sel_even"], [E(0, [0, 2, 3], 9000)], {}, (1, 3)),
    ("select_more_wrong_than_right", "select_all", ["sel_even"], [E(0, [1, 3, 0], 9000)], {}, (0, 3)),
    ("select_partial", "select_all", ["sel_even"], [E(0, [4], 9000)], {}, (1, 3)),
    ("select_retry_ignored", "select_all", ["sel_even"], [E(0, [1], 5000), E(0, [0, 2, 4], 9000)], {}, (0, 3)),
    ("select_timer_nothing_popped", "select_all", ["sel_even"], [E(0, [], 20000), E(-1, "timer", 20000)], {},
     (0, 3)),
    ("select_bad_duplicate", "select_all", ["sel_even"], [E(0, [0, 0], 9000)], {}, "bad"),
    ("select_bad_not_a_list", "select_all", ["sel_even"], [E(0, 2, 9000)], {}, "bad"),
    # sequence
    ("sequence_order_right", "sequence", ["seq_112_1"],
     [E(0, [0, 0], 3000), E(0, [1, 1], 5000), E(0, [2, 2], 7000), E(0, [3, 3], 9000)],
     {"sacred": True, "template": "verse_builder"}, (4, 4)),
    ("sequence_order_wrong_then_retry", "sequence", ["seq_112_1"],
     [E(0, [0, 0], 3000), E(0, [1, 2], 5000), E(0, [1, 1], 6500), E(0, [2, 2], 8000), E(0, [3, 4], 9000),
      E(0, [3, 3], 11000)], {"sacred": True, "template": "verse_builder"}, (2, 4)),
    ("sequence_distractor_is_wrong", "sequence", ["seq_112_1"],
     [E(0, [0, 5], 3000), E(0, [0, 0], 4000), E(0, [1, 1], 5000), E(0, [2, 2], 7000), E(0, [3, 3], 9000)],
     {"sacred": True, "template": "word_train"}, (3, 4)),
    ("sequence_repeated_word_interchangeable", "sequence", ["seq_repeat"],
     [E(0, [0, 2], 3000), E(0, [1, 1], 5000), E(0, [2, 0], 7000), E(0, [3, 3], 9000)], {}, (4, 4)),
    ("sequence_complete_right", "sequence", ["seq_complete"], [E(0, [1, 1], 4000), E(0, [5, 5], 8000)], {}, (2, 2)),
    ("sequence_complete_distractor", "sequence", ["seq_complete"], [E(0, [1, 6], 4000), E(0, [5, 5], 8000)], {},
     (1, 2)),
    ("sequence_next_word_timer", "sequence", ["seq_next"],
     [E(0, [2, 2], 4000), E(0, [3, 6], 8000), E(-1, "timer", 12000)], {"template": "car_race"}, (1, 3)),
    ("sequence_bad_slot_not_blank", "sequence", ["seq_complete"], [E(0, [0, 0], 4000)], {}, "bad"),
    ("sequence_bad_token_range", "sequence", ["seq_112_1"], [E(0, [0, 6], 4000)], {}, "bad"),
    ("sequence_bad_shape", "sequence", ["seq_112_1"], [E(0, [0], 4000)], {}, "bad"),
    # classify
    ("classify_all_right_with_cases", "classify", ["cls_irab"],
     [E(0, [0, 1], 3000), E(0, [1, 0], 6000), E(0, [1, 0, 0], 8000), E(0, [2, 2], 11000), E(0, [2, 2, 1], 13000)],
     {"template": "irab_hunter"}, (5, 5)),
    ("classify_wrong_bucket_right_case", "classify", ["cls_irab"],
     [E(0, [0, 1], 3000), E(0, [1, 2], 6000), E(0, [1, 0], 7000), E(0, [1, 0, 0], 8000), E(0, [2, 2], 11000),
      E(0, [2, 2, 2], 13000), E(0, [2, 2, 1], 14000)], {"template": "irab_hunter"}, (3, 5)),
    ("classify_no_cases", "classify", ["cls_animals"], [E(0, [0, 0], 3000), E(0, [1, 0], 5000), E(0, [2, 0], 7000)],
     {}, (2, 3)),
    ("classify_timer_ended", "classify", ["cls_irab"], [E(0, [0, 1], 3000), E(-1, "timer", 30000)], {}, (1, 5)),
    ("classify_bad_case_on_token_without_case", "classify", ["cls_irab"], [E(0, [0, 1, 0], 3000)], {}, "bad"),
    ("classify_bad_case_without_cases", "classify", ["cls_animals"], [E(0, [0, 0, 0], 3000)], {}, "bad"),
    ("classify_bad_bucket_range", "classify", ["cls_animals"], [E(0, [0, 2], 3000)], {}, "bad"),
    # pair
    ("pair_all_right", "pair", ["pair_caps"], [E(0, [0, 0], 3000), E(0, [1, 1], 6000), E(0, [2, 2], 9000)], {},
     (3, 3)),
    ("pair_wrong_then_retry", "pair", ["pair_caps"],
     [E(0, [0, 1], 3000), E(0, [0, 0], 4000), E(0, [1, 1], 6000), E(0, [2, 2], 9000)], {}, (2, 3)),
    ("pair_lives_ended", "pair", ["pair_caps"], [E(0, [0, 2], 3000), E(0, [1, 0], 5000), E(-1, "lives", 5200)], {},
     (0, 3)),
    ("pair_bad_range", "pair", ["pair_caps"], [E(0, [0, 3], 3000)], {}, "bad"),
    # fraction
    ("fraction_shape_exact", "fraction", ["frac_shape"], [E(0, [3, 4], 9000)], {}, (1, 1)),
    ("fraction_shape_equivalent", "fraction", ["frac_shape"], [E(0, [6, 8], 9000)], {}, (1, 1)),
    ("fraction_shape_wrong_then_retry", "fraction", ["frac_shape"], [E(0, [2, 4], 9000), E(0, [3, 4], 12000)], {},
     (0, 1)),
    ("fraction_add", "fraction", ["frac_add", "frac_sub"], [E(0, [5, 6], 9000), E(1, [1, 2], 18000)], {}, (2, 2)),
    ("fraction_add_wrong", "fraction", ["frac_add", "frac_sub"], [E(0, [2, 5], 9000), E(1, [2, 4], 18000)], {},
     (1, 2)),
    ("fraction_bad_zero_denominator", "fraction", ["frac_shape"], [E(0, [3, 0], 9000)], {}, "bad"),
    ("fraction_bad_negative", "fraction", ["frac_shape"], [E(0, [-3, 4], 9000)], {}, "bad"),
    # program
    ("program_at_par", "program", ["prog_grid"], [E(0, ["R", "F", "F", "L", LOOP(2, ["F"])], 20000)], {}, (2, 2)),
    ("program_grid_over_par", "program", ["prog_grid"], [E(0, ["L", "R", "R", "F", "F", "L", "F", "F"], 20000)], {}, None),
    ("program_no_loop_par", "program", ["prog_noloop"], [E(0, ["F", "F"], 9000)], {}, (2, 2)),
    ("program_goal_over_par", "program", ["prog_noloop"], [E(0, ["L", "R", "F", "F"], 9000)], {}, (1, 2)),
    ("program_goal_over_max", "program", ["prog_noloop"], [E(0, ["L", "R", "L", "R", "F", "F"], 9000)], {}, (0, 2)),
    ("program_bump_wall", "program", ["prog_grid"], [E(0, ["F", "F", "F"], 9000)], {}, (0, 2)),
    ("program_leave_grid", "program", ["prog_noloop"], [E(0, ["L", "F"], 9000)], {}, (0, 2)),
    ("program_best_of_three_runs", "program", ["prog_noloop"],
     [E(0, ["R", "F"], 9000), E(0, ["L", "R", "F", "F"], 15000), E(0, ["F", "F"], 21000)], {}, (2, 2)),
    ("program_fourth_run_ignored", "program", ["prog_noloop"],
     [E(0, ["R"], 9000), E(0, ["L"], 12000), E(0, ["R", "R"], 15000), E(0, ["F", "F"], 21000)], {}, (0, 2)),
    ("program_stops_at_goal", "program", ["prog_noloop"], [E(0, ["F", "F", "F"], 9000)], {}, (1, 2)),
    ("program_bad_command", "program", ["prog_noloop"], [E(0, ["F", "X"], 9000)], {}, "bad"),
    ("program_bad_loop_not_allowed", "program", ["prog_noloop"], [E(0, [LOOP(2, ["F"])], 9000)], {}, "bad"),
    ("program_bad_loop_count", "program", ["prog_grid"], [E(0, [LOOP(1, ["F"])], 9000)], {}, "bad"),
    ("program_bad_nested_loop", "program", ["prog_grid"], [E(0, [LOOP(2, [LOOP(2, ["F"])])], 9000)], {}, "bad"),
    # combine
    ("combine_right", "combine", ["comb_volcano"], [E(0, [0, 1], 9000)], {"template": "science_lab"}, (1, 1)),
    ("combine_extra_ingredient", "combine", ["comb_volcano"], [E(0, [0, 1, 2], 9000)], {}, (0, 1)),
    ("combine_wrong_then_retry", "combine", ["comb_volcano"], [E(0, [2, 3], 5000), E(0, [0, 1], 9000)], {}, (0, 1)),
    ("combine_bad_empty", "combine", ["comb_volcano"], [E(0, [], 9000)], {}, "bad"),
    ("combine_bad_range", "combine", ["comb_volcano"], [E(0, [0, 4], 9000)], {}, "bad"),
    # mixed rounds and rank points
    ("mixed_lab_round", "combine", ["comb_volcano", "mcq_planet"], [E(0, [1, 0], 9000), E(1, 2, 15000)],
     {"template": "science_lab", "difficulty": "hard"}, (2, 2)),
    ("rank_fast_full_bonus", "choose", ["mcq_capital", "mcq_planet", "tf_water", "tf_sun"],
     [E(0, 0, 500), E(1, 2, 1000), E(2, 1, 1500), E(3, 0, 2000)], {"difficulty": "hard"}, (4, 4)),
    ("rank_too_fast", "choose", ["mcq_capital", "mcq_planet", "tf_water", "tf_sun"],
     [E(0, 0, 300), E(1, 2, 600), E(2, 1, 900), E(3, 0, 1200)], {}, (4, 4)),
    ("rank_growing_tree_no_bonus", "choose", ["mcq_capital", "mcq_planet"], [E(0, 0, 2000), E(1, 2, 4000)],
     {"template": "growing_tree", "difficulty": "easy"}, (2, 2)),
    ("rank_zero_stars", "choose", ["mcq_capital", "mcq_planet", "tf_water", "tf_sun"],
     [E(0, 1, 4000), E(1, 0, 9000), E(2, 0, 13000), E(3, 0, 17000)], {}, (1, 4)),
]


def build():
    out = []
    for name, kind, names, trace, meta, want in CASES:
        items = [ITEMS[n] for n in names]
        sacred = bool(meta.get("sacred")) or any(x.get("sacred") for x in items)
        tpl = meta.get("template", "challenge_quiz")
        diff = meta.get("difficulty", "medium")
        row = {"name": name, "kind": kind, "items": names, "template": tpl, "difficulty": diff, "sacred": sacred,
               "trace": trace}
        try:
            g = grade(items, trace)
        except Bad as exc:
            assert want == "bad", (name, "refused", str(exc))
            row.update({"valid": False, "why": str(exc)})
            out.append(row)
            continue
        assert want != "bad", (name, "should be refused", g)
        if want is not None:
            assert (g["score"], g["max"]) == want, (name, g["score"], g["max"], want)
        st = stars(g["score"], g["max"])
        too_fast = g["duration_ms"] < g["counted"] * MIN_STEP_MS
        row.update({"valid": True, "score": g["score"], "max_score": g["max"], "per_item": g["per_item"],
                    "counted": g["counted"], "duration_ms": g["duration_ms"], "end": g["end"], "stars": st,
                    "too_fast": too_fast,
                    "rank_points": rank_points(items, g["score"], g["max"], g["duration_ms"], diff, sacred, tpl),
                    "ghost": g["ghost"]})
        out.append(row)
    return out


def main(path):
    cases = build()
    by = {c["name"]: c for c in cases}
    # hand-checked numbers (the planner's own arithmetic, not the code's)
    assert by["program_grid_over_par"]["score"] == 1          # 8 tokens: over par 6, within max 8
    assert by["choose_all_right"]["rank_points"] == 145   # base 100, medium 125, D 17 s of par 40 s: bonus 158
    assert by["sequence_order_right"]["rank_points"] == 125      # sacred: no speed bonus
    assert by["rank_fast_full_bonus"]["rank_points"] == 179      # hard 150, bonus 195
    assert by["rank_too_fast"]["too_fast"] is True
    assert by["rank_growing_tree_no_bonus"]["rank_points"] == 100
    assert by["rank_zero_stars"]["rank_points"] == 0 and by["rank_zero_stars"]["stars"] == 0
    assert by["choose_timer_ended"]["stars"] == 0 and by["choose_timer_ended"]["end"] == "timer"
    prog = ITEMS["prog_grid"]["body"]
    sims = []
    for label, a in [("at_par", ["R", "F", "F", "L", LOOP(2, ["F"])]), ("bump_wall", ["F", "F", "F"]),
                     ("turn_only", ["L", "L", "R"]), ("loop_square", [LOOP(4, ["F", "R"])]),
                     ("long_way", ["R", "F", "L", "F", "F", "R", "F"])]:
        sims.append({"name": label, "item": "prog_grid", "a": a, **simulate(prog, a)})
    today = date(2026, 11, 23)
    ages = []
    for dob, grade_no in [("2019-01-10", None), ("2017-11-23", None), ("2016-11-23", None), ("2016-11-24", None),
                          ("2012-11-24", None), ("2012-11-23", None), ("2008-11-23", None), ("2008-11-24", None),
                          ("1996-05-01", None), ("2022-03-01", None), (None, 1), (None, 4), (None, 5), (None, 8),
                          (None, 9), (None, 12), (None, 13), (None, None)]:
        band, src = age_band(date.fromisoformat(dob) if dob else None, grade_no, today)
        ages.append({"today": str(today), "dob": dob, "grade": grade_no, "age_band": band, "age_source": src})
    doc = {
        "version": 1,
        "about": "Games v4 grading vectors (docs/games-v4/CONTRACT.md sections 5-7). The Dart session "
                 "(lib/features/games/core) and the server's items_grade.grade must both give these numbers. "
                 "valid=false: the trace is refused as a whole (the play is saved unranked, reason bad_trace). "
                 "Items are in the snapshot form of a draw (section 4). duration_ms is the last entry's ms. "
                 "too_fast: duration_ms < counted x min_step_ms. rank_points is computed for every valid case as if "
                 "the play ranked.",
        "constants": {"min_step_ms": MIN_STEP_MS, "max_trace": MAX_TRACE, "program_runs": PROGRAM_RUNS,
                      "program_max_steps": MAX_STEPS, "par_s": PAR_S, "par_per_unit_types": list(PER_UNIT),
                      "difficulty_percent": DIFF, "end_values": list(ENDS),
                      "no_speed_bonus_templates": list(NO_BONUS_TEMPLATES), "stars_percent": [90, 60, 30],
                      "ghost_max_events": 200},
        "items": ITEMS,
        "cases": cases,
        "program_runs": sims,
        "age_bands": ages,
        "srs": [
            {"about": "right on first try: the box goes up, due after the box's days",
             "before": {"box": 1}, "right": True, "after": {"box": 2, "due_in_days": 3, "lapses_added": 0}},
            {"before": {"box": 2}, "right": True, "after": {"box": 3, "due_in_days": 7, "lapses_added": 0}},
            {"before": {"box": 3}, "right": True, "after": {"box": 4, "due_in_days": 14, "lapses_added": 0}},
            {"before": {"box": 4}, "right": True, "after": {"box": 5, "due_in_days": 30, "lapses_added": 0}},
            {"before": {"box": 5}, "right": True, "after": {"box": 5, "due_in_days": 30, "lapses_added": 0}},
            {"about": "wrong (the item's score is below its max): back to box 1, due the next day",
             "before": {"box": 4}, "right": False, "after": {"box": 1, "due_in_days": 1, "lapses_added": 1}},
            {"about": "no row yet and right: no row is made (only a miss starts the ladder)",
             "before": None, "right": True, "after": None},
            {"before": None, "right": False, "after": {"box": 1, "due_in_days": 1, "lapses_added": 1}},
        ],
        "coins": [
            {"about": "coins_reward 9: each star of a level pays once, coins_reward // 3 each, the third takes the rest",
             "coins_reward": 9, "stars_before": 0, "stars_now": 2, "coins_awarded": 6},
            {"coins_reward": 9, "stars_before": 2, "stars_now": 3, "coins_awarded": 3},
            {"coins_reward": 9, "stars_before": 3, "stars_now": 3, "coins_awarded": 0},
            {"coins_reward": 10, "stars_before": 0, "stars_now": 3, "coins_awarded": 10},
            {"coins_reward": 10, "stars_before": 1, "stars_now": 2, "coins_awarded": 3},
            {"coins_reward": 0, "stars_before": 0, "stars_now": 3, "coins_awarded": 0},
        ],
    }
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write("\n")
    valid = sum(1 for c in cases if c["valid"])
    print(len(cases), "cases,", valid, "valid,", len(cases) - valid, "refused")
    for c in cases:
        if c["valid"]:
            print(" ", c["name"], c["score"], "/", c["max_score"], "stars", c["stars"], "rp", c["rank_points"],
                  "tf" if c["too_fast"] else "")
    for s in sims:
        print("  sim", s["name"], s["reached"], s["bumped"], s["length"], s["points"])


if __name__ == "__main__":
    main(sys.argv[1])
