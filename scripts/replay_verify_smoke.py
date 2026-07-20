"""Verify recordings API + frames joints for 2D/3D replay readiness (D8/V1d)."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def _get(url: str) -> bytes:
    """HTTP GET body bytes."""
    with urllib.request.urlopen(url, timeout=15) as resp:
        return resp.read()


def _check_frames_joints(frames_text: str, *, need_arm: bool) -> tuple[int, int, list[str]]:
    """Return (frame_count, frames_with_joints, sample_joint_names)."""
    n = 0
    with_j = 0
    names: list[str] = []
    for line in frames_text.splitlines():
        line = line.strip()
        if not line:
            continue
        n += 1
        frame = json.loads(line)
        state = frame.get("state") or {}
        for ent in state.get("entities") or []:
            joints = ent.get("joints") or {}
            if not joints:
                continue
            with_j += 1
            if not names:
                names = sorted(str(k) for k in joints.keys())
            break
    if need_arm:
        arm_keys = {"arm_yaw", "arm_shoulder", "arm_elbow", "gripper"}
        if not arm_keys.intersection(names):
            raise AssertionError(f"expected arm joints in frames, got {names}")
    return n, with_j, names


def main() -> int:
    """Smoke: list sessions, pick one, assert frames + optional arm joints."""
    parser = argparse.ArgumentParser(description="Replay / recordings verify smoke")
    parser.add_argument("--base", default="http://127.0.0.1:8080", help="serve_web origin")
    parser.add_argument(
        "--session",
        default="",
        help="session_id; default = newest from /api/recordings",
    )
    parser.add_argument(
        "--require-arm-joints",
        action="store_true",
        help="Fail if frames lack arm_yaw/shoulder/elbow/gripper",
    )
    parser.add_argument(
        "--min-frames",
        type=int,
        default=5,
        help="Minimum frames required",
    )
    args = parser.parse_args()
    base = args.base.rstrip("/")

    try:
        listing = json.loads(_get(f"{base}/api/recordings").decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"FAIL: cannot list recordings at {base}: {exc}", file=sys.stderr)
        print("Hint: bash scripts/serve_web.sh restart  (and have at least one session)", file=sys.stderr)
        return 1

    sessions = listing.get("sessions") or []
    if not sessions:
        # Fall back to examples sample for structural check
        sample = REPO / "examples" / "recordings" / "sample_frames.jsonl"
        if not sample.is_file():
            print("FAIL: no sessions and no examples/recordings/sample_frames.jsonl", file=sys.stderr)
            return 1
        text = sample.read_text(encoding="utf-8")
        n, with_j, names = _check_frames_joints(text, need_arm=False)
        print(f"replay verify OK (sample only) frames={n} with_joints={with_j} joints={names}")
        return 0

    sid = args.session
    if not sid:
        # Prefer a session that actually has frames (skip empty disconnects).
        for s in sessions:
            cand = str(s.get("session_id") or "")
            if not cand:
                continue
            nframes = s.get("num_frames")
            if nframes is not None and int(nframes) < args.min_frames:
                continue
            sid = cand
            break
        if not sid:
            sid = str(sessions[0].get("session_id") or "")
    if not sid:
        print("FAIL: empty session_id", file=sys.stderr)
        return 1

    try:
        header = json.loads(_get(f"{base}/api/recordings/{sid}").decode("utf-8"))
        frames_text = _get(f"{base}/api/recordings/{sid}/frames").decode("utf-8")
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"FAIL: fetch session {sid}: {exc}", file=sys.stderr)
        return 1

    need_arm = args.require_arm_joints or str(header.get("level_id") or "") == "demo_workshop"
    try:
        n, with_j, names = _check_frames_joints(frames_text, need_arm=need_arm)
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    if n < args.min_frames:
        print(f"FAIL: frames={n} < min {args.min_frames}", file=sys.stderr)
        return 1
    if with_j == 0:
        print("FAIL: no frames contain joints (3D arm/wheel replay will be static)", file=sys.stderr)
        return 1

    print(
        "replay verify OK "
        f"session={sid[:8]}… level={header.get('level_id')} outcome={header.get('outcome')} "
        f"frames={n} with_joints={with_j} joints={names[:8]}"
    )
    print(f"3D: {base}/?replay={sid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
