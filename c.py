from pathlib import Path
import subprocess

FILE = Path("app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt")
OLD = "e82a8ed9"

current = FILE.read_text()

original = subprocess.check_output([
    "git",
    "show",
    f"{OLD}:app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt",
], text=True)

start_old = original.index("override fun showChangeResolution()")
end_old = original.index("override fun initPhotoMode()")

replacement = original[start_old:end_old]

start_new = current.index("override fun showChangeResolution()")
end_new = current.index("fun toggleHorizonLock(")

patched = current[:start_new] + replacement + current[end_new:]

FILE.write_text(patched)

print("✅ Restored original camera methods.")
