#!/bin/bash
set -e

echo "=== Final fix: visible toggle, correct front camera, single APK ==="

# 1. Replace the ImageButton with a visible TextView button in activity_main.xml
#    Place it inside top_options FrameLayout, after the flash layout
sed -i '/<include android:id="@+id\/layout_flash"/a \
\
    <TextView\
        android:id="@+id/horizon_lock_toggle"\
        android:layout_width="wrap_content"\
        android:layout_height="wrap_content"\
        android:layout_gravity="end|top"\
        android:layout_margin="8dp"\
        android:padding="8dp"\
        android:background="?attr/selectableItemBackgroundBorderless"\
        android:text="H"\
        android:textColor="@android:color/white"\
        android:textSize="18sp"\
        android:gravity="center"\
        android:contentDescription="Toggle Horizon Lock" />' \
    app/src/main/res/layout/activity_main.xml

# 2. Fix toggleHorizonLock method in CameraXPreview.kt
#    Remove old method if present, then insert correct version before initVideoMode
sed -i '/fun toggleHorizonLock(enabled: Boolean)/,/^    }/d' app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt
sed -i '/^    override fun initVideoMode()/i \
\
    fun toggleHorizonLock(enabled: Boolean) {\
        if (horizonLockEnabled == enabled) return\
        horizonLockEnabled = enabled\
        if (enabled) {\
            initHorizonLock()\
        } else {\
            horizonLockRenderer?.release()\
            horizonLockRenderer = null\
            sensorFusionManager?.stop()\
            sensorFusionManager = null\
        }\
        startCamera()\
    }' \
    app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt

# 3. Ensure the button listener in MainActivity.kt is correct
#    Replace the previously inserted listener with a clean one
#    Find the line after 'horizonLockEnabled = horizonLockEnabled )' and insert a new block
LINE=$(grep -n "horizonLockEnabled = horizonLockEnabled" app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt | head -1 | cut -d: -f1)
if [ -z "$LINE" ]; then
    echo "Error: could not find horizonLockEnabled line"
    exit 1
fi
# Remove any previously inserted listener lines (3 lines after that line)
sed -i "$((LINE+1)),$((LINE+10))d" app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt

# Insert the new listener code
sed -i "${LINE}a\
\\
        binding.horizonLockToggle.setOnClickListener {\
            val preview = mPreview as? CameraXPreview ?: return@setOnClickListener\
            val newEnabled = !preview.horizonLockEnabled\
            preview.toggleHorizonLock(newEnabled)\
            binding.horizonLockToggle.text = if (newEnabled) \"H◉\" else \"H○\"\
            binding.horizonLockToggle.isSelected = newEnabled\
        }" app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt

# 4. Remove the example fragment (no longer needed)
rm -f app/src/main/java/com/fossify/camera/fragments/VideoFragment_HorizonLock_example.kt

# 5. Update workflow to only build fossDebug
cat << 'EOF' > .github/workflows/build_apk.yml
name: Build APK

on:
  push:
    branches: [ "main", "master" ]
  pull_request:
    branches: [ "main", "master" ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - uses: gradle/actions/setup-gradle@v3
      - name: Grant execute permission for gradlew
        run: chmod +x gradlew
      - name: Build fossDebug APK
        run: ./gradlew assembleFossDebug
      - uses: actions/upload-artifact@v4
        with:
          name: foss-debug-apk
          path: app/build/outputs/apk/foss/debug/*.apk
EOF

echo "=== Fix applied. Commit and push. ==="
