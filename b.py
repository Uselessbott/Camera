#!/usr/bin/env python3

import subprocess
import re
from pathlib import Path

OLD_COMMIT = "e82a8ed9"

TARGET = Path(
    "app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt"
)

METHODS = [
    "showChangeResolution",
    "toggleFrontBackCamera",
    "handleFlashlightClick",
    "setFlashlightState",
    "tryTakePicture",
]

old_source = subprocess.check_output(
    [
        "git",
        "show",
        f"{OLD_COMMIT}:app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt",
    ],
    text=True,
)

new_source = TARGET.read_text()

for method in METHODS:
    pattern = (
        r'override fun '
        + re.escape(method)
        + r'\([^)]*\)\s*\{'
        + r'(?:[^{}]|\{[^{}]*\})*?'
        + r'\n\s*\}'
    )

    old_match = re.search(pattern, old_source, flags=re.S)
    new_match = re.search(pattern, new_source, flags=re.S)

    if not old_match:
        raise RuntimeError(f"Couldn't find original {method}")

    if not new_match:
        raise RuntimeError(f"Couldn't find current {method}")

    new_source = (
        new_source[: new_match.start()]
        + old_match.group(0)
        + new_source[new_match.end() :]
    )

TARGET.write_text(new_source)

print("✅ Restored:")
for m in METHODS:
    print(" -", m)
