package com.fossify.camera.horizonlock

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.max

enum class RollMode { OFF, AUTO, FULL }

class HorizonLockRenderer(
    private val onError: (String) -> Unit = { Log.e(TAG, it) }
) {
    companion object {
        private const val TAG = "HorizonLockRenderer"
    }

    // Dedicated GL thread
    private val glThread = HandlerThread("HorizonLockGL").apply { start() }
    private val glHandler = Handler(glThread.looper)

    private var eglCore: EglCore? = null
    private var cameraSurfaceTexture: SurfaceTexture? = null
    private var cameraTextureId = 0
    private var program = 0
    private var aPosition = 0
    private var aTexCoord = 0
    private var uMVPMatrix = 0
    private var uTexture = 0

    // Matrices
    private val projectionMatrix = FloatArray(16)
    private val viewMatrix = FloatArray(16)
    private val rotationMatrix = FloatArray(16)
    private val scaleMatrix = FloatArray(16)
    private val mvpMatrix = FloatArray(16)
    private val textureTransformMatrix = FloatArray(16)

    @Volatile
    private var rollRad = 0f
    var mode: RollMode = RollMode.OFF
    var autoMaxAngle: Float = 30f

    // EGL surfaces
    private var previewEglSurface: EGLSurface? = null   // output to TextureView
    private var encoderEglSurface: EGLSurface? = null   // optional encoder output

    private var previewWidth = 1
    private var previewHeight = 1

    @Volatile
    private var frameAvailable = false

    @Volatile
    private var drawPending = false

    private var isReleased = false

    // Quad vertices: position (x,y,z) + tex (u,v) interleaved
    private val quadVertices = floatArrayOf(
        -1f,  1f, 0f, 0f, 0f,   // top-left
        -1f, -1f, 0f, 0f, 1f,   // bottom-left
         1f,  1f, 0f, 1f, 0f,   // top-right
         1f, -1f, 0f, 1f, 1f    // bottom-right
    )
    private val vertexBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(quadVertices.size * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .put(quadVertices).also { it.position(0) }

    private val transformedTexCoords = floatArrayOf(
        0f, 0f, 0f, 1f, 1f, 0f, 1f, 1f
    )
    private val texCoordBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(transformedTexCoords.size * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()

    private val vertexShaderCode = """
        uniform mat4 uMVPMatrix;
        attribute vec4 aPosition;
        attribute vec2 aTexCoord;
        varying vec2 vTexCoord;
        void main() {
            gl_Position = uMVPMatrix * aPosition;
            vTexCoord = aTexCoord;
        }
    """.trimIndent()

    private val fragmentShaderCode = """
        #extension GL_OES_EGL_image_external : require
        precision mediump float;
        varying vec2 vTexCoord;
        uniform samplerExternalOES uTexture;
        void main() {
            gl_FragColor = texture2D(uTexture, vTexCoord);
        }
    """.trimIndent()

    /**
     * Initializes OpenGL resources on the GL thread.
     * Calls [onReady] on the main thread with the camera [SurfaceTexture] when done.
     */
    fun init(onReady: (SurfaceTexture) -> Unit) {
        glHandler.post {
            try {
                eglCore = EglCore()
                eglCore!!.initialize(recordable = false)  // no encoding context needed here

                // Create a temporary surface to make context current
                val tmpSurface = eglCore!!.createOffscreenSurface(1, 1)
                eglCore!!.makeCurrent(tmpSurface)
                Log.d(TAG, "EGL context current for init")

                // Generate OES texture
                val textures = IntArray(1)
                GLES20.glGenTextures(1, textures, 0)
                cameraTextureId = textures[0]
                GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

                cameraSurfaceTexture = SurfaceTexture(cameraTextureId)
                cameraSurfaceTexture!!.setOnFrameAvailableListener(
                    { onFrameAvailable() },
                    glHandler
                )
                Log.d(TAG, "SurfaceTexture created, onFrameAvailableListener set")

                // Build shader program (with validation)
                program = buildProgram(vertexShaderCode, fragmentShaderCode)
                aPosition = GLES20.glGetAttribLocation(program, "aPosition")
                aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
                uMVPMatrix = GLES20.glGetUniformLocation(program, "uMVPMatrix")
                uTexture = GLES20.glGetUniformLocation(program, "uTexture")
                if (aPosition == -1) Log.w(TAG, "aPosition not found")
                if (aTexCoord == -1) Log.w(TAG, "aTexCoord not found")
                if (uMVPMatrix == -1) Log.w(TAG, "uMVPMatrix not found")
                if (uTexture == -1) Log.w(TAG, "uTexture not found")

                checkGlError("init")
                eglCore!!.makeNothingCurrent()
                eglCore!!.releaseSurface(tmpSurface)
                Log.d(TAG, "Renderer initialized successfully")

                Handler(Looper.getMainLooper()).post { onReady(cameraSurfaceTexture!!) }
            } catch (e: Exception) {
                Log.e(TAG, "Renderer init failed", e)
                onError("HorizonLockRenderer init failed: ${e.message}")
                Handler(Looper.getMainLooper()).post { release() }
            }
        }
    }

    fun getCameraSurfaceTexture(): SurfaceTexture = cameraSurfaceTexture!!

    /**
     * Set the preview output surface (TextureView).
     */
    fun setPreviewSurface(surface: Surface, width: Int, height: Int) {
        if (isReleased) return
        glHandler.post {
            try {
                previewEglSurface?.let { eglCore?.releaseSurface(it) }
                previewEglSurface = eglCore?.createWindowSurface(surface)
                previewWidth = width
                previewHeight = height
                Matrix.orthoM(projectionMatrix, 0, -1f, 1f, -1f, 1f, -1f, 1f)
                Log.d(TAG, "Preview surface set: ${width}x${height}")
                maybePostDraw()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to set preview surface", e)
            }
        }
    }

    fun clearPreviewSurface() {
        if (isReleased) return
        glHandler.post {
            previewEglSurface?.let { eglCore?.releaseSurface(it) }
            previewEglSurface = null
            Log.d(TAG, "Preview surface cleared")
        }
    }

    /**
     * Optional encoder output surface.
     */
    fun setEncoderSurface(surface: Surface?) {
        if (isReleased) return
        glHandler.post {
            encoderEglSurface?.let { eglCore?.releaseSurface(it) }
            encoderEglSurface = if (surface != null) {
                eglCore?.createWindowSurface(surface)
            } else {
                null
            }
            Log.d(TAG, "Encoder surface updated")
        }
    }

    fun setRoll(rollDegrees: Float) {
        Log.d(TAG, "Renderer roll = $rollDegrees")
        val limited = when (mode) {
            RollMode.AUTO -> rollDegrees.coerceIn(-autoMaxAngle, autoMaxAngle)
            RollMode.FULL -> rollDegrees
            RollMode.OFF -> 0f
        }
        rollRad = Math.toRadians(limited.toDouble()).toFloat()
    }

    fun release() {
        if (isReleased) return
        isReleased = true
        glHandler.removeCallbacksAndMessages(null)
        glHandler.post {
            try {
                eglCore?.makeNothingCurrent()
                previewEglSurface?.let { eglCore?.releaseSurface(it) }
                encoderEglSurface?.let { eglCore?.releaseSurface(it) }

                try {
                    cameraSurfaceTexture?.detachFromGLContext()
                } catch (_: RuntimeException) {}
                cameraSurfaceTexture?.release()
                cameraSurfaceTexture = null

                GLES20.glDeleteTextures(1, intArrayOf(cameraTextureId), 0)
                GLES20.glDeleteProgram(program)

                eglCore?.release()
                Log.d(TAG, "Renderer released")
            } finally {
                glThread.quitSafely()
            }
        }
    }

    private fun onFrameAvailable() {
        frameAvailable = true
        maybePostDraw()
    }

    private fun maybePostDraw() {
        if (!drawPending && !isReleased) {
            drawPending = true
            glHandler.post(drawTask)
        }
    }

    private val drawTask = Runnable {
        drawPending = false
        if (isReleased || !frameAvailable) return@Runnable
        frameAvailable = false
        drawFrame()
        if (frameAvailable) {
            maybePostDraw()
        }
    }

    private fun drawFrame() {
        try {
            val st = cameraSurfaceTexture ?: return

            val previewEgl = previewEglSurface
            val encoderEgl = encoderEglSurface

            if (previewEgl == null && encoderEgl == null) {
                return
            }

            val activeSurface = previewEgl ?: encoderEgl!!

            eglCore?.makeCurrent(activeSurface)

            Log.d(TAG, "drawFrame(): updateTexImage()")

            st.updateTexImage()

            Log.d(TAG, "drawFrame(): updateTexImage() OK")
            st.getTransformMatrix(textureTransformMatrix)

            computeTransformedTexCoords(textureTransformMatrix)

            val cosA = abs(cos(rollRad))
            val sinA = abs(sin(rollRad))
            val aspect = previewWidth.toFloat() / previewHeight.toFloat()

            val scaleX = cosA + sinA / aspect
            val scaleY = cosA + sinA * aspect
            val cropScale = max(scaleX, scaleY)  // >= 1

            Matrix.setIdentityM(viewMatrix, 0)
            // Rotate around Z to counter device tilt
            Log.d(TAG, "Drawing with roll = ${Math.toDegrees(rollRad.toDouble())}")
            Matrix.setRotateM(rotationMatrix, 0, Math.toDegrees(-rollRad.toDouble()).toFloat(), 0f, 0f, 1f)
            // Scale up to hide borders
            Matrix.setIdentityM(scaleMatrix, 0)
            Matrix.scaleM(scaleMatrix, 0, cropScale, cropScale, 1f)
            // Combine: rotate then scale
            Matrix.multiplyMM(viewMatrix, 0, rotationMatrix, 0, scaleMatrix, 0)
            Matrix.multiplyMM(mvpMatrix, 0, projectionMatrix, 0, viewMatrix, 0)

            if (previewEgl != null) {
                if (previewEgl != activeSurface) {
                    eglCore?.makeCurrent(previewEgl)
                }
                renderQuad()
                eglCore?.setPresentationTime(previewEgl, System.nanoTime())
                eglCore?.swapBuffers(previewEgl)
            }

            if (encoderEgl != null) {
                if (encoderEgl != previewEgl) {
                    eglCore?.makeCurrent(encoderEgl)
                }
                renderQuad()
                eglCore?.setPresentationTime(encoderEgl, System.nanoTime())
                eglCore?.swapBuffers(encoderEgl)
            }

            eglCore?.makeNothingCurrent()
        } catch (e: Exception) {
            Log.e(TAG, "drawFrame error", e)
        }
    }

    private fun renderQuad() {
        GLES20.glViewport(0, 0, previewWidth, previewHeight)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glUseProgram(program)

        val stride = 5 * 4
        vertexBuffer.position(0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 3, GLES20.GL_FLOAT, false, stride, vertexBuffer)

        texCoordBuffer.clear()
        texCoordBuffer.put(transformedTexCoords).flip()
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, texCoordBuffer)

        GLES20.glUniformMatrix4fv(uMVPMatrix, 1, false, mvpMatrix, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glUniform1i(uTexture, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
    }

    private fun computeTransformedTexCoords(matrix: FloatArray) {
        val src = floatArrayOf(0f, 0f, 0f, 1f, 1f, 0f, 1f, 1f)
        var idx = 0
        for (i in 0..3) {
            val u = src[i * 2]
            val v = src[i * 2 + 1]
            transformedTexCoords[idx] = matrix[0] * u + matrix[4] * v + matrix[12]
            transformedTexCoords[idx + 1] = matrix[1] * u + matrix[5] * v + matrix[13]
            idx += 2
        }
    }

    private fun buildProgram(vertexCode: String, fragmentCode: String): Int {
        val vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexCode)
        val fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentCode)
        if (vertexShader == 0 || fragmentShader == 0) throw RuntimeException("Shader compilation failed")
        val program = GLES20.glCreateProgram().also { prog ->
            if (prog == 0) throw RuntimeException("glCreateProgram failed")
            GLES20.glAttachShader(prog, vertexShader)
            GLES20.glAttachShader(prog, fragmentShader)
            GLES20.glLinkProgram(prog)
            val linkStatus = IntArray(1)
            GLES20.glGetProgramiv(prog, GLES20.GL_LINK_STATUS, linkStatus, 0)
            if (linkStatus[0] == 0) {
                val log = GLES20.glGetProgramInfoLog(prog)
                GLES20.glDeleteProgram(prog)
                throw RuntimeException("Program link failed: $log")
            }
        }
        GLES20.glDeleteShader(vertexShader)
        GLES20.glDeleteShader(fragmentShader)
        return program
    }

    private fun compileShader(type: Int, shaderCode: String): Int {
        val shader = GLES20.glCreateShader(type)
        if (shader == 0) throw RuntimeException("glCreateShader failed")
        GLES20.glShaderSource(shader, shaderCode)
        GLES20.glCompileShader(shader)
        val compileStatus = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compileStatus, 0)
        if (compileStatus[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw RuntimeException("Shader compile failed: $log")
        }
        return shader
    }

    private fun checkGlError(op: String) {
        val error = GLES20.glGetError()
        if (error != GLES20.GL_NO_ERROR) {
            throw RuntimeException("$op: glError $error")
        }
    }
}
