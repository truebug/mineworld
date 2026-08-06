"""Blackjack (21点) authority for the chess lounge — multi-hand vs shared dealer.

Casino rules (KISS): every seated player gets an independent hand vs one
shared dealer; 4-deck shoe; dealer stands on all 17; players act in join
order (black seat first); no splits/doubles/insurance.

Phases: idle → playing (dealt, one active player) → finished (all players
bust/stand/blackjack, dealer played out, results settled per player).
Players joining mid-round watch until the next deal.
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
    """Authority state for one blackjack table (multi-hand, shared dealer)."""

    def __init__(self) -> None:
        self.shoe: list[str] = _new_shoe()
        self.players: list[str] = []  # join order (sids); set at deal time
        self.hands: dict[str, list[str]] = {}
        self.stands: set[str] = set()
        self.results: dict[str, str] = {}  # win | lose | push | blackjack
        self.dealer: list[str] = []
        self.active_idx: int = 0
        self.phase: str = "idle"  # idle | playing | finished
        self.dealer_hole_hidden: bool = True

    def _draw(self) -> str:
        if len(self.shoe) < 15:
            self.shoe = _new_shoe()
        return self.shoe.pop()

    @property
    def active_sid(self) -> str:
        if self.phase != "playing" or self.active_idx >= len(self.players):
            return ""
        return self.players[self.active_idx]

    def deal(self, sids: list[str]) -> None:
        """Deal two cards to every seated player + dealer; skip naturals."""
        self.players = list(sids)
        self.hands = {sid: [self._draw(), self._draw()] for sid in self.players}
        self.dealer = [self._draw(), self._draw()]
        self.stands = set()
        self.results = {}
        self.dealer_hole_hidden = True
        self.active_idx = 0
        self.phase = "playing"
        # Naturals (21 on deal) settle instantly, no action needed.
        for sid in self.players:
            pv, _ = hand_value(self.hands[sid])
            if pv == 21:
                self.results[sid] = "blackjack"
                self.stands.add(sid)
        self._advance()

    def _advance(self) -> None:
        """Move to next player still needing action; settle dealer when done."""
        while self.active_idx < len(self.players):
            sid = self.players[self.active_idx]
            if sid not in self.stands and sid not in self.results:
                return
            self.active_idx += 1
        self._settle_dealer()

    def _settle_dealer(self) -> None:
        """All players done → dealer plays out; settle each hand."""
        self.dealer_hole_hidden = False
        live = [sid for sid in self.players if self.results.get(sid) not in ("lose",)]
        # Dealer only needs to draw if someone can still win on points.
        need_draw = any(
            self.results.get(sid, "") not in ("blackjack", "lose") for sid in self.players
        )
        while need_draw:
            dv, _ = hand_value(self.dealer)
            if dv < 17:
                self.dealer.append(self._draw())
            else:
                break
        dv, _ = hand_value(self.dealer)
        dbj = dv == 21 and len(self.dealer) == 2
        for sid in self.players:
            if sid in self.results:
                if self.results[sid] == "blackjack" and dbj:
                    self.results[sid] = "push"
                continue
            pv, _ = hand_value(self.hands[sid])
            if dv > 21 or pv > dv:
                self.results[sid] = "win"
            elif pv == dv:
                self.results[sid] = "push"
            else:
                self.results[sid] = "lose"
        self.phase = "finished"

    def hit(self, sid: str) -> str | None:
        if self.phase != "playing":
            return "BJ_NOT_PLAYING"
        if sid != self.active_sid:
            return "BJ_NOT_YOUR_TURN"
        self.hands[sid].append(self._draw())
        pv, _ = hand_value(self.hands[sid])
        if pv > 21:
            self.results[sid] = "lose"
            self._advance()
        elif pv == 21:
            self.stands.add(sid)  # 21 stands automatically
            self._advance()
        return None

    def stand(self, sid: str) -> str | None:
        if self.phase != "playing":
            return "BJ_NOT_PLAYING"
        if sid != self.active_sid:
            return "BJ_NOT_YOUR_TURN"
        self.stands.add(sid)
        self._advance()
        return None

    def resign(self, sid: str) -> None:
        """Player forfeits their hand (counts as lose); may end round."""
        if self.phase != "playing" or sid not in self.hands:
            return
        self.results[sid] = "lose"
        self.stands.add(sid)
        if sid == self.active_sid:
            self._advance()
        elif all(s in self.stands or s in self.results for s in self.players):
            self._settle_dealer()

    def remove_player(self, sid: str) -> None:
        """Drop a leaving player's hand; advance if they were active."""
        if sid not in self.hands:
            return
        self.resign(sid)
        if self.phase != "playing":
            return
        self.players.remove(sid)
        self.hands.pop(sid, None)
        self.stands.discard(sid)
        self.results.pop(sid, None)
        if self.active_idx > 0:
            self.active_idx -= 1
        if not self.players:
            self.phase = "idle"
        else:
            self._advance()

    def to_detail(self) -> dict:
        if self.dealer_hole_hidden and self.dealer:
            dealer_cards = [self.dealer[0], "??"]
            dv, _ = hand_value([self.dealer[0]])
        else:
            dealer_cards = list(self.dealer)
            dv, _ = hand_value(self.dealer) if self.dealer else (0, False)
        values = {
            sid: hand_value(cards)[0] for sid, cards in self.hands.items()
        }
        # Back-compat single-player fields (first hand) for older clients.
        first = self.players[0] if self.players else None
        out = {
            "players": list(self.players),
            "hands": {sid: list(cards) for sid, cards in self.hands.items()},
            "hand_values": values,
            "active_sid": self.active_sid,
            "results": dict(self.results),
            "dealer_cards": dealer_cards,
            "dealer_value": dv,
            "phase": self.phase,
            "player_cards": list(self.hands.get(first, [])) if first else [],
            "player_value": values.get(first, 0),
            "result": self.results.get(first, "") if first else "",
        }
        return out
