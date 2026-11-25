"""Python mirror of lib/core/*.dart. Same rules, same order of operations.
Used only to test the rules here; the app itself runs the Dart version."""
import re


def parse_time(text):
    text = text.strip()
    if not text:
        return None
    parts = text.split(":")
    if len(parts) > 3:
        raise ValueError(text)
    nums = []
    for p in parts:
        p = p.strip()
        if not p:
            nums.append(0.0)
            continue
        try:
            v = float(p)
        except ValueError:
            raise ValueError(text)
        if v < 0:
            raise ValueError(text)
        nums.append(v)
    if (len(nums) > 1 and nums[-1] >= 60) or (len(nums) == 3 and nums[1] >= 60):
        raise ValueError(text)
    total = 0.0
    for n in nums:
        total = total * 60 + n
    return total


def fmt_time(sec):
    s = int(sec + 0.5)  # Dart round(): half away from zero (values here are >= 0)
    h, rem = divmod(s, 3600)
    m, ss = divmod(rem, 60)
    return f"{h}:{m:02d}:{ss:02d}" if h else f"{m}:{ss:02d}"


def same(a, b):
    return a[0] == b[0] and a[1] == b[1] and abs(a[2] - b[2]) < 0.0005


class StampBook:
    """A stamp is a tuple (pdf, page, seconds)."""

    def __init__(self, initial=()):
        self.stamps = list(initial)
        self._sort()
        self._undo = []

    def _sort(self):
        self.stamps.sort(key=lambda s: (s[2], s[0], s[1]))

    def _remember(self):
        self._undo.append(list(self.stamps))
        if len(self._undo) > 100:
            self._undo.pop(0)

    def stamp(self, seconds, split, left, right=None, target="left"):
        if not split or right is None:
            wanted = [left]
        else:
            wanted = []
            if target in ("left", "both"):
                wanted.append(left)
            if target in ("right", "both"):
                wanted.append(right)
        s = max(seconds, 0.0)
        added = []
        for w in wanted:
            st = (w[0], w[1], s)
            if any(same(x, st) for x in self.stamps) or any(same(x, st) for x in added):
                continue
            added.append(st)
        if not added:
            return added
        self._remember()
        self.stamps.extend(added)
        self._sort()
        return added

    def delete(self, s):
        for i, x in enumerate(self.stamps):
            if same(x, s):
                self._remember()
                del self.stamps[i]
                return

    def edit(self, old, new):
        idx = next((i for i, x in enumerate(self.stamps) if same(x, old)), -1)
        if idx < 0:
            return False
        if any(i != idx and same(x, new) for i, x in enumerate(self.stamps)):
            return False
        self._remember()
        self.stamps[idx] = new
        self._sort()
        return True

    def nudge(self, s, delta):
        nt = max(s[2] + delta, 0.0)
        if abs(nt - s[2]) < 0.0005:
            return False
        return self.edit(s, (s[0], s[1], nt))

    def undo(self):
        if not self._undo:
            return False
        self.stamps = self._undo.pop()
        return True

    def remove_pdf(self, index):
        self._remember()
        self.stamps = [s for s in self.stamps if s[0] != index]
        self.stamps = [(s[0] - 1, s[1], s[2]) if s[0] > index else s for s in self.stamps]

    def for_page(self, pdf, page):
        return [s for s in self.stamps if s[0] == pdf and s[1] == page]

    def groups(self):
        out = []
        for pdf, page, t in self.stamps:
            if out and abs(out[-1][0] - t) < 0.0005:
                out[-1][1].append((pdf, page))
            else:
                out.append((t, [(pdf, page)]))
        return out

    def segments(self):
        g = self.groups()
        segs = []
        for i, (t, pages) in enumerate(g):
            start = 0.0 if i == 0 else t
            end = g[i + 1][0] if i + 1 < len(g) else None
            segs.append((start, end, pages))
        return segs

    def trimmed_segments(self, end_at=None):
        g = [e for e in self.groups() if end_at is None or e[0] < end_at]
        segs = []
        for i, (t, pages) in enumerate(g):
            end = g[i + 1][0] if i + 1 < len(g) else end_at
            segs.append((t, end, pages))
        return segs


def grid_layout(n):
    cols = 1
    while cols * cols < n:
        cols += 1
    rows, left = [], n
    while left > 0:
        rows.append(min(cols, left))
        left -= cols
    if n == 2:
        return [2]
    return rows


def grid_rects(n, width=1920, height=1080, gap=8):
    rows = grid_layout(n)
    cols = max(rows)
    cw, ch = width / cols, height / len(rows)
    rects = []
    for r, k in enumerate(rows):
        x_off = (cols - k) * cw / 2
        for c in range(k):
            x0, y0 = x_off + c * cw, r * ch
            rects.append((x0 + gap, y0 + gap, x0 + cw - gap, y0 + ch - gap))
    return rects
