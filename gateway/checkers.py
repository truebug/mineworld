"""Halma-style 跳棋 on 8×8 (2-player corner camps, step or jump)."""
from __future__ import annotations

import random
from dataclasses import dataclass, field

SIZE = 8
EMPTY = 0
BLACK = 1  # red camp — bottom-left
WHITE = 2  # blue camp — top-right

# 10-piece Halma corners
BLACK_HOME: tuple[tuple[int, int], ...] = (
    (0, 0),
    (1, 0),
    (2, 0),
    (3, 0),
    (0, 1),
    (1, 1),
    (2, 1),
    (0, 2),
    (1, 2),
    (0, 3),
)
WHITE_HOME: tuple[tuple[int, int], ...] = (
    (7, 7),
    (6, 7),
    (5, 7),
    (4, 7),
    (7, 6),
    (6, 6),
    (5, 6),
    (7, 5),
    (6, 5),
    (7, 4),
)

_DIRS = tuple(
    (dx, dy)
    for dx in (-1, 0, 1)
    for dy in (-1, 0, 1)
    if not (dx == 0 and dy == 0)
)


@dataclass
class CheckersBoard:
    """8×8 Halma: step to adjacent empty, or jump over a neighbor."""

    cells: list[int] = field(default_factory=list)
    winner: int = EMPTY
    moves: list[list[int]] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.cells:
            self.reset()

    def reset(self) -> None:
        """Place both camps; clear winner."""
        self.cells = [EMPTY] * (SIZE * SIZE)
        for x, y in BLACK_HOME:
            self.cells[y * SIZE + x] = BLACK
        for x, y in WHITE_HOME:
            self.cells[y * SIZE + x] = WHITE
        self.winner = EMPTY
        self.moves.clear()

    def at(self, x: int, y: int) -> int:
        if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
            return -1
        return self.cells[y * SIZE + x]

    def _set(self, x: int, y: int, color: int) -> None:
        self.cells[y * SIZE + x] = color

    def snapshot_cells(self) -> list[int]:
        return list(self.cells)

    def win_line(self) -> list[list[int]]:
        """Unused for Halma; keep API parity with gomoku."""
        return []

    def home_for(self, color: int) -> tuple[tuple[int, int], ...]:
        return WHITE_HOME if color == BLACK else BLACK_HOME

    def try_move(self, fx: int, fy: int, tx: int, ty: int, color: int) -> bool:
        """Apply one step or one jump; update winner. False if illegal."""
        if self.winner != EMPTY:
            return False
        if self.at(fx, fy) != color or self.at(tx, ty) != EMPTY:
            return False
        dx, dy = tx - fx, ty - fy
        adx, ady = abs(dx), abs(dy)
        # Adjacent step (8-way).
        if adx <= 1 and ady <= 1 and (adx + ady) > 0:
            self._set(fx, fy, EMPTY)
            self._set(tx, ty, color)
            self.moves.append([fx, fy, tx, ty, color])
            self._check_win(color)
            return True
        # Single jump: ±2 along 8-way axes; mid must be occupied.
        if adx in (0, 2) and ady in (0, 2) and max(adx, ady) == 2:
            mx, my = fx + dx // 2, fy + dy // 2
            if self.at(mx, my) <= EMPTY:
                return False
            self._set(fx, fy, EMPTY)
            self._set(tx, ty, color)
            self.moves.append([fx, fy, tx, ty, color])
            self._check_win(color)
            return True
        return False

    def legal_moves(self, color: int) -> list[tuple[int, int, int, int]]:
        """All step + jump moves for color."""
        out: list[tuple[int, int, int, int]] = []
        for y in range(SIZE):
            for x in range(SIZE):
                if self.at(x, y) != color:
                    continue
                for dx, dy in _DIRS:
                    sx, sy = x + dx, y + dy
                    if self.at(sx, sy) == EMPTY:
                        out.append((x, y, sx, sy))
                    jx, jy = x + 2 * dx, y + 2 * dy
                    if self.at(sx, sy) > EMPTY and self.at(jx, jy) == EMPTY:
                        out.append((x, y, jx, jy))
        return out

    def ai_move(self) -> tuple[int, int, int, int] | None:
        """White reply: prefer moves that enter/near BLACK_HOME."""
        moves = self.legal_moves(WHITE)
        if not moves:
            return None
        home = set(BLACK_HOME)

        def score(m: tuple[int, int, int, int]) -> float:
            _fx, _fy, tx, ty = m
            s = 0.0
            if (tx, ty) in home:
                s += 100.0
            # Closer to black home centroid (1.0, 1.0).
            s -= abs(tx - 1.0) + abs(ty - 1.0)
            s += random.random() * 0.3
            return s

        return max(moves, key=score)

    def _check_win(self, color: int) -> None:
        target = self.home_for(color)
        for x, y in target:
            if self.at(x, y) != color:
                return
        self.winner = color
