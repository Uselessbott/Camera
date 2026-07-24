from pathlib import Path

ROOT = Path(".")

layout = ROOT / "app/src/main/res/layout/layout_top.xml"
main = ROOT / "app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt"
drawable = ROOT / "app/src/main/res/drawable/ic_horizon_lock_vector.xml"

# ---------------------------------------------------------------------
# Drawable
# ---------------------------------------------------------------------

if not drawable.exists():
    drawable.write_text("""<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">

    <path
        android:fillColor="?attr/colorControlNormal"
        android:pathData="M4,12h16v2H4z"/>

    <path
        android:fillColor="?attr/colorControlNormal"
        android:pathData="M12,4a6,6 0 1,0 0.01,0zM12,6a4,4 0 1,1 0,8a4,4 0 0,1 0,-8z"/>

</vector>
""")
    print("✓ Drawable created")

# ---------------------------------------------------------------------
# layout_top.xml
# ---------------------------------------------------------------------

xml = layout.read_text()

if "toggle_horizon_lock" not in xml:
    button = """
    <com.google.android.material.button.MaterialButton
        android:id="@+id/toggle_horizon_lock"
        style="@style/Widget.App.Button.OutlineButton.IconOnly"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:contentDescription="Horizon Lock"
        android:padding="@dimen/normal_margin"
        app:icon="@drawable/ic_horizon_lock_vector" />

"""
    xml = xml.replace(
        '<com.google.android.material.button.MaterialButton\n        android:id="@+id/settings"',
        button + '    <com.google.android.material.button.MaterialButton\n        android:id="@+id/settings"'
    )

    layout.write_text(xml)
    print("✓ Toolbar button added")

# ---------------------------------------------------------------------
# MainActivity.kt
# ---------------------------------------------------------------------

code = main.read_text()

# member variable
if "private var horizonLockEnabled" not in code:
    code = code.replace(
        "private var mPreview: MyPreview? = null",
        "private var mPreview: MyPreview? = null\n    private var horizonLockEnabled = false"
    )

# click listener
if "toggleHorizonLock.setOnClickListener" not in code:

    old = """changeResolution.setOnClickListener { mPreview?.showChangeResolution() }"""

    new = """changeResolution.setOnClickListener { mPreview?.showChangeResolution() }

            toggleHorizonLock.setShadowIcon(R.drawable.ic_horizon_lock_vector)
            toggleHorizonLock.setOnClickListener {
                horizonLockEnabled = !horizonLockEnabled
                toggleHorizonLock.isSelected = horizonLockEnabled
                (mPreview as? CameraXPreview)?.toggleHorizonLock(horizonLockEnabled)
            }"""

    code = code.replace(old, new)

# rotate animation
if "layoutTop.toggleHorizonLock" not in code:
    code = code.replace(
        "layoutTop.changeResolution,",
        "layoutTop.changeResolution,\n            layoutTop.toggleHorizonLock,"
    )

# disable while busy
if "toggleHorizonLock.isClickable" not in code:
    code = code.replace(
        "layoutTop.toggleFlash.isClickable = enabled",
        """layoutTop.toggleFlash.isClickable = enabled
            layoutTop.toggleHorizonLock.isClickable = enabled"""
    )

main.write_text(code)

print("✓ MainActivity patched")

print("\nDone.")
print("Rebuild the project now.")
