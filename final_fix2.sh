#!/bin/bash
set -e

FILE="app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt"

# Replace the wrong import with the SDK one
sed -i 's/import androidx.preference.PreferenceManager/import android.preference.PreferenceManager/' "$FILE"

# If the import wasn't there at all (unlikely), add it after the last import line.
if ! grep -q 'import android.preference.PreferenceManager' "$FILE"; then
    LAST_IMPORT_LINE=$(grep -n '^import ' "$FILE" | tail -1 | cut -d: -f1)
    if [ -n "$LAST_IMPORT_LINE" ]; then
        sed -i "${LAST_IMPORT_LINE}a\\
import android.preference.PreferenceManager" "$FILE"
    fi
fi

# Remove the preference library from build.gradle if we added it (optional – clean up)
BUILD_GRADLE="app/build.gradle"
if [ -f "$BUILD_GRADLE" ]; then
    sed -i "/implementation 'androidx.preference:preference:1.2.0'/d" "$BUILD_GRADLE"
fi

echo "=== Fixed import. Commit and push. ==="
