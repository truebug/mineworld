"""Gomoku (五子棋) board + heuristic AI — mirrors godot/spike/scripts/gomoku.gd."""
from __future__ import annotations

import random
from dataclasses import dataclass, field

SIZE = 15
EMPTY = 0
BLACK = 1
WHITE = 2

_DIRS = ((1, 0), (0, 1), (1, 1), (1, -1))


@dataclass
class GomokuBoard:
    """15×15 flat board with win check and white AI reply."""

    cells: list[int] = field(default_factory=lambda: [EMPTY] * (SIZE * SIZE))
    moves: list[list[int]] = field(default_factory=list)
    winner: int = EMPTY

    def reset(self) -> None:
        """Clear board and history."""
        self.cells = [EMPTY] * (SIZE * SIZE)
        self.moves.clear()
        self.winner = EMPTY

    def at(self, x: int, y: int) -> int:
        if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
            return -1
        return self.cells[y * SIZE + x]

    def place(self, x: int, y: int, color: int) -> bool:
        """Place a stone; False when illegal. Updates winner."""
        if self.winner != EMPTY or self.at(x, y) != EMPTY:
            return False
        self.cells[y * SIZE + x] = color
        self.moves.append([x, y, color])
        if self._line_len(x, y, color) >= 5:
            self.winner = color
        return True

    def is_full(self) -> bool:
        return len(self.moves) >= SIZE * SIZE

    def ai_move(self) -> tuple[int, int]:
        """White reply: best-scoring empty cell (attack biased)."""
        best = (-1, -1)
        best_score = -1.0
        for y in range(SIZE):
            for x in range(SIZE):
                if self.at(x, y) != EMPTY:
                    continue
                score = (
                    self._cell_score(x, y, WHITE) * 1.05
                    + self._cell_score(x, y, BLACK)
                    + random.random() * 3.0
                )
                if score > best_score:
                    best_score = score
                    best = (x, y)
        return best

    def snapshot_cells(self) -> list[int]:
        return list(self.cells)

    def _line_len(self, x: int, y: int, color: int) -> int:
        longest = 1
        for dx, dy in _DIRS:
            n = 1
            for sign in (1, -1):
                cx, cy = x + dx * sign, y + dy * sign
                while self.at(cx, cy) == color:
                    n += 1
                    cx += dx * sign
                    cy += dy * sign
            longest = max(longest, n)
        return longest

    def _cell_score(self, x: int, y: int, color: int) -> float:
        total = 0.0
        for dx, dy in _DIRS:
            n = 1
            open_ends = 0
            for sign in (1, -1):
                cx, cy = x + dx * sign, y + dy * sign
                while self.at(cx, cy) == color:
                    n += 1
                    cx += dx * sign
                    cy += dy * sign
                if self.at(cx, cy) == EMPTY:
                    open_ends += 1
            total += self._pattern_score(n, open_ends)
        return total

    @staticmethod
    def _pattern_score(run: int, open_ends: int) -> float:
        if run >= 5:
            return 10000000.0
        if open_ends == 0:
            return 0.0
        if run == 4:
            return 1000000.0 if open_ends == 2 else 120000.0
        if run == 3:
            return 9000.0 if open_ends == 2 else 1200.0
        if run == 2:
            return 320.0 if open_ends == 2 else 60.0
        return 4.0 if open_ends == 2 else 1.0
