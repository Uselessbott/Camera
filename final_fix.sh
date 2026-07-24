#!/bin/bash
set -e

echo "=== Final fix for Horizon Lock imports & dependencies ==="

# 1. Fix CameraXPreview.kt – change import package
sed -i 's/import org\.fossify\.camera\.horizonlock\.\*/import com.fossify.camera.horizonlock.*/' \
  app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt

# 2. Ensure MainActivity.kt has the correct import for PreferenceManager.
#    Insert the import after the last 'import' line if it is missing.
if ! grep -q 'import androidx.preference.PreferenceManager' \
     app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt; then
    LAST_IMPORT_LINE=$(grep -n '^import ' app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt | tail -1 | cut -d: -f1)
    if [ -n "$LAST_IMPORT_LINE" ]; then
        sed -i "${LAST_IMPORT_LINE}a\\
import androidx.preference.PreferenceManager" \
          app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt
    else
        sed -i "1a\\
import androidx.preference.PreferenceManager" \
          app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt
    fi
fi

# 3. Add the preference library to build.gradle (app module) if it is missing.
BUILD_GRADLE="app/build.gradle"
if [ -f "$BUILD_GRADLE" ]; then
    if ! grep -q "androidx.preference:preference" "$BUILD_GRADLE"; then
        # Insert inside the dependencies block
        sed -i "/dependencies {/a\\
    implementation 'androidx.preference:preference:1.2.0'" "$BUILD_GRADLE"
    fi
else
    echo "Warning: $BUILD_GRADLE not found – please add preference dependency manually."
fi

echo "=== Fix applied. Now commit and push. ==="
