from pathlib import Path

f = Path("app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt")
text = f.read_text()

text = text.replace(
    "fun toggleHorizonLock(enabled: Boolean) {",
    "override fun toggleHorizonLock(enabled: Boolean) {",
    1
)

f.write_text(text)
print("✓ Added override modifier")
