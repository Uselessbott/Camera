#!/bin/bash
set -e

echo "=== Adding Horizon Lock toggle button & fixing APK output ==="

# 1. Add a toggle button in activity_main.xml (inside top_options FrameLayout)
sed -i '/<include android:id="@+id\/layout_timer"/a \
\
    <ImageButton\
        android:id="@+id/horizon_lock_toggle"\
        android:layout_width="wrap_content"\
        android:layout_height="wrap_content"\
        android:layout_gravity="end|top"\
        android:layout_margin="8dp"\
        android:background="?attr/selectableItemBackgroundBorderless"\
        android:src="@android:drawable/ic_menu_compass"\
        android:contentDescription="Toggle Horizon Lock" />' app/src/main/res/layout/activity_main.xml

# 2. Add toggleHorizonLock method to CameraXPreview.kt
# Insert the method before the class closing brace.
sed -i '/^    override fun initVideoMode()/i \
\
    fun toggleHorizonLock(enabled: Boolean) {\
        if (horizonLockEnabled == enabled) return\
        horizonLockEnabled = enabled\
        // Stop existing rendering if disabling\
        if (!enabled) {\
            horizonLockRenderer?.release()\
            sensorFusionManager?.stop()\
        }\
        // Re-bind camera use cases with the new flag\
        startCamera()\
    }' app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt

# 3. Wire the button in MainActivity.kt (find the button and call toggleHorizonLock)
# Add the code right after the existing mPreview = ... line.
# We'll insert after the line that ends with 'horizonLockEnabled = horizonLockEnabled )'.
# First, find the line number of that closing parenthesis.
LINE=$(grep -n "horizonLockEnabled = horizonLockEnabled" app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt | head -1 | cut -d: -f1)
if [ -z "$LINE" ]; then
    echo "Error: Could not find horizonLockEnabled line in MainActivity.kt"
    exit 1
fi
# Insert after that line (the next line)
sed -i "${LINE}a\
\\
        binding.horizonLockToggle.setOnClickListener {\
            val currentEnabled = (mPreview as? CameraXPreview)?.let { it.horizonLockEnabled } ?: false\
            val newEnabled = !currentEnabled\
            (mPreview as? CameraXPreview)?.toggleHorizonLock(newEnabled)\
            binding.horizonLockToggle.setImageResource(\
                if (newEnabled) android.R.drawable.ic_menu_compass\
                else android.R.drawable.ic_menu_compass\
            )\
            // Optionally update the toggle visual\
            binding.horizonLockToggle.isSelected = newEnabled\
        }" app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt

# 4. Update the GitHub Actions workflow to build only fossDebug and produce one APK
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
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v3

      - name: Grant execute permission for gradlew
        run: chmod +x gradlew

      - name: Build fossDebug APK
        run: ./gradlew assembleFossDebug

      - name: Upload fossDebug APK
        uses: actions/upload-artifact@v4
        with:
          name: foss-debug-apk
          path: app/build/outputs/apk/foss/debug/*.apk
EOF

echo "=== UI toggle added, workflow fixed. Commit and push. ==="
