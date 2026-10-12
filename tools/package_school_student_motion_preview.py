"""Package engine-rendered PNG captures as a GIF; source character art is untouched."""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "data/ui/school_student_motion_sample.json").read_text(encoding="utf-8"))
SOURCE = ROOT / "tools/out/school_student_motion_sample"
DESTINATION = ROOT / "docs/art/concepts/school_student_motion_sample"
DESTINATION.mkdir(parents=True, exist_ok=True)
paths = sorted(SOURCE.glob("[0-9][0-9][0-9].png"))
expected = round(sum(CONFIG[key] for key in ("walk_duration", "sit_duration", "hold_duration")) * CONFIG["capture_fps"])
assert len(paths) == expected + 1, (len(paths), expected)
frames = [Image.open(path).convert("RGB") for path in paths]
frames[0].save(
    DESTINATION / "motion-20261012.gif",
    save_all=True,
    append_images=frames[1:],
    duration=round(1000 / CONFIG["capture_fps"]),
    loop=0,
    disposal=2,
)
frames[-1].save(DESTINATION / "seated-20261012.png")
with Image.open(DESTINATION / "motion-20261012.gif") as result:
    assert result.is_animated and result.n_frames > 30
    print("GIF:", result.size, result.n_frames, "frames")
