#!/bin/bash
set -e

FILE="app/src/main/kotlin/org/fossify/camera/activities/MainActivity.kt"
if [ ! -f "$FILE" ]; then
    echo "ERROR: $FILE not found"
    exit 1
fi

# Find start line (the line with createCameraXPreview)
START_LINE=$(grep -n "mPreview = CameraXInitializer(this).createCameraXPreview(" "$FILE" | head -1 | cut -d: -f1)
if [ -z "$START_LINE" ]; then
    echo "ERROR: could not find createCameraXPreview call"
    exit 1
fi

# Find end line: after START_LINE, find the next line that is exactly ")" (whitespace allowed)
END_LINE=$(awk -v start=$START_LINE 'NR>start && /^\s*\)\s*$/ {print NR; exit}' "$FILE")
if [ -z "$END_LINE" ]; then
    echo "ERROR: could not find closing ) of createCameraXPreview call"
    exit 1
fi

echo "Patching from line $START_LINE to $END_LINE..."

# Create the replacement block with proper indentation
REPLACEMENT=$(cat << 'BLOCK'
        val prefs = PreferenceManager.getDefaultSharedPreferences(this)
        val horizonLockMode = prefs.getString("horizon_lock_mode", "off") ?: "off"
        val horizonLockEnabled = horizonLockMode != "off"
        mPreview = CameraXInitializer(this).createCameraXPreview(
            binding.previewView,
            listener = this,
            mediaSoundHelper = mediaSoundHelper,
            outputUri = outputUri,
            isThirdPartyIntent = isThirdPartyIntent,
            initInPhotoMode = isInPhotoMode,
            horizonLockEnabled = horizonLockEnabled
        )
BLOCK
)

# Use sed to delete the lines and insert the replacement
TEMP_FILE=$(mktemp)
sed "${START_LINE},${END_LINE}c\\
${REPLACEMENT}" "$FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$FILE"

# Check if import for PreferenceManager exists, add if missing
if ! grep -q "import androidx.preference.PreferenceManager" "$FILE"; then
    # Add import after the last import line or after package line
    # Find line with "import" and insert after the last one
    LAST_IMPORT_LINE=$(grep -n "^import " "$FILE" | tail -1 | cut -d: -f1)
    if [ -n "$LAST_IMPORT_LINE" ]; then
        sed -i "${LAST_IMPORT_LINE}a\\
import androidx.preference.PreferenceManager" "$FILE"
    else
        # No imports? Insert after package line
        sed -i "1a\\
import androidx.preference.PreferenceManager" "$FILE"
    fi
fi

# Ensure preferences.xml exists (it does, but safe)
if [ ! -f app/src/main/res/xml/preferences.xml ]; then
    mkdir -p app/src/main/res/xml
    cat << 'XML' > app/src/main/res/xml/preferences.xml
<?xml version="1.0" encoding="utf-8"?>
<PreferenceScreen xmlns:android="http://schemas.android.com/apk/res/android">

    <PreferenceCategory android:title="Horizon Lock">
        <ListPreference
            android:key="horizon_lock_mode"
            android:title="Mode"
            android:summary="OFF / AUTO / ON"
            android:entries="@array/horizon_lock_entries"
            android:entryValues="@array/horizon_lock_values"
            android:defaultValue="off" />
    </PreferenceCategory>

</PreferenceScreen>
XML
fi

echo "MainActivity.kt patched successfully."
