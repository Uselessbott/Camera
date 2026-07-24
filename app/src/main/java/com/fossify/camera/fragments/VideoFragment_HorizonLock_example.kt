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
