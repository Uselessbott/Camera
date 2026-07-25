#!/usr/bin/env python3

from pathlib import Path
import sys

ROOT = Path(".")

egl = ROOT / "app/src/main/java/com/fossify/camera/horizonlock/EglCore.kt"
renderer = ROOT / "app/src/main/java/com/fossify/camera/horizonlock/HorizonLockRenderer.kt"

if not egl.exists():
    sys.exit(f"Missing {egl}")

if not renderer.exists():
    sys.exit(f"Missing {renderer}")

# ------------------------------------------------------------
# Patch EglCore.makeCurrent()
# ------------------------------------------------------------

text = egl.read_text()

old = """    fun makeCurrent(eglSurface: EGLSurface) {
        if (!EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context)) {
            throw RuntimeException("EGL error: eglMakeCurrent failed")
        }
    }
"""

new = """    fun makeCurrent(eglSurface: EGLSurface) {
        if (!EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context)) {
            val error = EGL14.eglGetError()
            throw RuntimeException(
                "eglMakeCurrent failed: 0x${Integer.toHexString(error)} " +
                "(display=$display, context=$context, surface=$eglSurface)"
            )
        }
    }
"""

if old in text:
    text = text.replace(old, new)

egl.write_text(text)

# ------------------------------------------------------------
# Patch HorizonLockRenderer drawFrame()
# ------------------------------------------------------------

text = renderer.read_text()

old = """            val st = cameraSurfaceTexture ?: return
            st.updateTexImage()
"""

new = """            val st = cameraSurfaceTexture ?: return

            val previewEgl = previewEglSurface
            val encoderEgl = encoderEglSurface

            if (previewEgl == null && encoderEgl == null) {
                return
            }

            val activeSurface = previewEgl ?: encoderEgl!!

            eglCore?.makeCurrent(activeSurface)

            Log.d(TAG, "drawFrame(): updateTexImage()")

            st.updateTexImage()

            Log.d(TAG, "drawFrame(): updateTexImage() OK")
"""

if old in text:
    text = text.replace(old, new)

old = """            val previewEgl = previewEglSurface
            if (previewEgl != null) {
                eglCore?.makeCurrent(previewEgl)
"""

new = """            if (previewEgl != null) {
                if (previewEgl != activeSurface) {
                    eglCore?.makeCurrent(previewEgl)
                }
"""

if old in text:
    text = text.replace(old, new)

old = """            val encoderEgl = encoderEglSurface
            if (encoderEgl != null) {
                eglCore?.makeCurrent(encoderEgl)
"""

new = """            if (encoderEgl != null) {
                if (encoderEgl != previewEgl) {
                    eglCore?.makeCurrent(encoderEgl)
                }
"""

if old in text:
    text = text.replace(old, new)

old = """        } catch (e: Exception) {
            Log.e(TAG, "drawFrame failed", e)
"""

new = """        } catch (e: Exception) {
            Log.e(TAG, "drawFrame failed", e)

            try {
                Log.e(
                    TAG,
                    "EGL state: error=0x${Integer.toHexString(android.opengl.EGL14.eglGetError())}"
                )
            } catch (_: Exception) {
            }
"""

if old in text:
    text = text.replace(old, new)

renderer.write_text(text)

print("===================================")
print(" Horizon Lock debug patch applied ")
print("===================================")
print()
print("Next steps:")
print("1. ./gradlew assembleDebug")
print("2. Install APK")
print("3. Open Horizon Lock")
print("4. Capture full logcat")
print("5. Send the logs")
