"""AI race driver v0 (pure pursuit, no learning).

Connects as a regular WS client — same protocol as a human (T4.5 proof:
human/AI interchangeable over one contract). Reads own pose from state,
steers toward a lookahead point on the race centerline, throttles by
upcoming curvature.

Usage:
  .venv/bin/python scripts/ai_driver.py [--url ws://127.0.0.1:8765] [--seconds 30]

Requires: godot/spike/data/race_layout.json (centerline, MW Z-up meters).
Verify: prints progress (centerline index advances) and lap time if finished.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import sys
from pathlib import Path

import websockets

LAYOUT = Path(__file__).resolve().parents[1] / "godot" / "spike" / "data" / "race_layout.json"
CMD_HZ = 20.0
LOOKAHEAD_M = 8.0
V_TARGET_FAST = 14.0   # m/s on straights
V_TARGET_SLOW = 5.0    # m/s in sharp corners
STEER_KP = 1.4


def load_centerline() -> list[tuple[float, float]]:
    data = json.loads(LAYOUT.read_text(encoding="utf-8"))
    return [(float(p["x"]), float(p["y"])) for p in data["centerline"]]


def nearest_idx(pts: list[tuple[float, float]], x: float, y: float, hint: int, window: int = 30) -> int:
    """Nearest centerline index within ±window of hint (avoids full scan)."""
    n = len(pts)
    best, best_d = hint, float("inf")
    for off in range(-window, window + 1):
        i = (hint + off) % n
        d = (pts[i][0] - x) ** 2 + (pts[i][1] - y) ** 2
        if d < best_d:
            best, best_d = i, d
    return best


def curvature_ahead(pts: list[tuple[float, float]], idx: int, span: int = 6) -> float:
    """Max heading change (rad) over the next `span` segments."""
    n = len(pts)
    worst = 0.0
    for k in range(span):
        a = pts[(idx + k) % n]
        b = pts[(idx + k + 1) % n]
        c = pts[(idx + k + 2) % n]
        v1 = (b[0] - a[0], b[1] - a[1])
        v2 = (c[0] - b[0], c[1] - b[1])
        a1 = math.atan2(v1[1], v1[0])
        a2 = math.atan2(v2[1], v2[0])
        turn = abs((a2 - a1 + math.pi) % (2 * math.pi) - math.pi)
        worst = max(worst, turn)
    return worst


async def drive(
    url: str,
    seconds: float,
    room: str = "",
    name: str = "AI Driver v0",
    bot: bool = False,
    forever: bool = False,
) -> int:
    pts = load_centerline()
    n = len(pts)
    async with websockets.connect(url) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        sid = hello["session_id"]
        join_payload: dict = {"level_id": "demo_race", "player_name": name}
        if room:
            join_payload["room_id"] = room
        if bot:
            join_payload["extensions"] = {"mw": {"profile": {"bot": True, "id": "ai-driver-v0"}}}
        await ws.send(json.dumps({
            "type": "join", "session_id": sid,
            "payload": join_payload,
        }))
        entity = None
        hint = 0
        lap_start_t = None
        accum_progress = 0.0
        x = y = yaw = 0.0
        t_sim = 0.0
        progress_marks: list[int] = []

        async def send_cmd(throttle: float, brake: float, steer: float) -> None:
            await ws.send(json.dumps({
                "type": "cmd", "session_id": sid,
                "payload": {
                    "entity_id": entity, "control_mode": "drive",
                    "throttle": round(throttle, 3), "brake": round(brake, 3),
                    "steer": round(steer, 3), "handbrake": 0.0,
                },
            }))

        deadline = (
            float("inf") if forever else asyncio.get_event_loop().time() + seconds
        )
        last_cmd = 0.0
        while asyncio.get_event_loop().time() < deadline:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=5)
            except asyncio.TimeoutError:
                break
            msg = json.loads(raw)
            mtype = msg.get("type")
            if mtype == "scene":
                ents = msg["payload"]["entities"]
                entity = next(
                    (e["entity_id"] for e in ents if e.get("controllable")),
                    ents[0]["entity_id"],
                )
                await ws.send(json.dumps({
                    "type": "cmd", "session_id": sid,
                    "payload": {"action": "take_control", "entity_id": entity},
                }))
                print(f"joined, controlling {entity}")
            elif mtype == "state" and entity:
                t_sim = float(msg.get("t_sim", 0.0))
                mine = next(
                    (e for e in msg["payload"]["entities"] if e.get("entity_id") == entity),
                    None,
                )
                if mine is None:
                    continue
                pose = mine["base_pose"]
                x, y, yaw = float(pose["x"]), float(pose["y"]), float(pose["yaw"])
                now = asyncio.get_event_loop().time()
                if now - last_cmd < 1.0 / CMD_HZ:
                    continue
                last_cmd = now
                prev_hint = hint
                hint = nearest_idx(pts, x, y, hint)
                progress_marks.append(hint)
                # Accumulate forward progress in index space (wrap-aware) so a
                # lap = full traversal, not just index comparison.
                delta_idx = hint - prev_hint
                if delta_idx < -n // 2:
                    delta_idx += n
                elif delta_idx > n // 2:
                    delta_idx -= n
                accum_progress += max(0, delta_idx)
                if lap_start_t is None and accum_progress > 5:
                    lap_start_t = t_sim
                    accum_progress = 0
                # lookahead target
                step = max(1.0, (pts[(hint + 1) % n][0] - pts[hint][0]) ** 2
                           + (pts[(hint + 1) % n][1] - pts[hint][1]) ** 2) ** 0.5
                ahead = int(max(2, LOOKAHEAD_M / max(step, 0.5)))
                tx, ty = pts[(hint + ahead) % n]
                # pure pursuit steering: heading error in body frame
                desired = math.atan2(ty - y, tx - x)
                err = (desired - yaw + math.pi) % (2 * math.pi) - math.pi
                steer = max(-1.0, min(1.0, STEER_KP * err))
                # speed by upcoming curvature
                curv = curvature_ahead(pts, hint)
                v_target = V_TARGET_SLOW if curv > 0.5 else (
                    V_TARGET_FAST - min(1.0, curv) * (V_TARGET_FAST - V_TARGET_SLOW)
                )
                vx, vy = (float(mine["velocities"]["vx"]), float(mine["velocities"]["vy"]))
                speed = math.hypot(vx, vy)
                throttle = brake = 0.0
                if speed < v_target - 0.5:
                    throttle = 1.0 if curv < 0.3 else 0.6
                elif speed > v_target + 1.0:
                    brake = 0.8
                await send_cmd(throttle, brake, steer)
                if len(progress_marks) % 100 == 0:
                    print(f"t={t_sim:.1f}s idx={hint}/{n} speed={speed:.1f}m/s steer={steer:+.2f}")
                # lap detection: accumulated a full centerline traversal
                if lap_start_t is not None and accum_progress >= n * 0.95:
                    print(f"LAP DONE in {t_sim - lap_start_t:.1f}s (verified full traversal)")
                    if forever:
                        lap_start_t = None
                        accum_progress = 0.0
                    else:
                        return 0
        span = (max(progress_marks) - min(progress_marks)) if progress_marks else 0
        print(f"progress: centerline span {span}/{n} idx over {seconds}s")
        ok = span > n * 0.15  # covered at least 15% of the lap
        print("AI DRIVER", "PASS" if ok else "FAIL")
        return 0 if ok else 1


async def drive_forever(
    url: str, room: str, name: str, bot: bool, retry_s: float = 3.0
) -> int:
    """Resident bot loop: reconnect + rejoin on any drop (gateway restart, room full)."""
    while True:
        try:
            await drive(url, 0.0, room=room, name=name, bot=bot, forever=True)
        except (OSError, websockets.WebSocketException, asyncio.TimeoutError) as err:
            print(f"connection dropped: {err!r} — retry in {retry_s:.0f}s")
        await asyncio.sleep(retry_s)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="ws://127.0.0.1:8765")
    ap.add_argument("--seconds", type=float, default=45.0)
    ap.add_argument("--room", default="", help="shared room id (empty = private)")
    ap.add_argument("--name", default="AI Driver v0")
    ap.add_argument("--bot", action="store_true", help="mark session as bot (skip recording)")
    ap.add_argument("--forever", action="store_true", help="resident mode: laps + reconnect loop")
    args = ap.parse_args()
    if args.forever:
        raise SystemExit(asyncio.run(drive_forever(args.url, args.room, args.name, args.bot)))
    raise SystemExit(
        asyncio.run(drive(args.url, args.seconds, room=args.room, name=args.name, bot=args.bot))
    )


if __name__ == "__main__":
    main()
