package com.fossify.camera.horizonlock

import android.graphics.SurfaceTexture
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

enum class RollMode { OFF, AUTO, FULL }

class HorizonLockRenderer {
    private lateinit var eglCore: EglCore
    private var previewSurface: EGLSurface? = null
    private var encoderSurface: EGLSurface? = null
    private var cameraTextureId = 0
    private var surfaceTexture: SurfaceTexture? = null
    private var program = 0
    private var aPosition = 0
    private var aTexCoord = 0
    private var uMVPMatrix = 0
    private var uTexture = 0
    private val mvpMatrix = FloatArray(16)
    private val projectionMatrix = FloatArray(16)
    private val viewMatrix = FloatArray(16)
    private val rotationMatrix = FloatArray(16)
    private val scaleMatrix = FloatArray(16)
    private var rollRad = 0f
    private var rollDeg = 0f
    private var outputWidth = 0
    private var outputHeight = 0
    var mode: RollMode = RollMode.OFF
    var autoMaxAngle: Float = 30f

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

    fun init() {
        eglCore = EglCore()
        eglCore.initialize()
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        cameraTextureId = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        surfaceTexture = SurfaceTexture(cameraTextureId)
        program = buildProgram(vertexShaderCode, fragmentShaderCode)
        aPosition = GLES20.glGetAttribLocation(program, "aPosition")
        aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
        uMVPMatrix = GLES20.glGetUniformLocation(program, "uMVPMatrix")
        uTexture = GLES20.glGetUniformLocation(program, "uTexture")
    }

    fun getCameraSurfaceTexture(): SurfaceTexture = surfaceTexture!!

    fun setPreviewSurface(surface: Surface, width: Int, height: Int) {
        outputWidth = width
        outputHeight = height
        val safePreview = previewSurface
        if (safePreview != null) eglCore.releaseSurface(safePreview)
        previewSurface = eglCore.createWindowSurface(surface)
        Matrix.orthoM(projectionMatrix, 0, -1f, 1f, -1f, 1f, -1f, 1f)
    }

    fun setEncoderSurface(surface: Surface?) {
        val safeEncoder = encoderSurface
        if (safeEncoder != null) {
            eglCore.releaseSurface(safeEncoder)
            encoderSurface = null
        }
        if (surface != null) {
            encoderSurface = eglCore.createWindowSurface(surface)
        }
    }

    fun setRoll(rollDegrees: Float) {
        rollDeg = when (mode) {
            RollMode.AUTO -> rollDegrees.coerceIn(-autoMaxAngle, autoMaxAngle)
            RollMode.FULL -> rollDegrees
            RollMode.OFF -> 0f
        }
        rollRad = Math.toRadians(rollDeg.toDouble()).toFloat()
    }

    fun drawFrame(timestampNanos: Long) {
        surfaceTexture?.updateTexImage()
        val cosA = kotlin.math.abs(kotlin.math.cos(rollRad))
        val sinA = kotlin.math.abs(kotlin.math.sin(rollRad))
        val cropFactor = if (cosA + sinA > 0.001f) 1f / (cosA + sinA) else 1f

        Matrix.setIdentityM(viewMatrix, 0)
        Matrix.setRotateM(rotationMatrix, 0, -rollRad, 0f, 0f, 1f)
        Matrix.setIdentityM(scaleMatrix, 0)
        Matrix.scaleM(scaleMatrix, 0, cropFactor, cropFactor, 1f)
        Matrix.multiplyMM(viewMatrix, 0, rotationMatrix, 0, scaleMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, projectionMatrix, 0, viewMatrix, 0)

        val safePreview = previewSurface
        if (safePreview != null) {
            eglCore.makeCurrent(safePreview)
            renderInternal()
            eglCore.setPresentationTime(safePreview, timestampNanos)
            eglCore.swapBuffers(safePreview)
        }

        val safeEncoder = encoderSurface
        if (safeEncoder != null) {
            eglCore.makeCurrent(safeEncoder)
            renderInternal()
            eglCore.setPresentationTime(safeEncoder, timestampNanos)
            eglCore.swapBuffers(safeEncoder)
        }
    }

    private fun renderInternal() {
        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glUseProgram(program)

        val quadVertices = floatArrayOf(
            -1f,  1f, 0f, 0f, 0f,
            -1f, -1f, 0f, 0f, 1f,
             1f,  1f, 0f, 1f, 0f,
             1f, -1f, 0f, 1f, 1f
        )
        val buffer = ByteBuffer.allocateDirect(quadVertices.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        buffer.put(quadVertices).position(0)

        GLES20.glUniformMatrix4fv(uMVPMatrix, 1, false, mvpMatrix, 0)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glUniform1i(uTexture, 0)

        val stride = 5 * 4
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 3, GLES20.GL_FLOAT, false, stride, buffer)

        GLES20.glEnableVertexAttribArray(aTexCoord)
        buffer.position(3)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, stride, buffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
    }

    fun release() {
        eglCore.makeNothingCurrent()
        val safePreview = previewSurface
        if (safePreview != null) eglCore.releaseSurface(safePreview)
        val safeEncoder = encoderSurface
        if (safeEncoder != null) eglCore.releaseSurface(safeEncoder)
        surfaceTexture?.release()
        GLES20.glDeleteTextures(1, intArrayOf(cameraTextureId), 0)
        GLES20.glDeleteProgram(program)
        eglCore.release()
    }

    private fun buildProgram(vertexCode: String, fragmentCode: String): Int {
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexCode)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentCode)
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)
        return program
    }

    private fun loadShader(type: Int, shaderCode: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, shaderCode)
        GLES20.glCompileShader(shader)
        return shader
    }
}
