from pathlib import Path
import re
import sys

FILE = Path("app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt")

if not FILE.exists():
    print("❌ CameraXPreview.kt not found")
    sys.exit(1)

text = FILE.read_text(encoding="utf-8")

# ------------------------------------------------------------------
# Add RollMode import if missing
# ------------------------------------------------------------------

if "import com.fossify.camera.horizonlock.RollMode" not in text:
    marker = "import com.fossify.camera.horizonlock.HorizonLockRenderer"
    if marker in text:
        text = text.replace(
            marker,
            marker + "\nimport com.fossify.camera.horizonlock.RollMode"
        )
        print("✓ Added RollMode import")
    else:
        print("⚠ Couldn't locate HorizonLockRenderer import")

# ------------------------------------------------------------------
# Enable FULL mode immediately after renderer creation
# ------------------------------------------------------------------

pattern = re.compile(
    r'(horizonLockRenderer\s*=\s*HorizonLockRenderer\s*\{.*?\n\s*\})',
    re.DOTALL
)

match = pattern.search(text)

if not match:
    print("❌ Couldn't locate HorizonLockRenderer creation")
    sys.exit(1)

block = match.group(1)

if "mode = RollMode.FULL" not in block:
    replacement = (
        block +
        "\n        horizonLockRenderer?.mode = RollMode.FULL"
    )
    text = text.replace(block, replacement, 1)
    print("✓ Enabled RollMode.FULL")
else:
    print("✓ RollMode already configured")

FILE.write_text(text, encoding="utf-8")

print("\nDone.")
