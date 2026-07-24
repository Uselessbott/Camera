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
