#!/usr/bin/env python3

from pathlib import Path
import re
import sys

FILE = Path("app/src/main/java/com/fossify/camera/horizonlock/HorizonLockRenderer.kt")

if not FILE.exists():
    print("❌ HorizonLockRenderer.kt not found")
    sys.exit(1)

text = FILE.read_text()

replacement = '''
    private fun computeTransformedTexCoords(matrix: FloatArray) {
        val src = floatArrayOf(
            0f, 0f,
            0f, 1f,
            1f, 0f,
            1f, 1f
        )

        var out = 0

        for (i in 0 until 4) {
            val x = src[i * 2]
            val y = src[i * 2 + 1]

            val tx =
                matrix[0] * x +
                matrix[4] * y +
                matrix[8] * 0f +
                matrix[12]

            val ty =
                matrix[1] * x +
                matrix[5] * y +
                matrix[9] * 0f +
                matrix[13]

            val tw =
                matrix[3] * x +
                matrix[7] * y +
                matrix[11] * 0f +
                matrix[15]

            transformedTexCoords[out] =
                if (tw != 0f) tx / tw else tx

            transformedTexCoords[out + 1] =
                if (tw != 0f) ty / tw else ty

            out += 2
        }
    }
'''

pattern = re.compile(
    r'private fun computeTransformedTexCoords\(matrix: FloatArray\)\s*\{.*?\n\s*\}',
    re.DOTALL
)

new_text, count = pattern.subn(replacement.strip(), text, count=1)

if count != 1:
    print("❌ Couldn't locate computeTransformedTexCoords()")
    sys.exit(1)

FILE.write_text(new_text)

print("✅ Patched computeTransformedTexCoords()")
