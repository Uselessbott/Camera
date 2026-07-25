#!/usr/bin/env python3

from pathlib import Path
import sys

camera = Path("app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt")
renderer = Path("app/src/main/java/com/fossify/camera/horizonlock/HorizonLockRenderer.kt")

if not camera.exists():
    sys.exit(f"Missing {camera}")

if not renderer.exists():
    sys.exit(f"Missing {renderer}")

# --------------------------------------------------------
# CameraXPreview.kt
# --------------------------------------------------------

text = camera.read_text()

old = "                horizonLockRenderer?.setRoll(roll)"
new = """                Log.d(TAG, "Sensor roll = $roll")
                horizonLockRenderer?.setRoll(roll)"""

text = text.replace(old, new)

old = """    override fun initPhotoMode() {
        debounceChangeCameraMode(photoModeRunnable)
    }"""

new = """    override fun initPhotoMode() {
        if (horizonLockEnabled) {
            horizonLockRenderer?.clearPreviewSurface()
        }
        debounceChangeCameraMode(photoModeRunnable)
    }"""

text = text.replace(old, new)

old = """    override fun initVideoMode() {
        debounceChangeCameraMode(videoModeRunnable)
    }"""

new = """    override fun initVideoMode() {
        if (horizonLockEnabled) {
            horizonLockRenderer?.clearPreviewSurface()
        }
        debounceChangeCameraMode(videoModeRunnable)
    }"""

text = text.replace(old, new)

camera.write_text(text)

# --------------------------------------------------------
# HorizonLockRenderer.kt
# --------------------------------------------------------

text = renderer.read_text()

old = """    fun setRoll(rollDegrees: Float) {
        val limited = when (mode) {"""

new = """    fun setRoll(rollDegrees: Float) {
        Log.d(TAG, "Renderer roll = $rollDegrees")
        val limited = when (mode) {"""

text = text.replace(old, new)

old = """            Matrix.setRotateM(rotationMatrix, 0, Math.toDegrees(-rollRad.toDouble()).toFloat(), 0f, 0f, 1f)"""

new = """            Log.d(TAG, "Drawing with roll = ${Math.toDegrees(rollRad.toDouble())}")
            Matrix.setRotateM(rotationMatrix, 0, Math.toDegrees(-rollRad.toDouble()).toFloat(), 0f, 0f, 1f)"""

text = text.replace(old, new)

renderer.write_text(text)

print("======================================")
print(" Horizon Lock debug instrumentation ")
print("======================================")
print()
print("Next:")
print("1. Build the APK")
print("2. Enable Horizon Lock")
print("3. Tilt the phone left/right")
print("4. Capture logcat")
print()
print("We're looking for:")
print("  Sensor roll = ...")
print("  Renderer roll = ...")
print("  Drawing with roll = ...")
