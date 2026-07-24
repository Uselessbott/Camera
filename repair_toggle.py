from pathlib import Path
import re

f = Path("app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt")
text = f.read_text()

pattern = re.compile(
    r'override\s+fun\s+toggleHorizonLock\s*\(enabled:\s*Boolean\)\s*\{.*?^\s*override\s+fun\s+initPhotoMode',
    re.S | re.M
)

replacement = '''override fun toggleHorizonLock(enabled: Boolean) {
        if (horizonLockEnabled == enabled) return

        horizonLockEnabled = enabled

        if (enabled) {
            initHorizonLock()
        } else {
            horizonLockRenderer?.release()
            horizonLockRenderer = null
            sensorFusionManager?.stop()
            sensorFusionManager = null
        }

        startCamera()
    }

    override fun initPhotoMode'''

new, n = pattern.subn(replacement, text, count=1)

if n != 1:
    print("Failed to repair toggleHorizonLock()")
    exit(1)

f.write_text(new)
print("toggleHorizonLock() repaired.")
