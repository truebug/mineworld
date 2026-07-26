"""二人暗战陆军棋 — 规则引擎（对齐 docs/26-junqi-ssot.md）。"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any

ROWS = 12
COLS = 5

# ranks: higher wins. specials handled separately.
RANK: dict[str, int] = {
    "junqi": 0,
    "gongbing": 1,
    "paizhang": 2,
    "lianzhang": 3,
    "yingzhang": 4,
    "tuanzhang": 5,
    "lvzhang": 6,
    "shizhang": 7,
    "junzhang": 8,
    "siling": 9,
    "zhadan": -1,
    "dilei": -2,
}

PIECE_QUOTA: dict[str, int] = {
    "junqi": 1,
    "siling": 1,
    "junzhang": 1,
    "shizhang": 2,
    "lvzhang": 2,
    "tuanzhang": 2,
    "yingzhang": 2,
    "zhadan": 2,
    "lianzhang": 3,
    "paizhang": 3,
    "gongbing": 3,
    "dilei": 3,
}

HQ_BLACK = ((0, 1), (0, 3))
HQ_RED = ((11, 1), (11, 3))
CAMP_BLACK = ((2, 1), (2, 3), (3, 2), (4, 1), (4, 3))
CAMP_RED = ((7, 1), (7, 3), (8, 2), (9, 1), (9, 3))


def _mirror_r(r: int) -> int:
    return 11 - r


def cell_key(r: int, c: int) -> str:
    return f"{r},{c}"


def parse_key(k: str) -> tuple[int, int]:
    a, b = k.split(",")
    return int(a), int(b)


def is_hq(r: int, c: int) -> bool:
    return (r, c) in HQ_BLACK or (r, c) in HQ_RED


def is_camp(r: int, c: int) -> bool:
    return (r, c) in CAMP_BLACK or (r, c) in CAMP_RED


def side_of_cell(r: int) -> str:
    return "black" if r <= 5 else "red"


def layout_rows(side: str) -> range:
    return range(0, 6) if side == "black" else range(6, 12)


def _add_undirected(edges: set[tuple[str, str]], a: tuple[int, int], b: tuple[int, int]) -> None:
    if not (0 <= a[0] < ROWS and 0 <= a[1] < COLS):
        return
    if not (0 <= b[0] < ROWS and 0 <= b[1] < COLS):
        return
    ka, kb = cell_key(*a), cell_key(*b)
    if ka == kb:
        return
    edges.add((ka, kb) if ka < kb else (kb, ka))


def _build_highway() -> dict[str, set[str]]:
    edges: set[tuple[str, str]] = set()
    # Orthogonal within half + front; mountain only cols 0,2,4.
    for r in range(ROWS):
        for c in range(COLS):
            for dr, dc in ((0, 1), (1, 0)):
                nr, nc = r + dr, c + dc
                if not (0 <= nr < ROWS and 0 <= nc < COLS):
                    continue
                # Block mountain gap on cols 1 and 3.
                if sorted((r, nr)) == [5, 6] and c in (1, 3) and dc == 0:
                    continue
                if r <= 5 and nr >= 6 and not (sorted((r, nr)) == [5, 6] and c in (0, 2, 4)):
                    continue
                if nr <= 5 and r >= 6 and not (sorted((r, nr)) == [5, 6] and c in (0, 2, 4)):
                    continue
                _add_undirected(edges, (r, c), (nr, nc))
    # Camp diagonals.
    for camp in list(CAMP_BLACK) + list(CAMP_RED):
        cr, cc = camp
        for dr, dc in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
            _add_undirected(edges, camp, (cr + dr, cc + dc))
    return _adj_from_edges(edges)


def _rail_chain(edges: set[tuple[str, str]], cells: list[tuple[int, int]]) -> None:
    for i in range(len(cells) - 1):
        _add_undirected(edges, cells[i], cells[i + 1])


def _build_railway() -> dict[str, set[str]]:
    edges: set[tuple[str, str]] = set()
    # Black loop: row1, row5, col0 rows1-5, col4 rows1-5.
    _rail_chain(edges, [(1, c) for c in range(COLS)])
    _rail_chain(edges, [(5, c) for c in range(COLS)])
    _rail_chain(edges, [(r, 0) for r in range(1, 6)])
    _rail_chain(edges, [(r, 4) for r in range(1, 6)])
    # Red mirror.
    _rail_chain(edges, [(_mirror_r(1), c) for c in range(COLS)])
    _rail_chain(edges, [(_mirror_r(5), c) for c in range(COLS)])
    _rail_chain(edges, [(_mirror_r(r), 0) for r in range(1, 6)])
    _rail_chain(edges, [(_mirror_r(r), 4) for r in range(1, 6)])
    # Mountain rail sides.
    _add_undirected(edges, (5, 0), (6, 0))
    _add_undirected(edges, (5, 4), (6, 4))
    return _adj_from_edges(edges)


def _adj_from_edges(edges: set[tuple[str, str]]) -> dict[str, set[str]]:
    adj: dict[str, set[str]] = {}
    for a, b in edges:
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    return adj


HIGHWAY = _build_highway()
RAILWAY = _build_railway()


def resolve_combat(attacker: str, defender: str) -> str:
    """Return win | lose | draw | flag_win."""
    if defender == "junqi":
        return "flag_win"
    if attacker == "junqi":
        return "lose"
    if attacker == "zhadan" or defender == "zhadan":
        return "draw"
    if defender == "dilei":
        if attacker == "gongbing":
            return "win"
        return "lose"
    if attacker == "dilei":
        return "lose"
    ar, dr = RANK[attacker], RANK[defender]
    if ar > dr:
        return "win"
    if ar < dr:
        return "lose"
    return "draw"


@dataclass
class JunqiPiece:
    pid: str
    ptype: str
    side: str  # black | red
    r: int
    c: int
    alive: bool = True
    locked: bool = False  # entered non-flag HQ


@dataclass
class JunqiBoard:
    """Full dark-junqi board state for one table."""

    pieces: dict[str, JunqiPiece] = field(default_factory=dict)
    phase: str = "layout"  # layout | playing | finished
    turn: str = "red"  # red moves first after layout (convention)
    winner: str | None = None  # black | red
    flag_revealed: dict[str, bool] = field(default_factory=lambda: {"black": False, "red": False})
    layout_ready: dict[str, bool] = field(default_factory=lambda: {"black": False, "red": False})
    last_battle: dict[str, Any] | None = None

    def reset(self) -> None:
        self.pieces.clear()
        self.phase = "layout"
        self.turn = "red"
        self.winner = None
        self.flag_revealed = {"black": False, "red": False}
        self.layout_ready = {"black": False, "red": False}
        self.last_battle = None

    def cell_piece(self, r: int, c: int) -> JunqiPiece | None:
        for p in self.pieces.values():
            if p.alive and p.r == r and p.c == c:
                return p
        return None

    def flag_pos(self, side: str) -> tuple[int, int] | None:
        for p in self.pieces.values():
            if p.alive and p.side == side and p.ptype == "junqi":
                return (p.r, p.c)
        return None

    def validate_layout(self, side: str, layout: dict[str, list[int]]) -> str | None:
        """Return error message or None if OK. layout: pieceType_index -> [r,c]."""
        rows = set(layout_rows(side))
        camps = set(CAMP_BLACK if side == "black" else CAMP_RED)
        hqs = set(HQ_BLACK if side == "black" else HQ_RED)
        counts: dict[str, int] = {k: 0 for k in PIECE_QUOTA}
        used: set[tuple[int, int]] = set()
        flag_cell: tuple[int, int] | None = None
        for key, pos in layout.items():
            if len(pos) != 2:
                return "bad_pos"
            r, c = int(pos[0]), int(pos[1])
            ptype = key.rsplit("_", 1)[0]
            if ptype not in PIECE_QUOTA:
                return f"unknown:{ptype}"
            if r not in rows or not (0 <= c < COLS):
                return "out_of_half"
            if (r, c) in camps:
                return "camp_forbidden"
            if (r, c) in used:
                return "overlap"
            used.add((r, c))
            counts[ptype] = counts.get(ptype, 0) + 1
            if ptype == "junqi":
                if (r, c) not in hqs:
                    return "flag_not_hq"
                flag_cell = (r, c)
            if ptype == "dilei":
                last = {0, 1} if side == "black" else {10, 11}
                if r not in last:
                    return "mine_row"
                if flag_cell and (r, c) == flag_cell:
                    return "mine_on_flag"
            if ptype == "zhadan":
                back = 0 if side == "black" else 11
                if r == back:
                    return "bomb_back_row"
        # mine vs flag same cell check after flag known
        for key, pos in layout.items():
            ptype = key.rsplit("_", 1)[0]
            if ptype == "dilei" and flag_cell == (int(pos[0]), int(pos[1])):
                return "mine_on_flag"
        for t, n in PIECE_QUOTA.items():
            if counts.get(t, 0) != n:
                return f"quota:{t}"
        if len(used) != 25:
            return "count"
        if flag_cell is None:
            return "no_flag"
        return None

    def apply_layout(self, side: str, layout: dict[str, list[int]]) -> bool:
        err = self.validate_layout(side, layout)
        if err:
            return False
        # Remove existing side pieces.
        self.pieces = {k: v for k, v in self.pieces.items() if v.side != side}
        for key, pos in layout.items():
            ptype = key.rsplit("_", 1)[0]
            r, c = int(pos[0]), int(pos[1])
            pid = f"{side}_{key}"
            self.pieces[pid] = JunqiPiece(pid=pid, ptype=ptype, side=side, r=r, c=c)
        self.layout_ready[side] = True
        if self.layout_ready["black"] and self.layout_ready["red"]:
            self.phase = "playing"
            # First sitter (black) moves first — matches gomoku seat order.
            self.turn = "black"
        return True

    def auto_layout(self, side: str) -> dict[str, list[int]]:
        """Deterministic-ish random legal layout for AI / solo fill."""
        rows = list(layout_rows(side))
        camps = set(CAMP_BLACK if side == "black" else CAMP_RED)
        hqs = list(HQ_BLACK if side == "black" else HQ_RED)
        cells = [(r, c) for r in rows for c in range(COLS) if (r, c) not in camps]
        random.shuffle(cells)
        layout: dict[str, list[int]] = {}
        flag_hq = hqs[0]
        layout["junqi_0"] = [flag_hq[0], flag_hq[1]]
        used = {flag_hq}
        back = 0 if side == "black" else 11
        mine_rows = {0, 1} if side == "black" else {10, 11}

        def take_cell(pred) -> tuple[int, int]:
            for cell in cells:
                if cell in used:
                    continue
                if pred(cell):
                    used.add(cell)
                    return cell
            raise RuntimeError("no cell")

        for i in range(3):
            r, c = take_cell(lambda x: x[0] in mine_rows and x not in hqs)
            layout[f"dilei_{i}"] = [r, c]
        for i in range(2):
            r, c = take_cell(lambda x: x[0] != back)
            layout[f"zhadan_{i}"] = [r, c]
        order = [
            ("siling", 1),
            ("junzhang", 1),
            ("shizhang", 2),
            ("lvzhang", 2),
            ("tuanzhang", 2),
            ("yingzhang", 2),
            ("lianzhang", 3),
            ("paizhang", 3),
            ("gongbing", 3),
        ]
        for ptype, n in order:
            for i in range(n):
                r, c = take_cell(lambda _x: True)
                layout[f"{ptype}_{i}"] = [r, c]
        assert self.validate_layout(side, layout) is None
        return layout

    def movable(self, p: JunqiPiece) -> bool:
        if not p.alive or p.locked:
            return False
        if p.ptype in ("junqi", "dilei"):
            return False
        if is_hq(p.r, p.c):
            return False
        return True

    def _rail_reachable(self, fr: int, fc: int, tr: int, tc: int, engineer: bool) -> bool:
        start, goal = cell_key(fr, fc), cell_key(tr, tc)
        if start == goal:
            return False
        if goal not in RAILWAY.get(start, set()) and not engineer:
            # BFS on railway only.
            pass
        from collections import deque

        q = deque([start])
        prev: dict[str, str | None] = {start: None}
        while q:
            cur = q.popleft()
            if cur == goal:
                # reconstruct path; non-engineer must be straight line
                path = []
                x = goal
                while x is not None:
                    path.append(x)
                    x = prev[x]
                path.reverse()
                # path includes start; intermediate must be empty
                for step in path[1:-1]:
                    rr, cc = parse_key(step)
                    if self.cell_piece(rr, cc) is not None:
                        return False
                if not engineer and len(path) >= 2:
                    coords = [parse_key(p) for p in path]
                    rows = {r for r, _c in coords}
                    cols = {c for _r, c in coords}
                    if not (len(rows) == 1 or len(cols) == 1):
                        return False
                return True
            for nb in RAILWAY.get(cur, ()):
                if nb in prev:
                    continue
                # cannot step onto occupied except goal
                rr, cc = parse_key(nb)
                occ = self.cell_piece(rr, cc)
                if occ is not None and nb != goal:
                    continue
                prev[nb] = cur
                q.append(nb)
        return False

    def _highway_step(self, fr: int, fc: int, tr: int, tc: int) -> bool:
        a, b = cell_key(fr, fc), cell_key(tr, tc)
        return b in HIGHWAY.get(a, set())

    def try_move(self, side: str, fr: int, fc: int, tr: int, tc: int) -> dict[str, Any] | None:
        """Apply move; return event detail or None if illegal."""
        if self.phase != "playing" or self.turn != side:
            return None
        piece = self.cell_piece(fr, fc)
        if piece is None or piece.side != side or not self.movable(piece):
            return None
        if not (0 <= tr < ROWS and 0 <= tc < COLS):
            return None
        target = self.cell_piece(tr, tc)
        if target is not None and target.side == side:
            return None
        if target is not None and is_camp(tr, tc):
            return None  # cannot attack into camp
        from_camp = is_camp(fr, fc)
        engineer = piece.ptype == "gongbing"
        # Movement legality to empty or enemy cell.
        one_step = self._highway_step(fr, fc, tr, tc)
        rail_ok = False if from_camp else self._rail_reachable(fr, fc, tr, tc, engineer)
        if from_camp and not one_step:
            return None
        if not from_camp and not one_step and not rail_ok:
            return None
        # Empty move.
        if target is None:
            # Entering enemy HQ (empty): lock unless that HQ holds flag — flag always occupies HQ.
            piece.r, piece.c = tr, tc
            if is_hq(tr, tc) and side_of_cell(tr) != side:
                piece.locked = True
            self.turn = "black" if side == "red" else "red"
            self.last_battle = None
            if not self._has_movable("black"):
                self.winner = "red"
                self.phase = "finished"
            elif not self._has_movable("red"):
                self.winner = "black"
                self.phase = "finished"
            return {"kind": "move", "from": [fr, fc], "to": [tr, tc]}
        # Combat.
        result = resolve_combat(piece.ptype, target.ptype)
        self.last_battle = {
            "attacker": piece.ptype,
            "defender": target.ptype,
            "attacker_side": side,
            "result": result,
            "at": [tr, tc],
        }
        if result == "flag_win":
            piece.r, piece.c = tr, tc
            target.alive = False
            self.winner = side
            self.phase = "finished"
            return self.last_battle
        if result == "win":
            target.alive = False
            piece.r, piece.c = tr, tc
            if target.ptype == "siling":
                self.flag_revealed[target.side] = True
            if is_hq(tr, tc) and side_of_cell(tr) != side:
                piece.locked = True
        elif result == "lose":
            piece.alive = False
            if piece.ptype == "siling":
                self.flag_revealed[side] = True
        else:  # draw
            piece.alive = False
            target.alive = False
            if piece.ptype == "siling":
                self.flag_revealed[side] = True
            if target.ptype == "siling":
                self.flag_revealed[target.side] = True
        if self.phase != "finished":
            self.turn = "black" if side == "red" else "red"
            if not self._has_movable("black"):
                self.winner = "red"
                self.phase = "finished"
            elif not self._has_movable("red"):
                self.winner = "black"
                self.phase = "finished"
        return self.last_battle

    def _has_movable(self, side: str) -> bool:
        return any(self.movable(p) for p in self.pieces.values() if p.side == side and p.alive)

    def ai_move(self, side: str) -> dict[str, Any] | None:
        """Pick a random legal move for side."""
        options: list[tuple[int, int, int, int]] = []
        for p in self.pieces.values():
            if p.side != side or not self.movable(p):
                continue
            # Collect highway neighbors + rail ends (sample).
            start = cell_key(p.r, p.c)
            cands: set[str] = set(HIGHWAY.get(start, ()))
            if not is_camp(p.r, p.c):
                # BFS railway destinations empty or enemy
                from collections import deque

                q = deque([start])
                seen = {start}
                while q:
                    cur = q.popleft()
                    for nb in RAILWAY.get(cur, ()):
                        if nb in seen:
                            continue
                        rr, cc = parse_key(nb)
                        occ = self.cell_piece(rr, cc)
                        if occ is not None and occ.side == side:
                            continue
                        seen.add(nb)
                        if occ is None or occ.side != side:
                            cands.add(nb)
                        if occ is None:
                            q.append(nb)
            for nb in cands:
                tr, tc = parse_key(nb)
                options.append((p.r, p.c, tr, tc))
        random.shuffle(options)
        for fr, fc, tr, tc in options:
            # Dry-run via copy is heavy; try_move mutates — use tentative
            snap = self._snapshot()
            ev = self.try_move(side, fr, fc, tr, tc)
            if ev is not None:
                return ev
            self._restore(snap)
        return None

    def _snapshot(self) -> dict[str, Any]:
        return {
            "pieces": {
                k: JunqiPiece(**{f: getattr(v, f) for f in v.__dataclass_fields__})
                for k, v in self.pieces.items()
            },
            "phase": self.phase,
            "turn": self.turn,
            "winner": self.winner,
            "flag_revealed": dict(self.flag_revealed),
            "layout_ready": dict(self.layout_ready),
            "last_battle": None if self.last_battle is None else dict(self.last_battle),
        }

    def _restore(self, snap: dict[str, Any]) -> None:
        self.pieces = snap["pieces"]
        self.phase = snap["phase"]
        self.turn = snap["turn"]
        self.winner = snap["winner"]
        self.flag_revealed = snap["flag_revealed"]
        self.layout_ready = snap["layout_ready"]
        self.last_battle = snap["last_battle"]

    def public_cells(self, viewer: str | None) -> list[dict[str, Any]]:
        """60 cells for client; hide enemy types unless revealed battle/flag."""
        out: list[dict[str, Any]] = []
        for r in range(ROWS):
            for c in range(COLS):
                kind = "hq" if is_hq(r, c) else ("camp" if is_camp(r, c) else "station")
                p = self.cell_piece(r, c)
                cell: dict[str, Any] = {"r": r, "c": c, "kind": kind, "piece": None}
                if p is not None:
                    show_type = p.ptype
                    if viewer and p.side != viewer:
                        show_type = "?"
                        if (
                            self.flag_revealed.get(p.side)
                            and p.ptype == "junqi"
                        ):
                            show_type = "junqi"
                    cell["piece"] = {
                        "side": p.side,
                        "type": show_type,
                        "locked": p.locked,
                    }
                out.append(cell)
        return out

    def to_detail(self, viewer: str | None = None) -> dict[str, Any]:
        return {
            "phase": self.phase,
            "turn": self.turn,
            "winner": self.winner,
            "flag_revealed": dict(self.flag_revealed),
            "layout_ready": dict(self.layout_ready),
            "last_battle": self.last_battle,
            "cells": self.public_cells(viewer),
            "board_rows": ROWS,
            "board_cols": COLS,
        }
