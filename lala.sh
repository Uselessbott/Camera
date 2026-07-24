#!/bin/bash
# Apply Horizon Lock feature to Fossify Camera
# Run this script from the Camera/ root folder.

set -e

echo "Creating horizonlock package directory..."
mkdir -p app/src/main/java/com/fossify/camera/horizonlock

echo "Writing EglCore.kt..."
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
        EGL14.eglPresentationTimeANDROID(display, eglSurface, nsecs)
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

echo "Writing SensorFusionManager.kt..."
cat << 'EOF' > app/src/main/java/com/fossify/camera/horizonlock/SensorFusionManager.kt
package com.fossify.camera.horizonlock

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import kotlin.math.*

class SensorFusionManager(private val context: Context) : SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val rotationVectorSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private var fusedRoll = 0f
    private var filteredRoll = 0f
    private val smoothFactor = 0.9f
    private var currentGyroZ = 0f
    private var lastTimestamp = 0L
    private var gravity: FloatArray = floatArrayOf(0f, 0f, 9.81f)
    private var orientation = FloatArray(3)

    private val _rollLiveData = MutableLiveData<Float>(0f)
    val rollLiveData: LiveData<Float> = _rollLiveData

    private val handlerThread = HandlerThread("SensorFusion")
    private val handler: Handler

    init {
        handlerThread.start()
        handler = Handler(handlerThread.looper)
    }

    fun start() {
        if (rotationVectorSensor != null) {
            sensorManager.registerListener(this, rotationVectorSensor, SensorManager.SENSOR_DELAY_GAME, handler)
        } else {
            if (gyroscope != null) sensorManager.registerListener(this, gyroscope, SensorManager.SENSOR_DELAY_GAME, handler)
            if (accelerometer != null) sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME, handler)
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
        handlerThread.quitSafely()
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                val rotationMatrix = FloatArray(9)
                SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
                SensorManager.getOrientation(rotationMatrix, orientation)
                fusedRoll = Math.toDegrees(orientation[2].toDouble()).toFloat()
                applyFilter()
            }
            Sensor.TYPE_GYROSCOPE -> {
                val dt = (event.timestamp - lastTimestamp) / 1e9f
                if (lastTimestamp != 0L && dt > 0) {
                    currentGyroZ += event.values[2] * dt
                }
                lastTimestamp = event.timestamp
            }
            Sensor.TYPE_ACCELEROMETER -> {
                val alpha = 0.8f
                gravity[0] = alpha * gravity[0] + (1 - alpha) * event.values[0]
                gravity[1] = alpha * gravity[1] + (1 - alpha) * event.values[1]
                gravity[2] = alpha * gravity[2] + (1 - alpha) * event.values[2]
                val norm = sqrt(gravity[0] * gravity[0] + gravity[1] * gravity[1] + gravity[2] * gravity[2])
                gravity[0] /= norm; gravity[1] /= norm; gravity[2] /= norm
            }
        }
        if (rotationVectorSensor == null && gyroscope != null) {
            fusedRoll = currentGyroZ.coerceIn(-180f, 180f)
        }
        if (rotationVectorSensor == null) applyFilter()
    }

    private fun applyFilter() {
        filteredRoll = smoothFactor * filteredRoll + (1 - smoothFactor) * fusedRoll
        _rollLiveData.postValue(filteredRoll)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
EOF

echo "Writing HorizonLockRenderer.kt..."
cat << 'EOF' > app/src/main/java/com/fossify/camera/horizonlock/HorizonLockRenderer.kt
package com.fossify.camera.horizonlock

import android.graphics.SurfaceTexture
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
        if (previewSurface != null) eglCore.releaseSurface(previewSurface!!)
        previewSurface = eglCore.createWindowSurface(surface)
        Matrix.orthoM(projectionMatrix, 0, -1f, 1f, -1f, 1f, -1f, 1f)
    }

    fun setEncoderSurface(surface: Surface?) {
        if (encoderSurface != null) {
            eglCore.releaseSurface(encoderSurface!!)
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
        // Compute crop factor: ensures no black borders after rotation
        val cosA = kotlin.math.abs(kotlin.math.cos(rollRad))
        val sinA = kotlin.math.abs(kotlin.math.sin(rollRad))
        val cropFactor = if (cosA + sinA > 0.001f) 1f / (cosA + sinA) else 1f

        Matrix.setIdentityM(viewMatrix, 0)
        Matrix.setRotateM(rotationMatrix, 0, -rollRad, 0f, 0f, 1f)
        Matrix.setIdentityM(scaleMatrix, 0)
        Matrix.scaleM(scaleMatrix, 0, cropFactor, cropFactor, 1f)
        Matrix.multiplyMM(viewMatrix, 0, rotationMatrix, 0, scaleMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, projectionMatrix, 0, viewMatrix, 0)

        if (previewSurface != null) {
            eglCore.makeCurrent(previewSurface!!)
            renderInternal()
            eglCore.setPresentationTime(previewSurface!!, timestampNanos)
            eglCore.swapBuffers(previewSurface!!)
        }

        if (encoderSurface != null) {
            eglCore.makeCurrent(encoderSurface!!)
            renderInternal()
            eglCore.setPresentationTime(encoderSurface!!, timestampNanos)
            eglCore.swapBuffers(encoderSurface!!)
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
        if (previewSurface != null) eglCore.releaseSurface(previewSurface!!)
        if (encoderSurface != null) eglCore.releaseSurface(encoderSurface!!)
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

echo "Writing HorizonLockEncoder.kt..."
cat << 'EOF' > app/src/main/java/com/fossify/camera/horizonlock/HorizonLockEncoder.kt
package com.fossify.camera.horizonlock

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import java.io.File

class HorizonLockEncoder(
    private val outputFile: File,
    private val width: Int,
    private val height: Int,
    private val frameRate: Int,
    private val bitRate: Int
) {
    private lateinit var mediaCodec: MediaCodec
    private lateinit var muxer: MediaMuxer
    private var inputSurface: Surface? = null
    private var isRunning = false
    private var trackIndex = -1
    private var muxerStarted = false
    private val handlerThread = HandlerThread("Encoder")
    private val handler: Handler

    init {
        handlerThread.start()
        handler = Handler(handlerThread.looper)
    }

    fun prepare(): Surface {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIME_TYPE_AVC, width, height)
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
        format.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)

        mediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIME_TYPE_AVC)
        mediaCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = mediaCodec.createInputSurface()
        mediaCodec.start()

        muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        isRunning = true
        return inputSurface!!
    }

    fun start() {
        handler.post { drainEncoder() }
    }

    fun stop() {
        isRunning = false
        handler.post {
            mediaCodec.signalEndOfInputStream()
            drainEncoder()
            mediaCodec.stop()
            mediaCodec.release()
            muxer.stop()
            muxer.release()
            handlerThread.quitSafely()
        }
    }

    private fun drainEncoder() {
        val bufferInfo = MediaCodec.BufferInfo()
        while (isRunning || true) {
            val outputIndex = mediaCodec.dequeueOutputBuffer(bufferInfo, 10_000)
            if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (muxerStarted) throw RuntimeException("format changed twice")
                val newFormat = mediaCodec.outputFormat
                trackIndex = muxer.addTrack(newFormat)
                muxer.start()
                muxerStarted = true
            } else if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!isRunning) break
            } else if (outputIndex >= 0) {
                val outputBuffer = mediaCodec.getOutputBuffer(outputIndex)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    mediaCodec.releaseOutputBuffer(outputIndex, false)
                    continue
                }
                if (bufferInfo.size != 0 && muxerStarted) {
                    outputBuffer?.position(bufferInfo.offset)
                    outputBuffer?.limit(bufferInfo.offset + bufferInfo.size)
                    muxer.writeSampleData(trackIndex, outputBuffer!!, bufferInfo)
                }
                mediaCodec.releaseOutputBuffer(outputIndex, false)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
        }
    }
}
EOF

echo "Adding horizon lock preference to preferences.xml..."
# Assumes preferences.xml exists and has </PreferenceScreen> somewhere.
if [ -f app/src/main/res/xml/preferences.xml ]; then
    if grep -q '<PreferenceCategory android:title="Horizon Lock"' app/src/main/res/xml/preferences.xml; then
        echo "Horizon Lock preference already exists, skipping."
    else
        sed -i 's|</PreferenceScreen>|    <PreferenceCategory android:title="Horizon Lock">\n        <ListPreference\n            android:key="horizon_lock_mode"\n            android:title="Mode"\n            android:summary="OFF / AUTO / ON"\n            android:entries="@array/horizon_lock_entries"\n            android:entryValues="@array/horizon_lock_values"\n            android:defaultValue="off" />\n    </PreferenceCategory>\n</PreferenceScreen>|' app/src/main/res/xml/preferences.xml
        echo "Preference inserted."
    fi
else
    echo "preferences.xml not found, skipping horizon lock preference addition."
fi

# Add string arrays for the ListPreference if not present
if [ -f app/src/main/res/values/strings.xml ]; then
    if grep -q 'horizon_lock_entries' app/src/main/res/values/strings.xml; then
        echo "String arrays already exist."
    else
        echo "Adding string arrays for horizon lock..."
        sed -i 's|</resources>|    <string-array name="horizon_lock_entries">\n        <item>Off</item>\n        <item>Auto</item>\n        <item>On</item>\n    </string-array>\n    <string-array name="horizon_lock_values">\n        <item>off</item>\n        <item>auto</item>\n        <item>on</item>\n    </string-array>\n</resources>|' app/src/main/res/values/strings.xml
    fi
else
    echo "strings.xml not found."
fi

echo "Creating reference VideoFragment_HorizonLock_example.kt..."
mkdir -p app/src/main/java/com/fossify/camera/fragments
cat << 'EOF' > app/src/main/java/com/fossify/camera/fragments/VideoFragment_HorizonLock_example.kt
package com.fossify.camera.fragments

import android.graphics.SurfaceTexture
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.view.*
import androidx.fragment.app.Fragment
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import com.fossify.camera.R
import com.fossify.camera.horizonlock.*
import java.io.File
import java.util.concurrent.Executors

/**
 * Example replacement for VideoFragment with full Horizon Lock integration.
 * Replace your VideoFragment with this code, adapting package and imports.
 */
class VideoFragment : Fragment() {
    private lateinit var textureView: TextureView
    private lateinit var renderer: HorizonLockRenderer
    private lateinit var sensorManager: SensorFusionManager
    private var encoder: HorizonLockEncoder? = null
    private val renderingHandler = HandlerThread("Rendering").apply { start() }
    private val executor = Executors.newSingleThreadExecutor()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        return inflater.inflate(R.layout.fragment_video, container, false).also {
            textureView = it.findViewById(R.id.texture_preview) // you must add a TextureView with this id to layout
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        renderer = HorizonLockRenderer()
        renderer.init()
        sensorManager = SensorFusionManager(requireContext())
        sensorManager.rollLiveData.observe(viewLifecycleOwner) { roll ->
            renderer.setRoll(roll)
        }

        // Read preference
        val prefs = requireContext().getSharedPreferences("camera_prefs", 0) // adapt
        val modeStr = prefs.getString("horizon_lock_mode", "off") ?: "off"
        renderer.mode = when (modeStr) {
            "on" -> RollMode.FULL
            "auto" -> RollMode.AUTO.also { renderer.autoMaxAngle = 30f }
            else -> RollMode.OFF
        }
        if (renderer.mode != RollMode.OFF) sensorManager.start()

        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                renderer.setPreviewSurface(Surface(surface), width, height)
                startRenderingLoop()
                startCamera()
            }
            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
                renderer.setPreviewSurface(Surface(surface), width, height)
            }
            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true
            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
        }
    }

    private fun startCamera() {
        val cameraProvider = ProcessCameraProvider.getInstance(requireContext())
        val preview = Preview.Builder()
            .setTargetResolution(android.util.Size(1920, 1080))
            .build()
        preview.setSurfaceProvider { request ->
            val surfaceTexture = renderer.getCameraSurfaceTexture()
            surfaceTexture.setDefaultBufferSize(request.resolution.width, request.resolution.height)
            val surface = Surface(surfaceTexture)
            request.provideSurface(surface, executor) { result -> /* success */ }
            request.setListener({ }, executor) // empty listener
        }
        cameraProvider.get().bindToLifecycle(viewLifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview)
    }

    private fun startRenderingLoop() {
        val handler = Handler(renderingHandler.looper)
        val choreographer = Choreographer.getInstance()
        val frameCallback = object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                renderer.drawFrame(frameTimeNanos)
                choreographer.postFrameCallback(this)
            }
        }
        handler.post { choreographer.postFrameCallback(frameCallback) }
    }

    fun startRecording() {
        val outputFile = File(requireContext().externalCacheDir, "horizon_locked_video.mp4")
        encoder = HorizonLockEncoder(outputFile, 1920, 1080, 30, 10_000_000)
        val surface = encoder!!.prepare()
        renderer.setEncoderSurface(surface)
        encoder!!.start()
    }

    fun stopRecording() {
        encoder?.stop()
        encoder = null
        renderer.setEncoderSurface(null)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        sensorManager.stop()
        renderer.release()
        renderingHandler.quitSafely()
    }
}
EOF

echo "Horizon Lock feature files installed."
echo ""
echo "Manual integration steps:"
echo "1. Replace your VideoFragment (or relevant recording fragment) with the example provided in fragments/VideoFragment_HorizonLock_example.kt, adapting layout and logic."
echo "2. Ensure your layout contains a TextureView with id texture_preview."
echo "3. Add required permissions and features if not present (android.permission.CAMERA, etc.)."
echo "4. Sync Gradle and test."
