"""Fetch CC0 3D assets per scene manifest + auto-write ASSETS.md ledger entries.

Sources (all scriptable, verified 2026-08-21):
  kenney:<slug>     — kenney.nl asset page, zip URL scraped from #donate-text
  polyhaven:<slug>  — api.polyhaven.com/files/<slug> (gltf)
  ambientcg:<id>    — ambientcg.com API v2 downloadData zip

Usage:
  python scripts/fetch_cc0_assets.py --list
  python scripts/fetch_cc0_assets.py --scene chessroom --dry-run
  python scripts/fetch_cc0_assets.py --scene chessroom --scene workshop
License guardrail: CC0/MIT only; CC-BY requires explicit allow flag (docs/07 §8.2).
"""
from __future__ import annotations

import argparse
import io
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ASSETS_DIR = REPO / "godot" / "spike" / "assets"
LEDGER = REPO / "ASSETS.md"

# Scene manifest: chessroom + workshop density (docs/38 层3 道具线).
MANIFEST: dict[str, list[dict]] = {
    "chessroom": [
        {
            "name": "kenney_furniture",
            "source": "kenney:furniture-kit",
            "license": "CC0 1.0",
            "url": "https://kenney.nl/assets/furniture-kit",
            "role": "棋牌室桌椅/沙发/茶几/地毯 props",
            # Zip layout: "Models/GLTF format/<file>.glb"
            "include": [
                "table", "tableCross", "chair", "chairCushion", "chairModernCushion",
                "loungeSofa", "loungeChair", "rugRound", "rugRectangle",
                "tableCoffee", "lampRoundFloor", "bookcaseOpen", "plantSmall1",
            ],
            "date": "2026-08-21",
        },
        {
            "name": "polyhaven_chinese_furniture",
            "source": "polyhaven:models",
            "license": "CC0 1.0",
            "url": "https://polyhaven.com/models",
            "role": "棋牌室中式家具（茶桌/太师椅/沙发/条案）",
            "models": [
                "chinese_tea_table", "chinese_armchair", "chinese_sofa",
                "chinese_console_table",
            ],
            "res": "1k",
            "date": "2026-08-21",
        },
    ],
    "workshop": [
        {
            "name": "ambientcg_floor",
            "source": "ambientcg:materials",
            "license": "CC0 1.0",
            "url": "https://ambientcg.com",
            "role": "工坊地面/台面 PBR 材质（混凝土/金属/防滑板）",
            "material_ids": ["Concrete034", "Metal032", "Tiles074"],
            "res": "1K-JPG",
            "date": "2026-08-21",
        },
    ],
}

def fetch(url: str, timeout: int = 90) -> bytes:
    """curl-based fetch: robust CONNECT proxying via Clash (env http_proxy)."""
    last: Exception | None = None
    for _ in range(3):
        try:
            out = subprocess.run(
                ["curl", "-sfL", "--max-time", str(timeout),
                 "-A", "mineworld-asset-fetch/1.0", url],
                capture_output=True, check=True, timeout=timeout + 15,
            )
            return out.stdout
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            last = exc
    raise RuntimeError(f"fetch failed after 3 tries: {url}: {last}")


def resolve_kenney_zip(slug: str) -> str:
    """Kenney asset page → zip URL hidden in the #donate-text link."""
    html = fetch(f"https://kenney.nl/assets/{slug}").decode("utf-8", "replace")
    m = re.search(r"id='donate-text' href='([^']+\.zip)'", html)
    if not m:
        raise RuntimeError(f"kenney:{slug}: zip link not found on page")
    return m.group(1)


def select_kenney_models(zf: zipfile.ZipFile, include: list[str]) -> dict[str, bytes]:
    """Pick GLB files whose stem matches any include token, plus License."""
    out: dict[str, bytes] = {}
    for info in zf.infolist():
        name = info.filename
        base = Path(name).name
        if base.lower() == "license.txt":
            out["License.txt"] = zf.read(info)
            continue
        if not name.endswith(".glb") or "/GLTF format/" not in name:
            continue
        stem = Path(name).stem.lower()
        if any(tok.lower() in stem for tok in include):
            out[base] = zf.read(info)
    return out


def fetch_ambientcg(mat_id: str, res: str) -> tuple[str, bytes]:
    """ambientCG: canonical download URL (verified via API downloadData)."""
    zip_url = f"https://ambientcg.com/get?file={mat_id}_{res}.zip"
    return zip_url, fetch(zip_url)


def write_pack_readme(pack_dir: Path, item: dict, files: list[str]) -> None:
    lines = [
        f"# {item['name']} (subset)",
        "",
        "| 字段 | 值 |",
        "|------|-----|",
        f"| Source | {item['url']} |",
        f"| License | {item['license']}（见包内 `License.txt` 或来源站条款） |",
        f"| Role | {item['role']} |",
        "",
        "## Included files",
        "",
    ] + [f"- `{f}`" for f in files] + [""]
    (pack_dir / "ASSETS.md").write_text("\n".join(lines), encoding="utf-8")


def append_ledger(item: dict, pack_dir: Path) -> None:
    """Append one row to root ASSETS.md 台账 (idempotent by pack name)."""
    text = LEDGER.read_text(encoding="utf-8")
    if item["name"] in text:
        return
    row = (
        f"| {item['name']}（fetch_cc0_assets.py 自动入库） | {item['url']} "
        f"| {item['license']} | {item['role']}；`godot/spike/assets/{pack_dir.name}/`（见目录 ASSETS.md） "
        f"| 无 | {item['date']} |"
    )
    # Insert after the 台账 table header rows.
    marker = "|------|------|------|------|------|------|\n"
    idx = text.find(marker)
    if idx < 0:
        text += "\n" + row + "\n"
    else:
        text = text[: idx + len(marker)] + row + "\n" + text[idx + len(marker):]
    LEDGER.write_text(text, encoding="utf-8")


def process_item(item: dict, dry_run: bool) -> None:
    src = item["source"]
    pack_dir = ASSETS_DIR / item["name"]
    if src.startswith("kenney:"):
        zip_url = resolve_kenney_zip(src.split(":", 1)[1])
        zf = zipfile.ZipFile(io.BytesIO(fetch(zip_url)))
        files = select_kenney_models(zf, item["include"])
        if not files:
            raise RuntimeError(f"{item['name']}: no files matched include list")
        if dry_run:
            print(f"[dry] {item['name']}: {len(files)} files from {zip_url}")
            return
        pack_dir.mkdir(parents=True, exist_ok=True)
        for fname, blob in files.items():
            (pack_dir / fname).write_bytes(blob)
        write_pack_readme(pack_dir, item, sorted(files))
        append_ledger(item, pack_dir)
        print(f"OK {item['name']}: {len(files)} files → {pack_dir}")
    elif src == "ambientcg:materials":
        got = []
        for mid in item["material_ids"]:
            url, blob = fetch_ambientcg(mid, item["res"])
            if dry_run:
                print(f"[dry] {mid}: {len(blob)//1024}KB from {url}")
                continue
            zf = zipfile.ZipFile(io.BytesIO(blob))
            mat_dir = pack_dir / mid
            mat_dir.mkdir(parents=True, exist_ok=True)
            for info in zf.infolist():
                if info.filename.lower().endswith((".jpg", ".png")):
                    (mat_dir / Path(info.filename).name).write_bytes(zf.read(info))
            got.append(mid)
        if dry_run:
            return
        write_pack_readme(pack_dir, item, got)
        append_ledger(item, pack_dir)
        print(f"OK {item['name']}: materials {got} → {pack_dir}")
    elif src == "polyhaven:models":
        got = []
        for slug in item["models"]:
            data = json.loads(fetch(f"https://api.polyhaven.com/files/{slug}"))
            node = None
            for res in (item["res"], "1k", "4k"):
                node = data.get("gltf", {}).get(res, {}).get("gltf")
                if node is not None:
                    break
            if node is None:
                raise RuntimeError(f"polyhaven:{slug}: no gltf at any res")
            main_url = node["url"]
            includes = node.get("include") or {}
            if dry_run:
                print(f"[dry] {slug}: {main_url} (+{len(includes)} textures)")
                continue
            mdir = pack_dir / slug
            mdir.mkdir(parents=True, exist_ok=True)
            (mdir / Path(main_url).name).write_bytes(fetch(main_url))
            for rel, meta in includes.items():
                dest = mdir / rel  # keep gltf-relative layout (textures/)
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(fetch(meta["url"]))
            got.append(slug)
        if dry_run:
            return
        write_pack_readme(pack_dir, item, got)
        append_ledger(item, pack_dir)
        print(f"OK {item['name']}: models {got} → {pack_dir}")
    else:
        raise RuntimeError(f"unknown source {src}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", action="append", choices=sorted(MANIFEST))
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if args.list:
        for scene, items in MANIFEST.items():
            print(f"[{scene}]")
            for it in items:
                print(f"  {it['name']:<22} {it['source']:<28} {it['role']}")
        return 0
    scenes = args.scene or sorted(MANIFEST)
    for scene in scenes:
        for item in MANIFEST[scene]:
            process_item(item, args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
