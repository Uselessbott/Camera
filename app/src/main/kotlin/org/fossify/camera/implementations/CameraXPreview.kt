package org.fossify.camera.implementations

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.util.Log
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
import com.fossify.camera.horizonlock.*
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
        private const val TAG = "CameraXPreview"
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
    private var horizonLockReady = false
    private var horizonLockOutputFile: File? = null

    private val orientationEventListener = object : OrientationEventListener(activity, SensorManager.SENSOR_DELAY_NORMAL) {
        @SuppressLint("RestrictedApi")
        override fun onOrientationChanged(orientation: Int) {
            if (orientation == UNKNOWN_ORIENTATION) return
            if (horizonLockEnabled) return  // rotation handled by renderer

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
        if (videoCapture == null) {
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
        horizonLockRenderer = HorizonLockRenderer { errorMsg ->
            Log.e(TAG, "HorizonLock error: $errorMsg")
            activity.runOnUiThread {
                activity.toast(R.string.camera_open_error)
                toggleHorizonLock(false)
            }
        }
        horizonLockRenderer!!.init { surfaceTexture ->
            horizonLockReady = true
            Log.d(TAG, "HorizonLock renderer ready, SurfaceTexture obtained")
            textureView?.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(surface: android.graphics.SurfaceTexture, width: Int, height: Int) {
                    Log.d(TAG, "TextureView surface available: ${width}x${height}")
                    horizonLockRenderer?.setPreviewSurface(Surface(surface), width, height)
                }
                override fun onSurfaceTextureSizeChanged(surface: android.graphics.SurfaceTexture, width: Int, height: Int) {
                    Log.d(TAG, "TextureView surface size changed: ${width}x${height}")
                    horizonLockRenderer?.setPreviewSurface(Surface(surface), width, height)
                }
                override fun onSurfaceTextureDestroyed(surface: android.graphics.SurfaceTexture): Boolean {
                    Log.d(TAG, "TextureView surface destroyed")
                    horizonLockRenderer?.clearPreviewSurface()
                    return true
                }
                override fun onSurfaceTextureUpdated(surface: android.graphics.SurfaceTexture) {}
            }
            sensorFusionManager = SensorFusionManager(activity)
            sensorFusionManager!!.rollLiveData.observe(activity) { roll ->
                Log.d(TAG, "Sensor roll = $roll")
                horizonLockRenderer?.setRoll(roll)
            }
            sensorFusionManager!!.start()
            if (activity.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                startCamera()
            }
        }
    }

    private fun bindToLifeCycle() {
        activity.lifecycle.addObserver(this)
    }

    private fun startCamera(switching: Boolean = false) {
        if (horizonLockEnabled && !horizonLockReady) {
            Log.d(TAG, "startCamera deferred – renderer not ready")
            return
        }

        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity.applicationContext)
        cameraProviderFuture.addListener({
            try {
                val provider = cameraProviderFuture.get()
                cameraProvider = provider
                imageQualityManager.initSupportedQualities()
                videoQualityManager.initSupportedQualities(provider)
                bindCameraUseCases()
                setupCameraObservers()
                Log.d(TAG, "Camera started successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Camera start failed", e)
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
        val captureUseCase: UseCase = if (isPhotoCapture) {
            buildImageCapture(targetResolution, rotation).also {
                imageCapture = it
                videoCapture = null
            }
        } else {
            buildVideoCapture().also {
                videoCapture = it
                imageCapture = null
            }
        }

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

        previewView.visibility = if (horizonLockEnabled) View.GONE else View.VISIBLE
        textureView?.visibility = if (horizonLockEnabled) View.VISIBLE else View.GONE
        Log.d(TAG, "bindCameraUseCases done, horizonLockEnabled=$horizonLockEnabled")
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
                        Log.d(TAG, "Providing camera surface to CameraX")
                        request.provideSurface(surface, ContextCompat.getMainExecutor(activity)) { result ->
                            Log.d(TAG, "CameraX surface released, result=$result")
                            surface.release()
                        }
                    }
                } else {
                    setSurfaceProvider(previewView.surfaceProvider)
                }
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
                    val targetView = if (horizonLockEnabled) textureView else previewView
                    if (targetView == null) return@let false
                    val width = targetView.width.toFloat()
                    val height = targetView.height.toFloat()
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
        val targetView = if (horizonLockEnabled) textureView else previewView
        targetView?.setOnTouchListener { _, event ->
            val handledGesture = gestureDetector.onTouchEvent(event)
            val handledScaleGesture = scaleGesture?.onTouchEvent(event)
            handledGesture || handledScaleGesture ?: false
        }
    }

    override fun onStart(owner: LifecycleOwner) {
        orientationEventListener.enable()
        previewView.doOnLayout {
            // Reinitialize Horizon Lock if it was released
            if (horizonLockEnabled && horizonLockRenderer == null) {
                initHorizonLock()
            }
            if (!horizonLockEnabled || horizonLockReady) {
                startCamera()
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
            // Stop any ongoing HL recording
            horizonLockEncoder?.stop()
            horizonLockEncoder = null
            horizonLockRenderer?.setEncoderSurface(null)
            horizonLockOutputFile = null

            horizonLockRenderer?.release()
            horizonLockRenderer = null
            sensorFusionManager?.stop()
            sensorFusionManager = null
            horizonLockReady = false
        }
    }

    override fun isInPhotoMode(): Boolean = isPhotoCapture

    override fun showChangeResolution() {
        val selectedResolution = if (isPhotoCapture) {
            imageQualityManager.getUserSelectedResolution(cameraSelector).toResolutionOption()
        } else {
            videoQualityManager.getUserSelectedQuality(cameraSelector).toResolutionOption()
        }

        val resolutions = if (isPhotoCapture) {
            imageQualityManager.getSupportedResolutions(cameraSelector)
                .map { it.toResolutionOption() }
        } else {
            videoQualityManager.getSupportedQualities(cameraSelector)
                .map { it.toResolutionOption() }
        }

        if (resolutions.size > 2) {
            listener.showImageSizes(
                selectedResolution = selectedResolution,
                resolutions = resolutions,
                isPhotoCapture = isPhotoCapture,
                isFrontCamera = isFrontCameraInUse()
            ) { index, changed ->
                mediaSizeStore.storeSize(isPhotoCapture, isFrontCameraInUse(), index)
                if (changed) {
                    currentRecording?.stop()
                    startCamera()
                }
            }
        } else {
            toggleResolutions(resolutions)
        }
    }

    private fun toggleResolutions(resolutions: List<ResolutionOption>) {
        if (resolutions.size >= 2) {
            val currentIndex =
                mediaSizeStore.getCurrentSizeIndex(isPhotoCapture, isFrontCameraInUse())

            val nextIndex = if (currentIndex >= resolutions.lastIndex) {
                0
            } else {
                currentIndex + 1
            }

            mediaSizeStore.storeSize(isPhotoCapture, isFrontCameraInUse(), nextIndex)
            currentRecording?.stop()
            startCamera()
        }
    }

    override fun toggleFrontBackCamera() {
        val newCameraSelector = if (isFrontCameraInUse()) {
            CameraSelector.DEFAULT_BACK_CAMERA
        } else {
            CameraSelector.DEFAULT_FRONT_CAMERA
        }

        cameraSelector = newCameraSelector
        config.lastUsedCameraLens = newCameraSelector.toLensFacing()
        startCamera(switching = true)
    }

    override fun handleFlashlightClick() {
        if (isPhotoCapture) {
            listener.showFlashOptions(true)
        } else {
            toggleFlashlight()
        }
    }

    private fun toggleFlashlight() {
        val newFlashMode = if (isPhotoCapture) {
            when (flashMode) {
                FLASH_MODE_OFF -> FLASH_MODE_ON
                FLASH_MODE_ON -> FLASH_MODE_AUTO
                else -> FLASH_MODE_OFF
            }
        } else {
            when (flashMode) {
                FLASH_MODE_OFF -> FLASH_MODE_ON
                else -> FLASH_MODE_OFF
            }
        }
        setFlashlightState(newFlashMode.toAppFlashMode())
    }

    override fun setFlashlightState(state: Int) {
        var flashState = state
        if (isPhotoCapture) {
            camera?.cameraControl?.enableTorch(flashState == FLASH_ALWAYS_ON)
        } else {
            camera?.cameraControl?.enableTorch(flashState == FLASH_ON || flashState == FLASH_ALWAYS_ON)
            if (flashState == FLASH_ALWAYS_ON) {
                flashState = FLASH_ON
            }
        }
        val newFlashMode = flashState.toCameraXFlashMode()
        flashMode = newFlashMode
        imageCapture?.flashMode = newFlashMode

        config.flashlightState = flashState
        listener.onChangeFlashMode(flashState)
    }

    override fun tryTakePicture() {
        if (imageCapture == null) {
            activity.toast(R.string.camera_open_error)
            return
        }

        val imageCapture = imageCapture

        val metadata = Metadata().apply {
            isReversedHorizontal = isFrontCameraInUse() && config.flipPhotos
            if (config.savePhotoVideoLocation) {
                location = simpleLocationManager?.getLocation()
            }
        }

        val mediaOutput = mediaOutputHelper.getImageMediaOutput()
        imageCapture!!.takePicture(mainExecutor, object : OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                listener.shutterAnimation()
                playShutterSoundIfEnabled()
                ensureBackgroundThread {
                    image.use {
                        if (mediaOutput is MediaOutput.BitmapOutput) {
                            val imageBytes = ImageUtil.jpegImageToJpegByteArray(image)
                            val bitmap = BitmapUtils.makeBitmap(imageBytes)
                            activity.runOnUiThread {
                                listener.onPhotoCaptureEnd()
                                if (bitmap != null) {
                                    listener.onImageCaptured(bitmap)
                                } else {
                                    cameraErrorHandler.handleImageCaptureError(ERROR_CAPTURE_FAILED)
                                }
                            }
                        } else {
                            ImageSaver.saveImage(
                                contentResolver = contentResolver,
                                image = image,
                                mediaOutput = mediaOutput,
                                metadata = metadata,
                                jpegQuality = config.photoQuality,
                                saveExifAttributes = config.savePhotoMetadata,
                                onImageSaved = { savedUri ->
                                    activity.runOnUiThread {
                                        listener.onPhotoCaptureEnd()
                                        listener.onMediaSaved(savedUri)
                                    }
                                },
                                onError = ::handleImageCaptureError
                            )
                        }
                    }
                }
            }

            override fun onError(exception: ImageCaptureException) {
                handleImageCaptureError(exception)
            }
        })
    }

    private fun handleImageCaptureError(exception: ImageCaptureException) {
        listener.onPhotoCaptureEnd()
        cameraErrorHandler.handleImageCaptureError(exception.imageCaptureError)
    }

    override fun toggleHorizonLock(enabled: Boolean) {
        if (horizonLockEnabled == enabled) return
        Log.d(TAG, "toggleHorizonLock: $enabled")

        horizonLockEnabled = enabled

        if (enabled) {
            horizonLockReady = false
            initHorizonLock()
        } else {
            horizonLockRenderer?.release()
            horizonLockRenderer = null
            sensorFusionManager?.stop()
            sensorFusionManager = null
            horizonLockReady = false
            startCamera()
        }
    }

    override fun initPhotoMode() {
        if (horizonLockEnabled) {
            textureView?.surfaceTexture?.let { st ->
                horizonLockRenderer?.setPreviewSurface(
                    Surface(st),
                    textureView!!.width,
                    textureView!!.height
                )
            }
        }
        debounceChangeCameraMode(photoModeRunnable)
    }

    override fun initVideoMode() {
        if (horizonLockEnabled) {
            textureView?.surfaceTexture?.let { st ->
                horizonLockRenderer?.setPreviewSurface(
                    Surface(st),
                    textureView!!.width,
                    textureView!!.height
                )
            }
        }
        debounceChangeCameraMode(videoModeRunnable)
    }

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
            // Horizon Lock recording – optional encoder, CameraX VideoCapture still bound
            if (horizonLockEncoder == null) {
                horizonLockOutputFile = File(activity.cacheDir, "horizon_video_${System.currentTimeMillis()}.mp4")
                horizonLockEncoder = HorizonLockEncoder(horizonLockOutputFile!!, 1920, 1080, 30, 10_000_000)
                val encoderSurface = horizonLockEncoder!!.prepare()
                horizonLockRenderer?.setEncoderSurface(encoderSurface)
                horizonLockEncoder!!.start()
                listener.onVideoRecordingStarted()
                Log.d(TAG, "HorizonLock encoder started")
            } else {
                horizonLockEncoder?.stop()
                horizonLockEncoder = null
                horizonLockRenderer?.setEncoderSurface(null)
                listener.onVideoRecordingStopped()
                horizonLockOutputFile?.let { file ->
                    listener.onMediaSaved(android.net.Uri.fromFile(file))
                }
                horizonLockOutputFile = null
                Log.d(TAG, "HorizonLock encoder stopped")
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
}
