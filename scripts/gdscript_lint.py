"""Lightweight GDScript footgun lint (no Godot needed).

Catches the bug class that caused the web black-void (2026-07-23):
`var x := <expr involving untyped Array elements / Variant>` fails type
inference at export/parse time. Full `--check-only` CI in a Linux container
is the long-term gate (docs/25); this lint is the fast local net.

Rules:
  GDL001  `var x := ...` where expr indexes an untyped Array/Dictionary
          or uses % with untyped operands — require explicit type.
Usage: python3 scripts/gdscript_lint.py [dir ...]  (default godot/spike/scripts)
Exit 1 if any finding.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

VAR_INFER = re.compile(r"^\s*var\s+(\w+)\s*:=\s*(.+?)\s*(?:#.*)?$")
# untyped containers: assigned from [] or {} or function params without types
UNSAFE_TOKENS = re.compile(r"(pts\[|layout\[|frames\[|\w+\[.+\]\s*[%+\-*/]|\bas\s+Array\b)")


def lint_file(path: Path) -> list[str]:
    findings: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return findings
    for no, line in enumerate(lines, 1):
        m = VAR_INFER.match(line)
        if not m:
            continue
        name, expr = m.group(1), m.group(2)
        # indexing an Array element then arithmetic → Variant math (the bi bug)
        if re.search(r"\w+\[[^\]]+\]\s*[-+*/%]", expr) and "float(" not in expr and "int(" not in expr and "Vector" not in expr:
            findings.append(f"{path}:{no}: GDL001 var {name} := Variant-array math; add explicit type")
        # modulo with untyped operand (not string-format: "..." % args)
        if (
            "%" in expr
            and not re.match(r'^"', expr)
            and not re.search(r"\b(int|float)\(", expr)
            and "." not in expr
        ):
            findings.append(f"{path}:{no}: GDL001 var {name} := possible Variant modulo; add explicit type")
    return findings


def main() -> int:
    roots = [Path(a) for a in sys.argv[1:]] or [Path("godot/spike/scripts")]
    all_findings: list[str] = []
    for root in roots:
        files = [root] if root.is_file() else sorted(root.rglob("*.gd"))
        for f in files:
            all_findings.extend(lint_file(f))
    for f in all_findings:
        print(f)
    print(f"gdscript_lint: {len(all_findings)} finding(s)")
    return 1 if all_findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
