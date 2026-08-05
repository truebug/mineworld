"""Blackjack (21点) authority for the chess lounge — single player vs dealer.

KISS: one human (black seat) vs built-in dealer; 4-deck shoe; dealer stands
on all 17. No splits/doubles/insurance. Second sitter is rejected client-side
(white seat unused).
"""

from __future__ import annotations

import random

_RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
_SUITS = ["S", "H", "D", "C"]
_DECKS = 4


def _new_shoe() -> list[str]:
    shoe = [r + s for _ in range(_DECKS) for r in _RANKS for s in _SUITS]
    random.shuffle(shoe)
    return shoe


def hand_value(cards: list[str]) -> tuple[int, bool]:
    """(best total, soft?) — soft when an ace counts as 11."""
    total = 0
    aces = 0
    for card in cards:
        rank = card[:-1]
        if rank == "A":
            aces += 1
            total += 11
        elif rank in ("J", "Q", "K", "10"):
            total += 10
        else:
            total += int(rank)
    soft = False
    while total > 21 and aces > 0:
        total -= 10
        aces -= 1
    if aces > 0:
        soft = True
    return total, soft


class BlackjackBoard:
    """Authority state for one blackjack table."""

    def __init__(self) -> None:
        self.shoe: list[str] = _new_shoe()
        self.player: list[str] = []
        self.dealer: list[str] = []
        self.phase: str = "idle"  # idle | playing | finished
        self.result: str = ""  # win | lose | push | blackjack
        self.dealer_hole_hidden: bool = True

    def _draw(self) -> str:
        if len(self.shoe) < 15:
            self.shoe = _new_shoe()
        return self.shoe.pop()

    def deal(self) -> None:
        """Start a round: two cards each."""
        self.player = [self._draw(), self._draw()]
        self.dealer = [self._draw(), self._draw()]
        self.result = ""
        self.dealer_hole_hidden = True
        pv, _ = hand_value(self.player)
        if pv == 21:
            self.phase = "finished"
            self.dealer_hole_hidden = False
            dv, _ = hand_value(self.dealer)
            self.result = "push" if dv == 21 else "blackjack"
        else:
            self.phase = "playing"

    def hit(self) -> str | None:
        """Player draws one card; returns error code or None."""
        if self.phase != "playing":
            return "BJ_NOT_PLAYING"
        self.player.append(self._draw())
        pv, _ = hand_value(self.player)
        if pv > 21:
            self.phase = "finished"
            self.dealer_hole_hidden = False
            self.result = "lose"
        return None

    def stand(self) -> str | None:
        """Player stands; dealer plays out and result settles."""
        if self.phase != "playing":
            return "BJ_NOT_PLAYING"
        self.dealer_hole_hidden = False
        while True:
            dv, _ = hand_value(self.dealer)
            if dv < 17:
                self.dealer.append(self._draw())
            else:
                break
        pv, _ = hand_value(self.player)
        dv, _ = hand_value(self.dealer)
        if dv > 21 or pv > dv:
            self.result = "win"
        elif pv == dv:
            self.result = "push"
        else:
            self.result = "lose"
        self.phase = "finished"
        return None

    def resign(self) -> None:
        if self.phase == "playing":
            self.phase = "finished"
            self.dealer_hole_hidden = False
            self.result = "lose"

    def to_detail(self) -> dict:
        pv, _ = hand_value(self.player) if self.player else (0, False)
        if self.dealer_hole_hidden and self.dealer:
            dealer_cards = [self.dealer[0], "??"]
            dv, _ = hand_value([self.dealer[0]])
        else:
            dealer_cards = list(self.dealer)
            dv, _ = hand_value(self.dealer) if self.dealer else (0, False)
        return {
            "player_cards": list(self.player),
            "player_value": pv,
            "dealer_cards": dealer_cards,
            "dealer_value": dv,
            "phase": self.phase,
            "result": self.result,
        }
