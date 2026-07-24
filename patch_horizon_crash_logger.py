from pathlib import Path
import re

f = Path("app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt")
text = f.read_text()

# Add imports if missing
if "import android.util.Log" not in text:
    text = text.replace(
        "import android.provider.MediaStore",
        "import android.provider.MediaStore\nimport android.util.Log"
    )

if "import java.io.File" not in text:
    idx = text.rfind("import ")
    end = text.find("\n", idx)
    text = text[:end+1] + "import java.io.File\n" + text[end+1:]

pattern = re.compile(
    r'toggleHorizonLock\.setOnClickListener\s*\{\s*'
    r'horizonLockEnabled = !horizonLockEnabled\s*'
    r'toggleHorizonLock\.isSelected = horizonLockEnabled\s*'
    r'mPreview\?\.toggleHorizonLock\(horizonLockEnabled\)\s*'
    r'\}',
    re.S
)

replacement = r'''toggleHorizonLock.setOnClickListener {
                try {
                    horizonLockEnabled = !horizonLockEnabled
                    toggleHorizonLock.isSelected = horizonLockEnabled
                    mPreview?.toggleHorizonLock(horizonLockEnabled)
                } catch (t: Throwable) {
                    File(filesDir, "horizon_crash.txt")
                        .writeText(Log.getStackTraceString(t))
                    throw t
                }
            }'''

new_text, n = pattern.subn(replacement, text, count=1)

if n == 0:
    print("Couldn't locate Horizon click listener automatically.")
else:
    f.write_text(new_text)
    print("✓ Crash logger installed")
