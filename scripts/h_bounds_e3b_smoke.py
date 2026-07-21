#!/usr/bin/env python3
"""Smoke: Hub walkable AABB clamp (H-bounds) + workshop space_id join (E3b)."""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

import websockets

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "gateway"))
from echo_server import (  # noqa: E402
    _hub_walkable_aabbs,
    _nearest_aabb_point,
    _point_in_aabb,
)

CONTRACT = ROOT / "examples" / "contracts" / "demo_hub.json"


def _load_bounds() -> tuple[float, float, list[dict]]:
    data = json.loads(CONTRACT.read_text(encoding="utf-8"))
    bounds = data["extensions"]["mw"]["bounds"]
    half_x = float(bounds["half_x"])
    half_y = float(bounds["half_y"])
    walkable = _hub_walkable_aabbs(bounds, half_x, half_y)
    return half_x, half_y, walkable


def _test_walkable_projection() -> None:
    """Void between south berth pads must project onto a walkable AABB."""
    _half_x, _half_y, walkable = _load_bounds()
    assert walkable, "demo_hub.json missing bounds.walkable"
    # Gap between RingS_L and RingS_M (dock notch), MW coords.
    void_x, void_y = -12.0, -32.0
    assert not any(
        _point_in_aabb(void_x, void_y, b) for b in walkable
    ), "expected dock void outside walkable"
    nx, ny = _nearest_aabb_point(void_x, void_y, walkable)
    assert any(_point_in_aabb(nx, ny, b) for b in walkable), f"projected ({nx},{ny}) still void"
    print(f"hub walkable projection OK · void ({void_x},{void_y}) → ({nx:.2f},{ny:.2f})")


async def _hub_live_clamp(url: str) -> None:
    """Drive avatar toward south-west; pose must remain inside walkable."""
    _half_x, _half_y, walkable = _load_bounds()
    async with websockets.connect(url) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert hello.get("type") == "hello", hello
        sid = hello["session_id"]
        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": sid,
                    "payload": {
                        "level_id": "demo_hub",
                        "player_name": "bounds",
                        "room_id": f"hub-bounds-{sid[:8]}",
                        "extensions": {"mw": {"profile": {"id": "smoke-bounds", "nickname": "B"}}},
                    },
                }
            )
        )
        scene = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert scene.get("type") == "scene", scene
        eid = None
        for ent in scene.get("payload", {}).get("entities", []):
            if str(ent.get("entity_id", "")).startswith("avatar_"):
                eid = ent["entity_id"]
                break
        assert eid, scene
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "take_control", "entity_id": eid},
                }
            )
        )
        for _ in range(120):
            await ws.send(
                json.dumps(
                    {
                        "type": "cmd",
                        "session_id": sid,
                        "payload": {
                            "action": "set_velocity",
                            "entity_id": eid,
                            "vx": -3.0,
                            "vy": -3.0,
                            "yaw_rate": 0.0,
                        },
                    }
                )
            )
            await asyncio.sleep(0.04)
        x = y = None
        deadline = asyncio.get_event_loop().time() + 3.0
        while asyncio.get_event_loop().time() < deadline:
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            if msg.get("type") != "state":
                continue
            for ent in msg.get("payload", {}).get("entities", []):
                if ent.get("entity_id") == eid:
                    pose = ent.get("base_pose") or {}
                    x = float(pose.get("x", 0))
                    y = float(pose.get("y", 0))
            if x is not None:
                break
        assert x is not None and y is not None, "no state pose"
        assert any(
            _point_in_aabb(x, y, b) for b in walkable
        ), f"pose ({x:.2f},{y:.2f}) outside walkable"
        print(f"hub live clamp OK · ({x:.2f}, {y:.2f})")


async def _workshop_space_id(url: str) -> None:
    """Join demo_workshop with space_id; expect scene ack (gateway accepts attribution)."""
    space_id = "mw-gallery-demo"
    async with websockets.connect(url) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        sid = hello["session_id"]
        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": sid,
                    "payload": {
                        "level_id": "demo_workshop",
                        "player_name": "attrib",
                        "room_id": f"ws-e3b-{sid[:8]}",
                        "extensions": {
                            "mw": {
                                "space_id": space_id,
                                "route_kind": "pms_space",
                                "profile": {"id": "smoke-e3b", "nickname": "E3b"},
                            }
                        },
                    },
                }
            )
        )
        scene = json.loads(await asyncio.wait_for(ws.recv(), timeout=8))
        assert scene.get("type") == "scene", scene
        print(f"e3b space_id join OK · space_id={space_id}")


async def main() -> int:
    url = sys.argv[1] if len(sys.argv) > 1 else "ws://127.0.0.1:8765"
    _test_walkable_projection()
    await _hub_live_clamp(url)
    await _workshop_space_id(url)
    print("h_bounds_e3b smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
