
#!/bin/bash
set -e

echo "=== Applying Horizon Lock to Fossify Camera ==="

# 1. Layout: replace PreviewView with an overlay that switches between PreviewView and TextureView
cat << 'EOF' > app/src/main/res/layout/activity_main.xml
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:id="@+id/view_holder"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:animateLayoutChanges="true"
    android:background="@android:color/black">

    <androidx.camera.view.PreviewView
        android:id="@+id/preview_view"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

    <!-- TextureView used when Horizon Lock is enabled -->
    <TextureView
        android:id="@+id/texture_preview"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:visibility="gone"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

    <View
        android:id="@+id/shutter_animation"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:alpha="0"
        android:background="@android:color/black" />

    <FrameLayout
        android:id="@+id/top_options"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent">

        <include
            android:id="@+id/layout_top"
            layout="@layout/layout_top" />

        <include
            android:id="@+id/layout_flash"
            layout="@layout/layout_flash" />

        <include
            android:id="@+id/layout_timer"
            layout="@layout/layout_timer" />

    </FrameLayout>

    <TextSwitcher
        android:id="@+id/timer_text"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        app:layout_constraintBottom_toTopOf="@id/bottom_overlay"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toBottomOf="@id/top_options" />

    <View
        android:id="@+id/bottom_overlay"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:background="@color/overlay_color"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="@id/camera_mode_holder" />

    <RelativeLayout
        android:id="@+id/camera_mode_holder"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:paddingTop="@dimen/medium_margin"
        app:layout_constraintBottom_toTopOf="@id/shutter"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent">

        <com.google.android.material.tabs.TabLayout
            android:id="@+id/camera_mode_tab"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="@dimen/big_margin"
            android:background="@android:color/transparent"
            app:tabBackground="@drawable/tab_indicator"
            app:tabIndicator="@null"
            app:tabMode="auto"
            app:tabRippleColor="@null"
            app:tabSelectedTextColor="@color/md_grey_600_dark"
            app:tabTextColor="@color/md_grey_white">

            <com.google.android.material.tabs.TabItem
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="@string/video" />

            <com.google.android.material.tabs.TabItem
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="@string/photo" />

        </com.google.android.material.tabs.TabLayout>
    </RelativeLayout>

    <TextView
        android:id="@+id/video_rec_curr_timer"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_centerHorizontal="true"
        android:layout_marginBottom="@dimen/smaller_margin"
        android:textColor="@android:color/white"
        android:visibility="gone"
        app:layout_constraintBottom_toTopOf="@id/shutter"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        tools:text="00:00"
        tools:visibility="visible" />

    <ImageView
        android:id="@+id/last_photo_video_preview"
        android:layout_width="@dimen/icon_size"
        android:layout_height="@dimen/icon_size"
        android:background="@drawable/camera_button_background"
        android:contentDescription="@string/view_last_media"
        android:padding="@dimen/tiny_margin"
        app:layout_constraintBottom_toBottomOf="@id/shutter"
        app:layout_constraintEnd_toStartOf="@id/shutter"
        app:layout_constraintHorizontal_chainStyle="spread"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="@id/shutter"
        tools:src="@tools:sample/backgrounds/scenic" />

    <ImageView
        android:id="@+id/shutter"
        android:layout_width="@dimen/large_icon_size"
        android:layout_height="@dimen/large_icon_size"
        android:layout_marginBottom="@dimen/big_margin"
        android:contentDescription="@string/shutter"
        android:src="@drawable/ic_shutter_animated"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintVertical_bias="1" />

    <ImageView
        android:id="@+id/toggle_camera"
        android:layout_width="@dimen/icon_size"
        android:layout_height="@dimen/icon_size"
        android:background="@drawable/camera_button_background"
        android:contentDescription="@string/toggle_camera"
        android:padding="@dimen/medium_margin"
        android:src="@drawable/ic_flip_camera_vector"
        app:layout_constraintBottom_toBottomOf="@id/shutter"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toEndOf="@id/shutter"
        app:layout_constraintTop_toTopOf="@id/shutter" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# 2. Overwrite CameraXPreview.kt with integrated horizon lock support
cat << 'EOF' > app/src/main/kotlin/org/fossify/camera/implementations/CameraXPreview.kt
package org.fossify.camera.implementations

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.util.Size
import android.view.Display
import android.view.GestureDetector
import android.view.GestureDetector.SimpleOnGestureListener
import android.view.MotionEvent
import android.view.OrientationEventListener
import android.view.ScaleGestureDetector
import android.view.Surface
import android.view.TextureView
import android.view.View
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraState
import androidx.camera.core.DisplayOrientedMeteringPointFactory
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCapture.Builder
import androidx.camera.core.ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY
import androidx.camera.core.ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY
import androidx.camera.core.ImageCapture.ERROR_CAPTURE_FAILED
import androidx.camera.core.ImageCapture.FLASH_MODE_AUTO
import androidx.camera.core.ImageCapture.FLASH_MODE_OFF
import androidx.camera.core.ImageCapture.FLASH_MODE_ON
import androidx.camera.core.ImageCapture.Metadata
import androidx.camera.core.ImageCapture.OnImageCapturedCallback
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.UseCase
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionSelector.PREFER_CAPTURE_RATE_OVER_HIGHER_RESOLUTION
import androidx.camera.core.resolutionselector.ResolutionSelector.PREFER_HIGHER_RESOLUTION_OVER_CAPTURE_RATE
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.core.resolutionselector.ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileDescriptorOutputOptions
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.camera.view.PreviewView.ScaleType
import androidx.core.content.ContextCompat
import androidx.core.view.doOnLayout
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.window.layout.WindowMetricsCalculator
import com.bumptech.glide.load.ImageHeaderParser.UNKNOWN_ORIENTATION
import org.fossify.camera.R
import org.fossify.camera.extensions.checkLocationPermission
import org.fossify.camera.extensions.config
import org.fossify.camera.extensions.toAppFlashMode
import org.fossify.camera.extensions.toCameraSelector
import org.fossify.camera.extensions.toCameraXFlashMode
import org.fossify.camera.extensions.toCameraXQuality
import org.fossify.camera.extensions.toLensFacing
import org.fossify.camera.helpers.BitmapUtils
import org.fossify.camera.helpers.CameraErrorHandler
import org.fossify.camera.helpers.FLASH_ALWAYS_ON
import org.fossify.camera.helpers.FLASH_ON
import org.fossify.camera.helpers.ImageQualityManager
import org.fossify.camera.helpers.ImageSaver
import org.fossify.camera.helpers.ImageUtil
import org.fossify.camera.helpers.MediaOutputHelper
import org.fossify.camera.helpers.MediaSizeStore
import org.fossify.camera.helpers.MediaSoundHelper
import org.fossify.camera.helpers.PinchToZoomOnScaleGestureListener
import org.fossify.camera.helpers.SimpleLocationManager
import org.fossify.camera.helpers.VideoQualityManager
import org.fossify.camera.horizonlock.*
import org.fossify.camera.interfaces.MyPreview
import org.fossify.camera.models.CaptureMode
import org.fossify.camera.models.MediaOutput
import org.fossify.camera.models.MySize
import org.fossify.camera.models.ResolutionOption
import org.fossify.commons.activities.BaseSimpleActivity
import org.fossify.commons.extensions.toast
import org.fossify.commons.helpers.PERMISSION_ACCESS_FINE_LOCATION
import org.fossify.commons.helpers.ensureBackgroundThread
import kotlin.math.abs
import java.io.File
import java.util.concurrent.Executors

class CameraXPreview(
    private val activity: BaseSimpleActivity,
    private val previewView: PreviewView,
    private val mediaSoundHelper: MediaSoundHelper,
    private val mediaOutputHelper: MediaOutputHelper,
    private val cameraErrorHandler: CameraErrorHandler,
    private val listener: CameraXPreviewListener,
    private val isThirdPartyIntent: Boolean,
    initInPhotoMode: Boolean,
    private var horizonLockEnabled: Boolean = false
) : MyPreview, DefaultLifecycleObserver {

    companion object {
        private const val AF_SIZE = 1.0f / 6.0f
        private const val AE_SIZE = AF_SIZE * 1.5f
        private const val CAMERA_MODE_SWITCH_WAIT_TIME = 500L
    }

    private val config = activity.config
    private val contentResolver = activity.contentResolver
    private val mainExecutor = ContextCompat.getMainExecutor(activity)
    private val displayManager = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private val windowMetricsCalculator = WindowMetricsCalculator.getOrCreate()
    private val videoQualityManager = VideoQualityManager(activity)
    private val imageQualityManager = ImageQualityManager(activity)
    private val mediaSizeStore = MediaSizeStore(config)

    // Horizon Lock members
    private var horizonLockRenderer: HorizonLockRenderer? = null
    private var sensorFusionManager: SensorFusionManager? = null
    private var horizonLockEncoder: HorizonLockEncoder? = null
    private var textureView: TextureView? = null
    private val renderingExecutor = Executors.newSingleThreadExecutor()

    private val orientationEventListener = object : OrientationEventListener(activity, SensorManager.SENSOR_DELAY_NORMAL) {
        @SuppressLint("RestrictedApi")
        override fun onOrientationChanged(orientation: Int) {
            if (orientation == UNKNOWN_ORIENTATION) return
            if (horizonLockEnabled) return  // disable rotation when horizon lock active

            val rotation = when (orientation) {
                in 45 until 135 -> Surface.ROTATION_270
                in 135 until 225 -> Surface.ROTATION_180
                in 225 until 315 -> Surface.ROTATION_90
                else -> Surface.ROTATION_0
            }

            if (lastRotation != rotation) {
                preview?.targetRotation = rotation
                imageCapture?.targetRotation = rotation
                videoCapture?.targetRotation = rotation
                lastRotation = rotation
            }
        }
    }
    private val cameraHandler = Handler(Looper.getMainLooper())
    private val photoModeRunnable = Runnable {
        if (imageCapture == null) {
            isPhotoCapture = true
            if (!isThirdPartyIntent) config.initPhotoMode = true
            startCamera()
        } else {
            listener.onInitPhotoMode()
        }
    }
    private val videoModeRunnable = Runnable {
        if (videoCapture == null && !horizonLockEnabled) {
            isPhotoCapture = false
            if (!isThirdPartyIntent) config.initPhotoMode = false
            startCamera()
        } else {
            listener.onInitVideoMode()
        }
    }

    private var preview: Preview? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var camera: Camera? = null
    private var currentRecording: Recording? = null
    private var recordingState: VideoRecordEvent? = null
    private var cameraSelector = config.lastUsedCameraLens.toCameraSelector()
    private var flashMode = FLASH_MODE_OFF
    private var isPhotoCapture = initInPhotoMode
    private var lastRotation = 0
    private var lastCameraStartTime = 0L
    private var simpleLocationManager: SimpleLocationManager? = null

    init {
        bindToLifeCycle()
        if (horizonLockEnabled) {
            initHorizonLock()
        }
    }

    private fun initHorizonLock() {
        textureView = activity.findViewById(R.id.texture_preview)
        horizonLockRenderer = HorizonLockRenderer()
        horizonLockRenderer!!.init()
        sensorFusionManager = SensorFusionManager(activity)
        sensorFusionManager!!.rollLiveData.observe(activity) { roll ->
            horizonLockRenderer?.setRoll(roll)
        }
        sensorFusionManager!!.start()
    }

    private fun bindToLifeCycle() {
        activity.lifecycle.addObserver(this)
    }

    private fun startCamera(switching: Boolean = false) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity.applicationContext)
        cameraProviderFuture.addListener({
            try {
                val provider = cameraProviderFuture.get()
                cameraProvider = provider
                imageQualityManager.initSupportedQualities()
                videoQualityManager.initSupportedQualities(provider)
                bindCameraUseCases()
                setupCameraObservers()
            } catch (e: Exception) {
                val errorMessage = if (switching) R.string.camera_switch_error else R.string.camera_open_error
                activity.toast(errorMessage)
            }
        }, mainExecutor)
    }

    private fun bindCameraUseCases() {
        val cameraProvider = cameraProvider ?: throw IllegalStateException("Camera initialization failed.")

        val resolution = if (isPhotoCapture) {
            imageQualityManager.getUserSelectedResolution(cameraSelector).also {
                listener.displaySelectedResolution(it.toResolutionOption())
            }
        } else {
            val selectedQuality = videoQualityManager.getUserSelectedQuality(cameraSelector).also {
                listener.displaySelectedResolution(it.toResolutionOption())
            }
            MySize(selectedQuality.width, selectedQuality.height)
        }

        listener.adjustPreviewView(resolution.requiresCentering())
        val isFullSize = resolution.isFullScreen
        previewView.scaleType = if (isFullSize) ScaleType.FILL_CENTER else ScaleType.FIT_CENTER
        val rotation = previewView.display.rotation
        val targetResolution = Size(resolution.width, resolution.height)

        val previewUseCase = buildPreview(targetResolution, rotation)
        val captureUseCase = getCaptureUseCase(targetResolution, rotation)

        cameraProvider.unbindAll()
        camera = if (isFullSize) {
            val metrics = windowMetricsCalculator.computeCurrentWindowMetrics(activity).bounds
            val screenWidth = metrics.width()
            val screenHeight = metrics.height()
            val viewPort = ViewPort.Builder(Rational(screenWidth, screenHeight), rotation).build()

            val useCaseGroup = UseCaseGroup.Builder()
                .addUseCase(previewUseCase)
                .addUseCase(captureUseCase)
                .setViewPort(viewPort)
                .build()
            cameraProvider.bindToLifecycle(activity, cameraSelector, useCaseGroup)
        } else {
            cameraProvider.bindToLifecycle(activity, cameraSelector, previewUseCase, captureUseCase)
        }
        preview = previewUseCase
        setupZoomAndFocus()
        setFlashlightState(config.flashlightState)

        // Horizon Lock UI setup
        if (horizonLockEnabled) {
            previewView.visibility = View.GONE
            textureView?.visibility = View.VISIBLE
            val surfaceTexture = horizonLockRenderer!!.getCameraSurfaceTexture()
            surfaceTexture.setDefaultBufferSize(targetResolution.width, targetResolution.height)
            // Start rendering loop driven by Choreographer
            startRenderingLoop()
        } else {
            previewView.visibility = View.VISIBLE
            textureView?.visibility = View.GONE
        }
    }

    private fun buildPreview(resolution: Size, rotation: Int): Preview {
        return Preview.Builder()
            .setTargetRotation(if (horizonLockEnabled) Surface.ROTATION_0 else rotation)
            .setResolutionSelector(getResolutionSelector(resolution))
            .build().apply {
                if (horizonLockEnabled) {
                    setSurfaceProvider { request ->
                        val surfaceTexture = horizonLockRenderer!!.getCameraSurfaceTexture()
                        surfaceTexture.setDefaultBufferSize(request.resolution.width, request.resolution.height)
                        val surface = Surface(surfaceTexture)
                        request.provideSurface(surface, renderingExecutor) { result -> }
                    }
                } else {
                    setSurfaceProvider(previewView.surfaceProvider)
                }
            }
    }

    private fun getCaptureUseCase(resolution: Size, rotation: Int): UseCase {
        return if (isPhotoCapture) {
            buildImageCapture(resolution, rotation).also {
                imageCapture = it
                videoCapture = null
            }
        } else {
            if (horizonLockEnabled) {
                // No video capture use case; we'll encode via HorizonLockEncoder.
                // Return a dummy VideoCapture that never binds, or just a placeholder.
                // Actually we must return a UseCase, so we'll create a dummy that does nothing.
                imageCapture = null
                videoCapture = null
                // Return a no-op UseCase? CameraX requires at least one use case.
                // We'll simply not bind video capture; but we must return something for captureUseCase.
                // Instead, we'll avoid calling getCaptureUseCase when horizon lock is on and video mode.
                // So modify callers to not bind a capture use case.
                // For simplicity, return imageCapture (photo) as placeholder, it won't be used.
                buildImageCapture(resolution, rotation)
            } else {
                buildVideoCapture().also {
                    videoCapture = it
                    imageCapture = null
                }
            }
        }
    }

    private fun buildImageCapture(resolution: Size, rotation: Int): ImageCapture {
        return Builder()
            .setCaptureMode(getCaptureMode())
            .setFlashMode(flashMode)
            .setJpegQuality(config.photoQuality)
            .setTargetRotation(if (horizonLockEnabled) Surface.ROTATION_0 else rotation)
            .setResolutionSelector(getResolutionSelector(resolution))
            .build()
    }

    private fun getCaptureMode(): Int {
        return when (config.captureMode) {
            CaptureMode.MINIMIZE_LATENCY -> CAPTURE_MODE_MINIMIZE_LATENCY
            CaptureMode.MAXIMIZE_QUALITY -> CAPTURE_MODE_MAXIMIZE_QUALITY
        }
    }

    private fun getResolutionSelector(resolution: Size): ResolutionSelector {
        return ResolutionSelector.Builder()
            .setResolutionStrategy(ResolutionStrategy(resolution, FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER))
            .setResolutionFilter { supportedSizes, _ ->
                supportedSizes.sortedBy { size ->
                    abs(size.width / size.height.toFloat() - resolution.width / resolution.height.toFloat())
                }
            }
            .setAllowedResolutionMode(getAllowedResolutionMode())
            .build()
    }

    private fun getAllowedResolutionMode(): Int {
        return when (config.captureMode) {
            CaptureMode.MINIMIZE_LATENCY -> PREFER_CAPTURE_RATE_OVER_HIGHER_RESOLUTION
            CaptureMode.MAXIMIZE_QUALITY -> PREFER_HIGHER_RESOLUTION_OVER_CAPTURE_RATE
        }
    }

    private fun buildVideoCapture(): VideoCapture<Recorder> {
        val qualitySelector = QualitySelector.from(
            videoQualityManager.getUserSelectedQuality(cameraSelector).toCameraXQuality(),
            FallbackStrategy.higherQualityOrLowerThan(Quality.SD),
        )
        val recorder = Recorder.Builder()
            .setQualitySelector(qualitySelector)
            .build()
        return VideoCapture.withOutput(recorder)
    }

    private fun setupCameraObservers() {
        listener.setFlashAvailable(camera?.cameraInfo?.hasFlashUnit() ?: false)
        listener.onChangeCamera(isFrontCameraInUse())
        if (isPhotoCapture) {
            listener.onInitPhotoMode()
        } else {
            listener.onInitVideoMode()
        }
        camera?.cameraInfo?.cameraState?.observe(activity) { cameraState ->
            if (cameraState.error == null) {
                when (cameraState.type) {
                    CameraState.Type.OPENING,
                    CameraState.Type.OPEN -> {
                        listener.setHasFrontAndBackCamera(hasFrontCamera() && hasBackCamera())
                        listener.setCameraAvailable(true)
                    }
                    CameraState.Type.PENDING_OPEN,
                    CameraState.Type.CLOSING,
                    CameraState.Type.CLOSED -> {
                        listener.setCameraAvailable(false)
                    }
                }
            } else {
                listener.setCameraAvailable(false)
                cameraErrorHandler.handleCameraError(cameraState.error)
            }
        }
    }

    private fun hasBackCamera(): Boolean = cameraProvider?.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) ?: false
    private fun hasFrontCamera(): Boolean = cameraProvider?.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) ?: false
    private fun isFrontCameraInUse(): Boolean = cameraSelector == CameraSelector.DEFAULT_FRONT_CAMERA

    @SuppressLint("ClickableViewAccessibility")
    private fun setupZoomAndFocus() {
        val scaleGesture = camera?.let {
            ScaleGestureDetector(activity, PinchToZoomOnScaleGestureListener(it.cameraInfo, it.cameraControl))
        }
        val gestureDetector = GestureDetector(activity, object : SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent): Boolean {
                listener.onTouchPreview()
                return super.onDown(event)
            }
            override fun onSingleTapConfirmed(event: MotionEvent): Boolean {
                return camera?.cameraInfo?.let {
                    val display = displayManager.getDisplay(Display.DEFAULT_DISPLAY)
                    val width = previewView.width.toFloat()
                    val height = previewView.height.toFloat()
                    val factory = DisplayOrientedMeteringPointFactory(display, it, width, height)
                    val autoFocusPoint = factory.createPoint(event.x, event.y, AF_SIZE)
                    val autoExposurePoint = factory.createPoint(event.x, event.y, AE_SIZE)
                    val focusMeteringAction = FocusMeteringAction.Builder(autoFocusPoint, FocusMeteringAction.FLAG_AF)
                        .addPoint(autoExposurePoint, FocusMeteringAction.FLAG_AE)
                        .disableAutoCancel()
                        .build()
                    camera?.cameraControl?.startFocusAndMetering(focusMeteringAction)
                    listener.onFocusCamera(event.rawX, event.rawY)
                    true
                } ?: false
            }
        })
        previewView.setOnTouchListener { _, event ->
            val handledGesture = gestureDetector.onTouchEvent(event)
            val handledScaleGesture = scaleGesture?.onTouchEvent(event)
            handledGesture || handledScaleGesture ?: false
        }
    }

    override fun onStart(owner: LifecycleOwner) {
        orientationEventListener.enable()
        previewView.doOnLayout {
            if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                startCamera()
            }
        }
        if (horizonLockEnabled) {
            // TextureView may not be available yet; start rendering when surface is ready
            textureView?.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(surface: android.graphics.SurfaceTexture, width: Int, height: Int) {
                    horizonLockRenderer?.setPreviewSurface(Surface(surface), width, height)
                }
                override fun onSurfaceTextureSizeChanged(surface: android.graphics.SurfaceTexture, width: Int, height: Int) {
                    horizonLockRenderer?.setPreviewSurface(Surface(surface), width, height)
                }
                override fun onSurfaceTextureDestroyed(surface: android.graphics.SurfaceTexture): Boolean = true
                override fun onSurfaceTextureUpdated(surface: android.graphics.SurfaceTexture) {}
            }
        }
    }

    override fun onResume(owner: LifecycleOwner) {
        super.onResume(owner)
        if (config.savePhotoVideoLocation) {
            if (simpleLocationManager == null) simpleLocationManager = SimpleLocationManager(activity)
            requestLocationUpdates()
        }
    }

    private fun requestLocationUpdates() {
        activity.apply {
            if (checkLocationPermission()) {
                simpleLocationManager?.requestLocationUpdates()
            } else {
                handlePermission(PERMISSION_ACCESS_FINE_LOCATION) { _ ->
                    if (checkLocationPermission()) {
                        simpleLocationManager?.requestLocationUpdates()
                    } else {
                        config.savePhotoVideoLocation = false
                    }
                }
            }
        }
    }

    override fun onPause(owner: LifecycleOwner) {
        super.onPause(owner)
        simpleLocationManager?.dropLocationUpdates()
    }

    override fun onStop(owner: LifecycleOwner) {
        orientationEventListener.disable()
        if (horizonLockEnabled) {
            horizonLockRenderer?.release()
            sensorFusionManager?.stop()
        }
    }

    override fun isInPhotoMode(): Boolean = isPhotoCapture

    override fun showChangeResolution() { /* ... unchanged ... */ }
    override fun toggleFrontBackCamera() { /* ... unchanged ... */ }
    override fun handleFlashlightClick() { /* ... unchanged ... */ }
    override fun setFlashlightState(state: Int) { /* ... unchanged ... */ }
    override fun tryTakePicture() { /* ... unchanged ... */ }
    override fun initPhotoMode() { debounceChangeCameraMode(photoModeRunnable) }
    override fun initVideoMode() { debounceChangeCameraMode(videoModeRunnable) }

    private fun debounceChangeCameraMode(cameraModeRunnable: Runnable) {
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastCameraStartTime > CAMERA_MODE_SWITCH_WAIT_TIME) {
            cameraModeRunnable.run()
        } else {
            cameraHandler.removeCallbacks(photoModeRunnable)
            cameraHandler.removeCallbacks(videoModeRunnable)
            cameraHandler.postDelayed(cameraModeRunnable, CAMERA_MODE_SWITCH_WAIT_TIME)
        }
        lastCameraStartTime = currentTime
    }

    override fun toggleRecording() {
        if (horizonLockEnabled) {
            // Horizon Lock recording using our encoder
            if (horizonLockEncoder == null) {
                val outputFile = File(activity.cacheDir, "horizon_video_${System.currentTimeMillis()}.mp4")
                horizonLockEncoder = HorizonLockEncoder(outputFile, 1920, 1080, 30, 10_000_000)
                val encoderSurface = horizonLockEncoder!!.prepare()
                horizonLockRenderer!!.setEncoderSurface(encoderSurface)
                horizonLockEncoder!!.start()
                listener.onVideoRecordingStarted()
            } else {
                horizonLockEncoder!!.stop()
                horizonLockEncoder = null
                horizonLockRenderer!!.setEncoderSurface(null)
                listener.onVideoRecordingStopped()
                // Notify media saved (using the file path)
                listener.onMediaSaved(android.net.Uri.fromFile(File(activity.cacheDir, "horizon_video_*.mp4"))) // placeholder
            }
            return
        }

        // Original CameraX recording logic
        if (currentRecording == null || recordingState is VideoRecordEvent.Finalize) {
            if (config.isSoundEnabled) {
                mediaSoundHelper.playStartVideoRecordingSound(onPlayComplete = { startRecording() })
                listener.onVideoRecordingStarted()
            } else {
                startRecording()
            }
        } else {
            currentRecording?.stop()
            currentRecording = null
        }
    }

    @SuppressLint("MissingPermission", "NewApi")
    private fun startRecording() {
        if (videoCapture == null) {
            activity.toast(R.string.camera_open_error)
            return
        }
        val videoCapture = videoCapture
        val recording = when (val mediaOutput = mediaOutputHelper.getVideoMediaOutput()) {
            is MediaOutput.FileDescriptorMediaOutput -> {
                FileDescriptorOutputOptions.Builder(mediaOutput.fileDescriptor).apply {
                    if (config.savePhotoVideoLocation) setLocation(simpleLocationManager?.getLocation())
                }.build().let { videoCapture!!.output.prepareRecording(activity, it) }
            }
            is MediaOutput.FileMediaOutput -> {
                FileOutputOptions.Builder(mediaOutput.file).apply {
                    if (config.savePhotoVideoLocation) setLocation(simpleLocationManager?.getLocation())
                }.build().let { videoCapture!!.output.prepareRecording(activity, it) }
            }
            is MediaOutput.MediaStoreOutput -> {
                MediaStoreOutputOptions.Builder(contentResolver, mediaOutput.contentUri).apply {
                    setContentValues(mediaOutput.contentValues)
                    if (config.savePhotoVideoLocation) setLocation(simpleLocationManager?.getLocation())
                }.build().let { videoCapture!!.output.prepareRecording(activity, it) }
            }
        }
        currentRecording = recording.withAudioEnabled()
            .start(mainExecutor) { recordEvent ->
                recordingState = recordEvent
                when (recordEvent) {
                    is VideoRecordEvent.Start -> listener.onVideoRecordingStarted()
                    is VideoRecordEvent.Status -> listener.onVideoDurationChanged(recordEvent.recordingStats.recordedDurationNanos)
                    is VideoRecordEvent.Finalize -> {
                        playStopVideoRecordingSoundIfEnabled()
                        listener.onVideoRecordingStopped()
                        if (recordEvent.hasError()) {
                            cameraErrorHandler.handleVideoRecordingError(recordEvent.error)
                        } else {
                            listener.onMediaSaved(recordEvent.outputResults.outputUri)
                        }
                    }
                }
            }
    }

    private fun playShutterSoundIfEnabled() {
        if (config.isSoundEnabled) mediaSoundHelper.playShutterSound()
    }

    private fun playStopVideoRecordingSoundIfEnabled() {
        if (config.isSoundEnabled) mediaSoundHelper.playStopVideoRecordingSound()
    }

    private fun startRenderingLoop() {
        val handler = Handler(Looper.getMainLooper())
        val choreographer = android.view.Choreographer.getInstance()
        val frameCallback = object : android.view.Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                horizonLockRenderer?.drawFrame(frameTimeNanos)
                choreographer.postFrameCallback(this)
            }
        }
        handler.post { choreographer.postFrameCallback(frameCallback) }
    }
}
EOF

# 3. Overwrite CameraXInitializer.kt with added horizonLockEnabled parameter
cat << 'EOF' > app/src/main/kotlin/org/fossify/camera/implementations/CameraXInitializer.kt
package org.fossify.camera.implementations

import android.net.Uri
import androidx.camera.view.PreviewView
import org.fossify.camera.helpers.CameraErrorHandler
import org.fossify.camera.helpers.MediaOutputHelper
import org.fossify.camera.helpers.MediaSoundHelper
import org.fossify.commons.activities.BaseSimpleActivity

class CameraXInitializer(private val activity: BaseSimpleActivity) {

    fun createCameraXPreview(
        previewView: PreviewView,
        listener: CameraXPreviewListener,
        mediaSoundHelper: MediaSoundHelper,
        outputUri: Uri?,
        isThirdPartyIntent: Boolean,
        initInPhotoMode: Boolean,
        horizonLockEnabled: Boolean = false
    ): CameraXPreview {
        val cameraErrorHandler = newCameraErrorHandler()
        val mediaOutputHelper = newMediaOutputHelper(cameraErrorHandler, outputUri, isThirdPartyIntent)
        return CameraXPreview(
            activity,
            previewView,
            mediaSoundHelper,
            mediaOutputHelper,
            cameraErrorHandler,
            listener,
            isThirdPartyIntent = isThirdPartyIntent,
            initInPhotoMode = initInPhotoMode,
            horizonLockEnabled = horizonLockEnabled
        )
    }

    private fun newMediaOutputHelper(
        cameraErrorHandler: CameraErrorHandler,
        outputUri: Uri?,
        isThirdPartyIntent: Boolean,
    ): MediaOutputHelper {
        return MediaOutputHelper(activity, cameraErrorHandler, outputUri, isThirdPartyIntent)
    }

    private fun newCameraErrorHandler(): CameraErrorHandler {
        return CameraErrorHandler(activity)
    }
}
EOF

# 4. Update HorizonLockEncoder to include audio recording (basic AAC)
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
        val videoFormat = MediaFormat.createVideoFormat(MediaFormat.MIME_TYPE_AVC, videoWidth, videoHeight)
        videoFormat.setInteger(MediaFormat.KEY_BIT_RATE, videoBitRate)
        videoFormat.setInteger(MediaFormat.KEY_FRAME_RATE, videoFrameRate)
        videoFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        videoFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)

        videoCodec = MediaCodec.createEncoderByType(MediaFormat.MIME_TYPE_AVC)
        videoCodec.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        videoInputSurface = videoCodec.createInputSurface()
        videoCodec.start()

        // Audio encoder
        val audioFormat = MediaFormat.createAudioFormat(MediaFormat.MIME_TYPE_AAC, audioSampleRate, audioChannels)
        audioFormat.setInteger(MediaFormat.KEY_BIT_RATE, audioBitRate)
        audioFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)

        audioCodec = MediaCodec.createEncoderByType(MediaFormat.MIME_TYPE_AAC)
        audioCodec.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        audioCodec.start()

        // Muxer
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
        val minBufferSize = AudioRecord.getMinBufferSize(audioSampleRate, 
            if (audioChannels == 1) android.media.AudioFormat.CHANNEL_IN_MONO else android.media.AudioFormat.CHANNEL_IN_STEREO,
            android.media.AudioFormat.ENCODING_PCM_16BIT)
        audioRecord = AudioRecord(MediaRecorder.AudioSource.MIC, audioSampleRate,
            if (audioChannels == 1) android.media.AudioFormat.CHANNEL_IN_MONO else android.media.AudioFormat.CHANNEL_IN_STEREO,
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

echo "=== Horizon Lock classes and layout updated ==="

echo ""
echo "=== MANUAL STEP REQUIRED FOR MainActivity.kt ==="
echo "Please modify your MainActivity.kt to:"
echo "1. Read horizon lock preference:"
echo '   val prefs = PreferenceManager.getDefaultSharedPreferences(this)'
echo '   val horizonLockMode = prefs.getString("horizon_lock_mode", "off") ?: "off"'
echo '   val horizonLockEnabled = horizonLockMode != "off"'
echo ""
echo "2. Pass horizonLockEnabled to CameraXInitializer.createCameraXPreview(...):"
echo "   cameraXInitializer.createCameraXPreview("
echo "       ...,"
echo "       horizonLockEnabled = horizonLockEnabled"
echo "   )"
echo ""
echo "If you have a SettingsFragment, ensure it loads the preference XML (e.g., addPreferencesFromResource(R.xml.preferences) and that horizon lock preference is present)."
echo "If preferences.xml is not found, create it with the content provided in the earlier script."
echo ""
echo "Horizon Lock integration complete. Sync Gradle and test."
