"""Encode Godot's pure 2D frame captures; generated artwork is untouched."""
import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
config = json.loads((ROOT / "data/ui/classroom_2d_motion_sample.json").read_text(encoding="utf-8"))
source = ROOT / config["output"].removeprefix("res://")
destination = ROOT / "docs/art/concepts/classroom_2d_motion"
destination.mkdir(parents=True, exist_ok=True)
paths = sorted(source.glob("[0-9][0-9][0-9].png"))
duration = sum(config[key] for key in ("walk_duration", "sit_duration", "hold_duration"))
assert len(paths) == math.ceil(duration * config["capture_fps"])
frames = [Image.open(path).convert("RGB") for path in paths]
stem = config.get("preview_stem", "motion-20261012")
durations = [round((index + 1) * 100 / config["capture_fps"]) * 10 - round(index * 100 / config["capture_fps"]) * 10 for index in range(len(frames))]
frames[0].save(destination / (stem + ".gif"), save_all=True,
               append_images=frames[1:], duration=durations,
               loop=0, disposal=2)
frames[-1].save(destination / (stem + "-seated.png"))
with Image.open(destination / (stem + ".gif")) as result:
    assert result.is_animated and result.n_frames > 30
    print("GIF verified:", result.size, result.n_frames, "frames")
