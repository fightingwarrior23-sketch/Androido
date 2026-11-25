package com.lecturestamper.lecture_stamper

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.*
import android.os.Bundle
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Slide pictures + one audio file -> small MP4, using only Android's own codecs.
 * Three steps, each into a temp file: audio -> AAC, pictures -> H.264 (2 fps), then mux.
 */
class VideoExporter(
    private val cancel: AtomicBoolean,
    private val cacheDir: File,
    private val videoKbps: Int,
    private val onProgress: (Double) -> Unit,
) {
    class Slide(val startUs: Long, val imagePath: String)

    companion object {
        const val W = 1920
        const val H = 1080
        const val FPS = 2
        const val FRAME_US = 1_000_000L / FPS
        const val AUDIO_KBPS = 96
        const val TIMEOUT_US = 5_000L
    }

    private fun check() {
        if (cancel.get()) throw CancellationException("cancelled")
    }

    fun export(slides: List<Slide>, audioPath: String, out: File) {
        val tmpAudio = File(cacheDir, "stamper_audio.m4a")
        val tmpVideo = File(cacheDir, "stamper_video.mp4")
        try {
            val durationUs = transcodeAudio(audioPath, tmpAudio) { onProgress(0.45 * it) }
            check()
            encodeVideo(slides, durationUs, tmpVideo) { onProgress(0.45 + 0.50 * it) }
            check()
            mux(tmpVideo, tmpAudio, out)
            onProgress(1.0)
        } catch (t: Throwable) {
            out.delete()
            throw t
        } finally {
            tmpAudio.delete()
            tmpVideo.delete()
        }
    }

    // ------------------------------------------------------------------ audio
    /** Returns the audio length in microseconds. */
    private fun transcodeAudio(src: String, dst: File, progress: (Double) -> Unit): Long {
        val ex = MediaExtractor()
        ex.setDataSource(src)
        var track = -1
        for (i in 0 until ex.trackCount) {
            val mime = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) { track = i; break }
        }
        if (track < 0) { ex.release(); throw IllegalStateException("No audio track in this file") }
        ex.selectTrack(track)
        val inFmt = ex.getTrackFormat(track)
        val totalUs = if (inFmt.containsKey(MediaFormat.KEY_DURATION)) inFmt.getLong(MediaFormat.KEY_DURATION) else 0L

        val dec = MediaCodec.createDecoderByType(inFmt.getString(MediaFormat.KEY_MIME)!!)
        dec.configure(inFmt, null, null, 0)
        dec.start()

        val muxer = MediaMuxer(dst.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var enc: MediaCodec? = null
        var sink: Sink? = null
        var rate = 0
        var channels = 0
        var samples = 0L
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var decDone = false

        fun startEncoder(fmt: MediaFormat) {
            rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            if (channels > 2) throw IllegalStateException("Audio with more than 2 channels is not supported")
            val ef = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, channels)
            ef.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            ef.setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_KBPS * 1000)
            ef.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 64 * 1024)
            val e = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            e.configure(ef, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            e.start()
            enc = e
            sink = Sink(e, muxer)
        }

        fun feed(buf: ByteBuffer, off: Int, size: Int) {
            val e = enc!!
            val frame = 2 * channels
            buf.position(off)
            buf.limit(off + size)
            while (buf.hasRemaining()) {
                check()
                val ii = e.dequeueInputBuffer(TIMEOUT_US)
                if (ii < 0) { sink!!.drain(); continue }
                val ib = e.getInputBuffer(ii)!!
                ib.clear()
                var n = minOf(ib.remaining(), buf.remaining())
                n -= n % frame
                if (n <= 0) { e.queueInputBuffer(ii, 0, 0, 0, 0); break }
                val slice = buf.duplicate()
                slice.limit(slice.position() + n)
                ib.put(slice)
                buf.position(buf.position() + n)
                val pts = samples * 1_000_000L / rate
                e.queueInputBuffer(ii, 0, n, pts, 0)
                samples += n / frame
            }
        }

        try {
            while (!decDone) {
                check()
                if (!inputDone) {
                    val i = dec.dequeueInputBuffer(TIMEOUT_US)
                    if (i >= 0) {
                        val b = dec.getInputBuffer(i)!!
                        val n = ex.readSampleData(b, 0)
                        if (n < 0) {
                            dec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            dec.queueInputBuffer(i, 0, n, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val oi = dec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (enc == null) startEncoder(dec.outputFormat)
                } else if (oi >= 0) {
                    if (info.size > 0) {
                        if (enc == null) startEncoder(dec.outputFormat)
                        feed(dec.getOutputBuffer(oi)!!, info.offset, info.size)
                    }
                    dec.releaseOutputBuffer(oi, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) decDone = true
                }
                sink?.drain()
                if (totalUs > 0 && rate > 0) {
                    progress((samples * 1_000_000L / rate).toDouble() / totalUs)
                }
            }
            val e = enc ?: throw IllegalStateException("Could not decode this audio file")
            // end of stream for the encoder
            while (true) {
                check()
                val ii = e.dequeueInputBuffer(TIMEOUT_US)
                if (ii >= 0) {
                    e.queueInputBuffer(ii, 0, 0, samples * 1_000_000L / rate, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                sink!!.drain()
            }
            while (!sink!!.eos) { check(); sink!!.drain() }
            progress(1.0)
            return samples * 1_000_000L / rate
        } finally {
            try { dec.stop() } catch (_: Throwable) {}
            dec.release()
            try { enc?.stop() } catch (_: Throwable) {}
            enc?.release()
            if (sink?.started == true) { try { muxer.stop() } catch (_: Throwable) {} }
            muxer.release()
            ex.release()
        }
    }

    /** Pulls finished buffers out of an encoder and writes them to a muxer. */
    private class Sink(val enc: MediaCodec, val muxer: MediaMuxer) {
        var started = false
        var eos = false
        private var track = -1
        private val info = MediaCodec.BufferInfo()

        fun drain() {
            while (true) {
                val oi = enc.dequeueOutputBuffer(info, 0)
                when {
                    oi == MediaCodec.INFO_TRY_AGAIN_LATER -> return
                    oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        track = muxer.addTrack(enc.outputFormat)
                        muxer.start()
                        started = true
                    }
                    oi >= 0 -> {
                        val b = enc.getOutputBuffer(oi)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && started) {
                            b.position(info.offset)
                            b.limit(info.offset + info.size)
                            muxer.writeSampleData(track, b, info)
                        }
                        enc.releaseOutputBuffer(oi, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) { eos = true; return }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ video
    private fun newVideoEncoder(): Pair<MediaCodec, MediaFormat> {
        fun fmt() = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, W, H).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, videoKbps * 1000)
            setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
            setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 20)
            setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
            setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
        }
        var lastError: Throwable? = null
        val candidates = listOf<String?>(null, "c2.android.avc.encoder", "OMX.google.h264.encoder")
        for (name in candidates) {
            try {
                val c = if (name == null) MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
                else MediaCodec.createByCodecName(name)
                val f = fmt()
                c.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                return Pair(c, f)
            } catch (t: Throwable) {
                lastError = t
            }
        }
        throw IllegalStateException("No H.264 encoder could be started: ${lastError?.message}")
    }

    private class Yuv(val y: ByteArray, val u: ByteArray, val v: ByteArray)

    private fun loadYuv(path: String): Yuv {
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        var bmp = BitmapFactory.decodeFile(path, opts) ?: throw IllegalStateException("Cannot read slide picture")
        if (bmp.width != W || bmp.height != H) {
            val s = Bitmap.createScaledBitmap(bmp, W, H, true)
            bmp.recycle(); bmp = s
        }
        val px = IntArray(W * H)
        bmp.getPixels(px, 0, W, 0, 0, W, H)
        bmp.recycle()
        val y = ByteArray(W * H)
        val u = ByteArray(W * H / 4)
        val v = ByteArray(W * H / 4)
        // BT.709, limited range
        for (j in 0 until H) {
            for (i in 0 until W) {
                val p = px[j * W + i]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                y[j * W + i] = (((47 * r + 157 * g + 16 * b + 128) shr 8) + 16).coerceIn(16, 235).toByte()
            }
        }
        var k = 0
        for (j in 0 until H step 2) {
            for (i in 0 until W step 2) {
                var r = 0; var g = 0; var b = 0
                for (dj in 0..1) for (di in 0..1) {
                    val p = px[(j + dj) * W + i + di]
                    r += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; b += p and 0xFF
                }
                r = r shr 2; g = g shr 2; b = b shr 2
                u[k] = (((-26 * r - 87 * g + 112 * b + 128) shr 8) + 128).coerceIn(16, 240).toByte()
                v[k] = (((112 * r - 102 * g - 10 * b + 128) shr 8) + 128).coerceIn(16, 240).toByte()
                k++
            }
        }
        return Yuv(y, u, v)
    }

    private fun fillImage(img: Image, yuv: Yuv) {
        val planes = img.planes
        for (p in 0..2) {
            val plane = planes[p]
            val buf = plane.buffer
            val rs = plane.rowStride
            val ps = plane.pixelStride
            val w = if (p == 0) W else W / 2
            val h = if (p == 0) H else H / 2
            val src = when (p) { 0 -> yuv.y; 1 -> yuv.u; else -> yuv.v }
            if (ps == 1 && rs == w) {
                buf.position(0)
                buf.put(src, 0, w * h)
            } else if (ps == 1) {
                for (r in 0 until h) { buf.position(r * rs); buf.put(src, r * w, w) }
            } else {
                for (r in 0 until h) for (c in 0 until w) buf.put(r * rs + c * ps, src[r * w + c])
            }
        }
    }

    private fun encodeVideo(slides: List<Slide>, durationUs: Long, dst: File, progress: (Double) -> Unit) {
        val (enc, _) = newVideoEncoder()
        enc.start()
        val muxer = MediaMuxer(dst.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val sink = Sink(enc, muxer)
        val frames = maxOf(1L, (durationUs + FRAME_US - 1) / FRAME_US)
        var slideIdx = -1
        var yuv: Yuv? = null
        try {
            for (k in 0 until frames) {
                check()
                val t = k * FRAME_US
                var want = 0
                for (i in slides.indices) if (slides[i].startUs <= t) want = i
                var changed = false
                if (want != slideIdx) {
                    yuv = loadYuv(slides[want].imagePath)
                    slideIdx = want
                    changed = true
                }
                var ii: Int
                while (true) {
                    ii = enc.dequeueInputBuffer(TIMEOUT_US)
                    if (ii >= 0) break
                    check()
                    sink.drain()
                }
                if (changed) {
                    val b = Bundle()
                    b.putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                    try { enc.setParameters(b) } catch (_: Throwable) {}
                }
                val img = enc.getInputImage(ii) ?: throw IllegalStateException("Encoder gave no input image")
                fillImage(img, yuv!!)
                val size = W * H * 3 / 2
                enc.queueInputBuffer(ii, 0, size, t, 0)
                sink.drain()
                if (k % 20L == 0L) progress(k.toDouble() / frames)
            }
            while (true) {
                val ii = enc.dequeueInputBuffer(TIMEOUT_US)
                if (ii >= 0) {
                    enc.queueInputBuffer(ii, 0, 0, frames * FRAME_US, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                check()
                sink.drain()
            }
            while (!sink.eos) { check(); sink.drain() }
            progress(1.0)
        } finally {
            try { enc.stop() } catch (_: Throwable) {}
            enc.release()
            if (sink.started) { try { muxer.stop() } catch (_: Throwable) {} }
            muxer.release()
        }
    }

    // -------------------------------------------------------------------- mux
    private fun mux(video: File, audio: File, out: File) {
        val vx = MediaExtractor().apply { setDataSource(video.path) }
        val ax = MediaExtractor().apply { setDataSource(audio.path) }
        val muxer = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            vx.selectTrack(0)
            ax.selectTrack(0)
            val vt = muxer.addTrack(vx.getTrackFormat(0))
            val at = muxer.addTrack(ax.getTrackFormat(0))
            muxer.start()
            val buf = ByteBuffer.allocate(2 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()
            var vDone = false
            var aDone = false
            while (!vDone || !aDone) {
                check()
                val useV = !vDone && (aDone || vx.sampleTime <= ax.sampleTime)
                val ex = if (useV) vx else ax
                buf.clear()
                val n = ex.readSampleData(buf, 0)
                if (n < 0) {
                    if (useV) vDone = true else aDone = true
                    continue
                }
                info.offset = 0
                info.size = n
                info.presentationTimeUs = ex.sampleTime
                info.flags = if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                muxer.writeSampleData(if (useV) vt else at, buf, info)
                ex.advance()
            }
            muxer.stop()
        } finally {
            muxer.release()
            vx.release()
            ax.release()
        }
    }
}
