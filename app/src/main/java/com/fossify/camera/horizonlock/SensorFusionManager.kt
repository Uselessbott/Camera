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
