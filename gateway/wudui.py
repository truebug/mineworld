"""五对 (WuDui / 5-Pairs) authority for the chess lounge — two-player pair-race.

Rules (SSOT):
- 54-card deck (A..K ×4 + jokers ×2). Both players dealt 10; first player
  gets 1 extra (11). All cards paired (five pairs) → win; "天和" if the
  extra card completes it immediately at deal.
- First player turn: MUST discard one unmatched card; if the remaining hand
  is exactly five pairs → win. Then draws one card (back to 11).
- Second player turn: may EAT the discarded card (pairing it with an
  unmatched card in hand, then MUST discard one unmatched card) or PASS
  (draw one card, then MUST discard one unmatched card).
- Win: a hand becomes exactly five pairs (five_pairs / tianhe); or resign.
"""

from __future__ import annotations

import random

_RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
_SUITS = ["S", "H", "D", "C"]
_TEN_HANDS = 10


def _new_deck() -> list[str]:
    deck = [r + s for _ in range(4) for r in _RANKS for s in _SUITS]
    deck += ["JOKER", "JOKER"]
    random.shuffle(deck)
    return deck


def rank_of(card: str) -> str:
    return "JOKER" if card == "JOKER" else card[:-1]


class WuDuiBoard:
    """Authority state for one 五对 table."""

    def __init__(self) -> None:
        self.deck: list[str] = _new_deck()
        self.black: list[str] = []  # first player (black seat)
        self.red: list[str] = []    # second player (red seat)
        self.discard_pile: list[str] = []  # last discarded card (face up)
        self.phase: str = "idle"  # idle | playing | finished
        self.turn: str = "black"  # black | red
        self.winner: str = ""     # black | red
        self.reason: str = ""
        self.last_action: str = "deal"

    def _draw(self) -> str:
        if len(self.deck) < 4:
            self.deck = _new_deck()
        return self.deck.pop()

    def _unmatched(self, hand: list[str]) -> list[str]:
        """Cards not yet part of a pair (odd counts by rank)."""
        by_rank: dict[str, int] = {}
        for c in hand:
            by_rank[rank_of(c)] = by_rank.get(rank_of(c), 0) + 1
        return [c for c in hand if by_rank[rank_of(c)] % 2 == 1]

    def _pairs_count(self, hand: list[str]) -> int:
        by_rank: dict[str, int] = {}
        for c in hand:
            by_rank[rank_of(c)] = by_rank.get(rank_of(c), 0) + 1
        return sum(n // 2 for n in by_rank.values())

    def _discardable(self, hand: list[str]) -> list[str]:
        if len(hand) <= 1:
            return []
        return self._unmatched(hand)

    def deal(self) -> None:
        """Deal 10 each, first player +1; immediate 天和 check."""
        self.deck = _new_deck()
        self.black = [self._draw() for _ in range(_TEN_HANDS)]
        self.red = [self._draw() for _ in range(_TEN_HANDS)]
        self.black.append(self._draw())
        self.discard_pile = []
        self.turn = "black"
        self.phase = "playing"
        self.winner = ""
        self.reason = ""
        self.last_action = "deal"
        if not self._unmatched(self.black):
            self.phase = "finished"
            self.winner = "black"
            self.reason = "tianhe"
            self.last_action = "win"

    def _finish_if_paired(self, side: str) -> bool:
        hand = self.black if side == "black" else self.red
        if not self._unmatched(hand):
            self.phase = "finished"
            self.winner = side
            self.reason = "tianhe" if side == "black" and self.last_action == "deal" else "five_pairs"
            self.last_action = "win"
            return True
        return False

    def discard(self, card: str) -> str | None:
        """First player discards an unmatched card, then draws one."""
        if self.phase != "playing" or self.turn != "black":
            return "WUDUI_NOT_TURN"
        if card not in self.black:
            return "WUDUI_BAD_CARD"
        if card not in self._discardable(self.black):
            return "WUDUI_NOT_UNMATCHED"
        self.black.remove(card)
        self.discard_pile.append(card)
        if self._finish_if_paired("black"):
            return None
        self.black.append(self._draw())
        self.turn = "red"
        self.last_action = "discard"
        return None

    def eat(self, card: str, discard_card: str) -> str | None:
        """Second player eats the top discard, pairs it, discards one unmatched."""
        if self.phase != "playing" or self.turn != "red":
            return "WUDUI_NOT_TURN"
        if not self.discard_pile:
            return "WUDUI_NO_DISCARD"
        if card != self.discard_pile[-1]:
            return "WUDUI_BAD_EAT"
        unmatched_ranks = {rank_of(c) for c in self._unmatched(self.red)}
        if rank_of(card) not in unmatched_ranks:
            return "WUDUI_CANNOT_EAT"
        if discard_card not in self._discardable(self.red):
            return "WUDUI_BAD_DISCARD"
        self.red.append(card)
        self.discard_pile = []
        if discard_card not in self.red:
            return "WUDUI_BAD_DISCARD"
        self.red.remove(discard_card)
        self.discard_pile.append(discard_card)
        if self._finish_if_paired("red"):
            return None
        self.turn = "black"
        self.last_action = "eat"
        return None

    def pass_turn(self, discard_card: str) -> str | None:
        """Second player passes: draws one, then discards one unmatched."""
        if self.phase != "playing" or self.turn != "red":
            return "WUDUI_NOT_TURN"
        self.discard_pile = []
        self.red.append(self._draw())
        if self._finish_if_paired("red"):
            return None
        if discard_card not in self._discardable(self.red):
            return "WUDUI_BAD_DISCARD"
        self.red.remove(discard_card)
        self.discard_pile.append(discard_card)
        if self._finish_if_paired("red"):
            return None
        self.turn = "black"
        self.last_action = "pass"
        return None

    def resign(self, side: str) -> None:
        if self.phase == "playing":
            self.phase = "finished"
            self.winner = "red" if side == "black" else "black"
            self.reason = "resign"

    def to_detail(self) -> dict:
        return {
            "black_cards": list(self.black),
            "red_cards": list(self.red),
            "discard_pile": list(self.discard_pile),
            "phase": self.phase,
            "turn": self.turn,
            "winner": self.winner,
            "reason": self.reason,
            "last_action": self.last_action,
            "black_pairs": self._pairs_count(self.black),
            "red_pairs": self._pairs_count(self.red),
        }
