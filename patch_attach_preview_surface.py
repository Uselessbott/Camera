from pathlib import Path

f = Path("app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt")
text = f.read_text()

old = """            val surfaceTexture = horizonLockRenderer!!.getCameraSurfaceTexture()
            surfaceTexture.setDefaultBufferSize(targetResolution.width, targetResolution.height)
            // Start rendering loop driven by Choreographer
            startRenderingLoop()
"""

new = """            val surfaceTexture = horizonLockRenderer!!.getCameraSurfaceTexture()
            surfaceTexture.setDefaultBufferSize(targetResolution.width, targetResolution.height)

            textureView?.surfaceTexture?.let { previewTexture ->
                previewTexture.setDefaultBufferSize(
                    targetResolution.width,
                    targetResolution.height
                )

                horizonLockRenderer!!.setPreviewSurface(
                    android.view.Surface(previewTexture),
                    targetResolution.width,
                    targetResolution.height
                )
            }

            // Start rendering loop driven by Choreographer
            startRenderingLoop()
"""

if old not in text:
    print("Pattern not found.")
    exit(1)

f.write_text(text.replace(old, new, 1))
print("✓ Attached TextureView surface to HorizonLockRenderer")
