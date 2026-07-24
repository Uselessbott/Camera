#!/bin/bash
set -e

echo "=== 1. Fix workflow (single fossDebug APK) ==="
cat << 'WF' > .github/workflows/build_apk.yml
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
WF

echo "=== 2. Add horizon lock toggle button to layout ==="
# Insert the button inside the top_options FrameLayout, right after the flash layout
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
        android:text="H○"\
        android:textColor="@android:color/white"\
        android:textSize="20sp"\
        android:gravity="center"\
        android:contentDescription="Toggle Horizon Lock" />' \
    app/src/main/res/layout/activity_main.xml

echo "=== 3. Add click listener in MainActivity.kt ==="
FILE="app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt"
LINE=$(grep -n "horizonLockEnabled = horizonLockEnabled" "$FILE" | head -1 | cut -d: -f1)
if [ -z "$LINE" ]; then
    echo "ERROR: could not find horizonLockEnabled line"
    exit 1
fi
# Remove any previously inserted listener lines (up to 10 lines after)
sed -i "$((LINE+1)),$((LINE+20))d" "$FILE"
# Insert new listener
sed -i "${LINE}a\
\
        binding.horizonLockToggle.setOnClickListener {\
            val preview = mPreview as? CameraXPreview ?: return@setOnClickListener\
            val newEnabled = !preview.horizonLockEnabled\
            preview.toggleHorizonLock(newEnabled)\
            binding.horizonLockToggle.text = if (newEnabled) \"H◉\" else \"H○\"\
        }" "$FILE"

echo "=== Fix complete. Now commit and push. ==="
