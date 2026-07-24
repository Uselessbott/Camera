from pathlib import Path
import re

f = Path("app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt")
text = f.read_text()

pattern = re.compile(
    r'override\s+fun\s+toggleHorizonLock\s*\(enabled:\s*Boolean\)\s*\{.*?^\s*override\s+fun\s+initPhotoMode',
    re.S | re.M
)

replacement = r'''override fun toggleHorizonLock(enabled: Boolean) {
        val trace = java.io.File(activity.filesDir, "horizon_trace.txt")

        fun log(msg: String) {
            trace.appendText(msg + "\n")
        }

        try {
            log("==== toggleHorizonLock ====")
            log("enabled=$enabled")
            log("current=$horizonLockEnabled")

            if (horizonLockEnabled == enabled) {
                log("Already in requested state")
                return
            }

            horizonLockEnabled = enabled
            log("State updated")

            if (enabled) {
                log("Calling initHorizonLock()")
                initHorizonLock()
                log("initHorizonLock() OK")
            } else {
                log("Releasing renderer")
                horizonLockRenderer?.release()
                horizonLockRenderer = null
                sensorFusionManager?.stop()
                sensorFusionManager = null
                log("Release OK")
            }

            log("Calling startCamera()")
            startCamera()
            log("startCamera() returned")

        } catch (t: Throwable) {
            trace.appendText(
                "\n===== CRASH =====\n" +
                android.util.Log.getStackTraceString(t) +
                "\n"
            )
            throw t
        }
    }

    override fun initPhotoMode'''

new_text, n = pattern.subn(replacement, text, count=1)

if n != 1:
    print("❌ Failed to patch toggleHorizonLock()")
    exit(1)

f.write_text(new_text)
print("✅ toggleHorizonLock() patched with tracing.")
