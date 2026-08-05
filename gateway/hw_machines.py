"""HW-0: hw_fake real-machine sim backend — public machine profiles (ADR-004).

Pure kinematics: joint_targets are integrated toward with per-joint rate
limits, then clamped to soft limits. No deployment info lives here; the
closed external arm-bridge keeps credentials/endpoints out of this repo.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class HwJoint:
    """One joint of a real-machine profile (public mechanical params)."""

    name: str
    home: float  # rad
    lo: float  # soft limit min, rad
    hi: float  # soft limit max, rad
    max_rate: float  # rad/s


@dataclass(frozen=True)
class HwProfile:
    """A real-machine profile: ordered joints + display metadata."""

    machine_id: str
    joints: tuple[HwJoint, ...]

    @property
    def joint_names(self) -> list[str]:
        return [j.name for j in self.joints]


## SO-101 6-DoF desktop arm (Feetech STS bus): public URDF-class params.
## Radians, Z-up base frame; home = relaxed upright pose.
SO101 = HwProfile(
    machine_id="so101",
    joints=(
        HwJoint("shoulder_pan", home=0.0, lo=-1.92, hi=1.92, max_rate=0.9),
        HwJoint("shoulder_lift", home=0.3, lo=-1.75, hi=1.75, max_rate=0.9),
        HwJoint("elbow_flex", home=-1.2, lo=-1.69, hi=1.69, max_rate=0.9),
        HwJoint("wrist_flex", home=0.9, lo=-1.66, hi=1.66, max_rate=1.2),
        HwJoint("wrist_roll", home=0.0, lo=-2.74, hi=2.74, max_rate=1.6),
        HwJoint("gripper", home=0.4, lo=-0.17, hi=1.75, max_rate=1.6),
    ),
)

HW_PROFILES: dict[str, HwProfile] = {p.machine_id: p for p in (SO101,)}


@dataclass
class HwArmSim:
    """Kinematic arm state: goals chase targets at max_rate, clamped to limits."""

    profile: HwProfile
    present: dict[str, float] = field(default_factory=dict)
    target: dict[str, float] = field(default_factory=dict)
    enabled: bool = False

    def __post_init__(self) -> None:
        if not self.present:
            self.present = {j.name: j.home for j in self.profile.joints}
        if not self.target:
            self.target = dict(self.present)

    def clamp(self, name: str, value: float) -> float:
        jnt = next(j for j in self.profile.joints if j.name == name)
        return max(jnt.lo, min(jnt.hi, value))

    def set_targets(self, targets: dict[str, float]) -> None:
        for name, value in targets.items():
            self.target[name] = self.clamp(name, float(value))

    def go_home(self) -> None:
        self.target = {j.name: j.home for j in self.profile.joints}

    def step(self, dt: float) -> None:
        if not self.enabled:
            return
        rates = {j.name: j.max_rate for j in self.profile.joints}
        for name, goal in self.target.items():
            cur = self.present[name]
            rate = rates[name]
            delta = goal - cur
            step = max(-rate * dt, min(rate * dt, delta))
            self.present[name] = self.clamp(name, cur + step)

    def joint_vels(self) -> dict[str, float]:
        rates = {j.name: j.max_rate for j in self.profile.joints}
        out: dict[str, float] = {}
        for name, goal in self.target.items():
            if not self.enabled:
                out[name] = 0.0
                continue
            cur = self.present[name]
            delta = goal - cur
            rate = rates[name]
            out[name] = max(-rate, min(rate, delta * 50.0))
        return out
