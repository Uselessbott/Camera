from pathlib import Path

ROOT = Path(".")

main = ROOT / "app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt"
iface = ROOT / "app/src/main/kotlin/org/fossify/camera/interfaces/MyPreview.kt"

# ---------------------------------------------------------------------
# Patch MyPreview
# ---------------------------------------------------------------------

text = iface.read_text()

if "fun toggleHorizonLock(enabled: Boolean)" not in text:
    text = text.replace(
        "    fun showChangeResolution()\n}",
        "    fun showChangeResolution()\n\n    fun toggleHorizonLock(enabled: Boolean)\n}"
    )
    iface.write_text(text)
    print("✓ Added toggleHorizonLock() to MyPreview")
else:
    print("✓ MyPreview already patched")

# ---------------------------------------------------------------------
# Patch MainActivity
# ---------------------------------------------------------------------

text = main.read_text()

text = text.replace(
    "import org.fossify.camera.implementations.CameraXPreview\n",
    ""
)

text = text.replace(
    "(mPreview as? CameraXPreview)?.toggleHorizonLock(horizonLockEnabled)",
    "mPreview?.toggleHorizonLock(horizonLockEnabled)"
)

main.write_text(text)

print("✓ MainActivity patched")
print("\nDone.")
