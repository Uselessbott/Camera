from pathlib import Path

f = Path("app/src/main/java/com/fossify/camera/horizonlock/HorizonLockRenderer.kt")
text = f.read_text()

old = """        eglCore = EglCore()
        eglCore.initialize()
"""

new = """        eglCore = EglCore()
        eglCore.initialize()

        val bootstrapSurface = eglCore.createOffscreenSurface(1, 1)
        eglCore.makeCurrent(bootstrapSurface)
"""

if old not in text:
    print("Couldn't find init()")
    raise SystemExit(1)

text = text.replace(old, new, 1)

old2 = """        uTexture = GLES20.glGetUniformLocation(program, "uTexture")
    }
"""

new2 = """        uTexture = GLES20.glGetUniformLocation(program, "uTexture")

        eglCore.makeNothingCurrent()
        eglCore.releaseSurface(bootstrapSurface)
    }
"""

if old2 not in text:
    print("Couldn't find end of init()")
    raise SystemExit(1)

text = text.replace(old2, new2, 1)

f.write_text(text)
print("✓ EGL bootstrap patch applied")
