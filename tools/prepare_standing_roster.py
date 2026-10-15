"""Validate/copy generated PNGs and prepare roster mappings; never modify pixels."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/textures/characters/standing_front_v2"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def prepare(sources_path):
    sources = read(sources_path)
    roster = read(ROOT / "assets/textures/characters/study_front_v1/manifest.json")
    settings = read(ROOT / "data/ui/student_poses.json")
    profiles = read(ROOT / "data/ui/npc_profile.json")
    manifest = []
    validation = []
    DEST.mkdir(parents=True, exist_ok=True)
    for entry in roster:
        character_id = entry["id"]
        source = sources[character_id]
        if " as " in source:
            source = source.rsplit(" as ", 1)[1]
        source_path = Path(source)
        with Image.open(source_path) as image:
            assert image.mode == "RGBA", (character_id, "RGBA required")
            assert image.size == (1024, 1536), (character_id, image.size)
            alpha = image.getchannel("A")
            histogram = alpha.histogram()
            transparent = histogram[0] / (image.width * image.height)
            assert transparent > .25, (character_id, "opaque poster rejected", transparent)
            # One generated source has 1/255 alpha quantization noise at two corners.
            assert all(alpha.getpixel(point) <= 1 for point in [
                (0, 0), (image.width - 1, 0), (0, image.height - 1),
                (image.width - 1, image.height - 1)
            ]), (character_id, "corners must be transparent")
            bounds = alpha.point(lambda value: 255 if value > 200 else 0).getbbox()
            assert bounds and bounds[3] > image.height * .9
            upper = alpha.crop((0, 0, image.width, 700)).point(
                lambda value: 255 if value > 200 else 0
            ).getbbox()
            assert upper
            left = max(0, upper[0] - 24)
            right = min(image.width, upper[2] + 24)
        filename = f"char_{character_id}_stand_natural_v2.png"
        target = DEST / filename
        if source_path.resolve() != target.resolve():
            shutil.copy2(source_path, target)
        reference = "res://assets/textures/characters/standing_front_v2/" + filename
        manifest.append({
            "id": character_id, "name": entry["name"], "sprite": entry["sprite"],
            "gender": entry["gender"], "identity_reference": entry["reference"],
            "reference": reference, "file": filename, "source": str(source_path),
            "pose": "relaxed_front_standing"
        })
        settings["bindings"][entry["sprite"]]["standing"] = reference
        settings["bindings"][entry["sprite"]]["standing_floor_pixel"] = bounds[3]
        profiles["portraits"][character_id] = {
            "path": reference, "region": [left, 0, right - left, 700]
        }
        validation.append({
            "id": character_id, "size": [1024, 1536], "mode": "RGBA",
            "transparent_ratio": round(transparent, 4), "opaque_bounds": bounds,
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest()
        })
    assert len({row["sha256"] for row in validation}) == 16
    write(DEST / "manifest.json", manifest)
    write(DEST / "validation.json", validation)
    write(ROOT / "data/ui/student_poses.json", settings)
    write(ROOT / "data/ui/npc_profile.json", profiles)
    print("16 standing PNGs validated and mapped; source pixels unchanged")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("sources", type=Path)
    prepare(parser.parse_args().sources)
