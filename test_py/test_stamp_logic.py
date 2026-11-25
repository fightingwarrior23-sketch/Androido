import os, sys, random
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools", "mirror"))
import stamp_logic as m

# desktop reference (optional: only if the desktop zip was unpacked next to us)
REF = "/home/claude/ref/LectureVideoMaker-arabic"
desk = None
if os.path.isdir(REF):
    sys.path.insert(0, REF)
    import types
    fake = types.ModuleType("i18n")          # desktop core.py only needs T() from it
    fake.T = lambda text, **kw: text.format(**kw) if kw else text
    sys.modules["i18n"] = fake
    try:
        import core as desk
    except Exception as e:
        print("desktop core not importable:", e)

fails = 0
def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    fails += 0 if cond else 1

# --- time
check("parse 90", m.parse_time("90") == 90)
check("parse 1:30", m.parse_time("1:30") == 90)
check("parse 1:02:03", m.parse_time("1:02:03") == 3723)
check("parse empty", m.parse_time("  ") is None)
for bad in ["1:75", "1:61:00", "a", "1:2:3:4", "-5"]:
    try:
        m.parse_time(bad); check("reject " + bad, False)
    except ValueError:
        check("reject " + bad, True)
check("fmt 83", m.fmt_time(83) == "1:23")
check("fmt 3723", m.fmt_time(3723) == "1:02:03")
check("fmt 59.5 rounds up", m.fmt_time(59.5) == "1:00")

# --- stamp rules
b = m.StampBook()
check("single stamps left only", b.stamp(10, False, (0, 2), (1, 5), "both") == [(0, 2, 10)])
b = m.StampBook()
check("split left", b.stamp(10, True, (0, 2), (1, 5), "left") == [(0, 2, 10)])
b = m.StampBook()
check("split right", b.stamp(10, True, (0, 2), (1, 5), "right") == [(1, 5, 10)])
b = m.StampBook()
check("split both", b.stamp(10, True, (0, 2), (1, 5), "both") == [(0, 2, 10), (1, 5, 10)])
check("duplicate skipped", b.stamp(10, True, (0, 2), (1, 5), "both") == [] and len(b.stamps) == 2)
b = m.StampBook()
b.stamp(5, False, (0, 0)); b.stamp(1, False, (0, 1)); b.stamp(9, False, (0, 0))
check("sorted by time", [s[2] for s in b.stamps] == [1, 5, 9])
check("page can repeat", len(b.for_page(0, 0)) == 2)
b.stamp(-3, False, (0, 7))
check("negative clamps to 0", b.stamps[0] == (0, 7, 0.0))

# --- undo / delete / edit
b = m.StampBook()
b.stamp(5, False, (0, 0)); b.stamp(8, False, (0, 1))
b.undo(); check("undo last stamp", b.stamps == [(0, 0, 5)])
b.delete((0, 0, 5)); check("delete", b.stamps == [])
b.undo(); check("undo delete", b.stamps == [(0, 0, 5)])
b.stamp(8, False, (0, 1))
check("edit time", b.edit((0, 1, 8), (0, 1, 2)) and b.stamps[0] == (0, 1, 2))
check("edit clash refused", not b.edit((0, 1, 2), (0, 0, 5)))
b.undo(); check("undo edit", (0, 1, 8) in b.stamps)
check("undo empty returns False", not m.StampBook().undo())

# --- remove pdf renumbers
b = m.StampBook([(0, 0, 1), (1, 3, 2), (2, 4, 3)])
b.remove_pdf(1)
check("remove pdf renumbers", b.stamps == [(0, 0, 1), (1, 4, 3)])

# --- segments
b = m.StampBook([(0, 0, 12), (0, 1, 40), (1, 0, 40), (0, 0, 90)])
segs = b.segments()
check("first starts at 0", segs[0][0] == 0.0)
check("same-time grouped", segs[1][2] == [(0, 1), (1, 0)])
check("last open ended", segs[-1][1] is None and segs[0][1] == 40)
check("page comes back", segs[2][2] == [(0, 0)])
check("no stamps -> no segments", m.StampBook().segments() == [])

# --- nudge
b = m.StampBook([(0, 0, 10), (0, 1, 20)])
check("nudge +1", b.nudge((0, 0, 10), 1) and b.stamps[0] == (0, 0, 11))
b2 = m.StampBook([(0, 0, 10), (0, 0, 20)])
check("nudge clash refused", not b2.nudge((0, 0, 10), 10) and b2.stamps[0] == (0, 0, 10))
check("nudge not below 0", m.StampBook([(0, 0, 0.4)]).nudge((0, 0, 0.4), -1))
check("nudge at 0 stays", not m.StampBook([(0, 0, 0)]).nudge((0, 0, 0), -1))

# --- trimmed segments (video begins at first stamp, optional end)
b = m.StampBook([(0, 0, 12), (0, 1, 40), (1, 0, 40), (0, 0, 90)])
t = b.trimmed_segments()
check("trim begins at first stamp", t[0][0] == 12 and len(t) == 3)
check("trim last open ended", t[-1][1] is None)
t = b.trimmed_segments(end_at=60)
check("trim end cuts last slide", len(t) == 2 and t[-1][1] == 60 and t[-1][2] == [(0, 1), (1, 0)])
check("trim end before first stamp -> empty", b.trimmed_segments(end_at=5) == [])

# --- cross-check against the desktop code
if desk:
    random.seed(1)
    for t in ["90", "1:30", "1:02:03", "0:07", "59:59", "12.5", ":30"]:
        check("desktop parse_time " + t, desk.parse_time(t) == m.parse_time(t))
    for v in [0, 5, 59.5, 83, 3599, 3723, 36000]:
        check(f"desktop fmt_time {v}", desk.fmt_time(v) == m.fmt_time(v))
    for n in range(1, 13):
        check(f"desktop grid_layout {n}", desk.grid_layout(n) == m.grid_layout(n))
        check(f"desktop grid_rects {n}", desk.grid_rects(n) == m.grid_rects(n))
    cues = sorted((random.choice([1, 2, 2, 3, 5]) * 10.0, random.randint(0, 1), random.randint(0, 4)) for _ in range(30))
    got = [(t, p) for t, p in m.StampBook([(d, p, t) for t, d, p in cues]).groups()]
    # the desktop sorts by time only; compare the grouping, ignoring order inside a group
    exp = [(t, sorted(p)) for t, p in desk.group_cues(cues, True)]
    got = [(t, sorted(p)) for t, p in got]
    check("desktop group_cues (30 random cues)", exp == [(t, p) for t, p in got] or {x[0] for x in exp} == {x[0] for x in got} and [sorted(x[1]) for x in exp] == [sorted(x[1]) for x in got])

print("\nFAILED:", fails)
sys.exit(1 if fails else 0)
