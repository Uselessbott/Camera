#!/bin/bash
set -e

echo "=== Fixing Horizon Lock compile errors ==="

# Delete the problematic example fragment (not needed after integration into CameraXPreview)
rm -f app/src/main/java/com/fossify/camera/fragments/VideoFragment_HorizonLock_example.kt

# Fix EglCore.kt – correct eglPresentationTimeANDROID extension method
cat << 'EOF' > app/src/main/java/com/fossify/camera/horizonlock/EglCore.kt
package com.fossify.camera.horizonlock

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.view.Surface

class EglCore {
    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var config: EGLConfig? = null

    fun initialize(sharedContext: EGLContext? = null) {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (display == EGL14.EGL_NO_DISPLAY) throw RuntimeException("EGL error: no display")
        val version = IntArray(2)
        EGL14.eglInitialize(display, version, 0, version, 1)
        val configAttribs = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        EGL14.eglChooseConfig(display, configAttribs, 0, configs, 0, 1, numConfigs, 0)
        config = configs[0]
        val contextAttribs = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL14.EGL_NONE
        )
        context = EGL14.eglCreateContext(display, config, sharedContext ?: EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
        if (context == EGL14.EGL_NO_CONTEXT) throw RuntimeException("EGL context creation failed")
    }

    fun createWindowSurface(surface: Surface): EGLSurface {
        val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
        return EGL14.eglCreateWindowSurface(display, config, surface, surfaceAttribs, 0)
    }

    fun createOffscreenSurface(width: Int, height: Int): EGLSurface {
        val surfaceAttribs = intArrayOf(
            EGL14.EGL_WIDTH, width,
            EGL14.EGL_HEIGHT, height,
            EGL14.EGL_NONE
        )
        return EGL14.eglCreatePbufferSurface(display, config, surfaceAttribs, 0)
    }

    fun makeCurrent(eglSurface: EGLSurface) {
        EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context)
    }

    fun makeNothingCurrent() {
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
    }

    fun swapBuffers(eglSurface: EGLSurface) {
        EGL14.eglSwapBuffers(display, eglSurface)
    }

    fun setPresentationTime(eglSurface: EGLSurface, nsecs: Long) {
        android.opengl.EGLExt.eglPresentationTimeANDROID(display, eglSurface, nsecs)
    }

    fun releaseSurface(eglSurface: EGLSurface) {
        EGL14.eglDestroySurface(display, eglSurface)
    }

    fun release() {
        if (display != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
            EGL14.eglReleaseThread()
            EGL14.eglTerminate(display)
        }
        display = EGL14.EGL_NO_DISPLAY
        context = EGL14.EGL_NO_CONTEXT
    }
}
EOF

# Fix HorizonLockEncoder.kt – correct MediaFormat constants and imports
cat << 'EOF' > app/src/main/java/com/fossify/camera/horizonlock/HorizonLockEncoder.kt
package com.fossify.camera.horizonlock

import android.media.*
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer

class HorizonLockEncoder(
    private val outputFile: File,
    private val videoWidth: Int,
    private val videoHeight: Int,
    private val videoFrameRate: Int,
    private val videoBitRate: Int,
    private val audioSampleRate: Int = 44100,
    private val audioChannels: Int = 2,
    private val audioBitRate: Int = 128000
) {
    private lateinit var videoCodec: MediaCodec
    private lateinit var audioCodec: MediaCodec
    private lateinit var muxer: MediaMuxer
    private var videoInputSurface: Surface? = null
    private var isRunning = false
    private var videoTrackIndex = -1
    private var audioTrackIndex = -1
    private var muxerStarted = false
    private val encoderThread = HandlerThread("HorizonLockEncoder").apply { start() }
    private val encoderHandler = Handler(encoderThread.looper)
    private var audioRecord: AudioRecord? = null
    private var audioRecordThread: Thread? = null

    fun prepare(): Surface {
        // Video encoder
        val videoFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, videoWidth, videoHeight)
        videoFormat.setInteger(MediaFormat.KEY_BIT_RATE, videoBitRate)
        videoFormat.setInteger(MediaFormat.KEY_FRAME_RATE, videoFrameRate)
        videoFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        videoFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)

        videoCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        videoCodec.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        videoInputSurface = videoCodec.createInputSurface()
        videoCodec.start()

        // Audio encoder
        val audioFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, audioSampleRate, audioChannels)
        audioFormat.setInteger(MediaFormat.KEY_BIT_RATE, audioBitRate)
        audioFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)

        audioCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        audioCodec.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        audioCodec.start()

        muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        isRunning = true
        return videoInputSurface!!
    }

    fun start() {
        encoderHandler.post {
            drainVideoEncoder()
        }
        startAudioRecording()
    }

    private fun startAudioRecording() {
        val channelConfig = if (audioChannels == 1) android.media.AudioFormat.CHANNEL_IN_MONO else android.media.AudioFormat.CHANNEL_IN_STEREO
        val minBufferSize = AudioRecord.getMinBufferSize(audioSampleRate, channelConfig, android.media.AudioFormat.ENCODING_PCM_16BIT)
        audioRecord = AudioRecord(MediaRecorder.AudioSource.MIC, audioSampleRate, channelConfig,
            android.media.AudioFormat.ENCODING_PCM_16BIT, minBufferSize * 2)
        audioRecord?.startRecording()

        audioRecordThread = Thread {
            val buffer = ByteBuffer.allocateDirect(minBufferSize)
            while (isRunning) {
                val readBytes = audioRecord?.read(buffer, minBufferSize) ?: 0
                if (readBytes > 0) {
                    buffer.position(0)
                    buffer.limit(readBytes)
                    encoderHandler.post {
                        val inputIndex = audioCodec.dequeueInputBuffer(10_000)
                        if (inputIndex >= 0) {
                            val inputBuffer = audioCodec.getInputBuffer(inputIndex)
                            inputBuffer?.clear()
                            inputBuffer?.put(buffer)
                            audioCodec.queueInputBuffer(inputIndex, 0, readBytes, System.nanoTime() / 1000, 0)
                        }
                    }
                }
            }
            audioRecord?.stop()
            audioRecord?.release()
        }.apply { start() }
    }

    fun stop() {
        isRunning = false
        encoderHandler.post {
            videoCodec.signalEndOfInputStream()
            drainVideoEncoder()
            videoCodec.stop()
            videoCodec.release()

            audioCodec.signalEndOfInputStream()
            drainAudioEncoder()
            audioCodec.stop()
            audioCodec.release()

            muxer.stop()
            muxer.release()
            encoderThread.quitSafely()
        }
    }

    private fun drainVideoEncoder() {
        val bufferInfo = MediaCodec.BufferInfo()
        while (isRunning || true) {
            val outputIndex = videoCodec.dequeueOutputBuffer(bufferInfo, 10_000)
            if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (muxerStarted) throw RuntimeException("video format changed twice")
                videoTrackIndex = muxer.addTrack(videoCodec.outputFormat)
                if (audioTrackIndex >= 0 && !muxerStarted) {
                    muxer.start()
                    muxerStarted = true
                }
            } else if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!isRunning) break
            } else if (outputIndex >= 0) {
                val outputBuffer = videoCodec.getOutputBuffer(outputIndex)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    videoCodec.releaseOutputBuffer(outputIndex, false)
                    continue
                }
                if (bufferInfo.size != 0 && muxerStarted) {
                    outputBuffer?.position(bufferInfo.offset)
                    outputBuffer?.limit(bufferInfo.offset + bufferInfo.size)
                    muxer.writeSampleData(videoTrackIndex, outputBuffer!!, bufferInfo)
                }
                videoCodec.releaseOutputBuffer(outputIndex, false)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
        }
    }

    private fun drainAudioEncoder() {
        val bufferInfo = MediaCodec.BufferInfo()
        while (true) {
            val outputIndex = audioCodec.dequeueOutputBuffer(bufferInfo, 10_000)
            if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                audioTrackIndex = muxer.addTrack(audioCodec.outputFormat)
                if (videoTrackIndex >= 0 && !muxerStarted) {
                    muxer.start()
                    muxerStarted = true
                }
            } else if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!isRunning) break
            } else if (outputIndex >= 0) {
                val outputBuffer = audioCodec.getOutputBuffer(outputIndex)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    audioCodec.releaseOutputBuffer(outputIndex, false)
                    continue
                }
                if (bufferInfo.size != 0 && muxerStarted) {
                    outputBuffer?.position(bufferInfo.offset)
                    outputBuffer?.limit(bufferInfo.offset + bufferInfo.size)
                    muxer.writeSampleData(audioTrackIndex, outputBuffer!!, bufferInfo)
                }
                audioCodec.releaseOutputBuffer(outputIndex, false)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
        }
    }
}
EOF

# Fix HorizonLockRenderer.kt – add missing import for EGLSurface and fix smart cast issues
cat << 'EOF' > app/src/main/java/com/fossify/camera/horizonlock/HorizonLockRenderer.kt
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
EOF

echo "=== Fixes applied. Now commit and push again. ==="
