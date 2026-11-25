package com.lecturestamper.lecture_stamper

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val channelName = "lecture_stamper/native"
    private val pool = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val cancel = AtomicBoolean(false)
    private lateinit var channel: MethodChannel

    private val audioExt = setOf("mp3", "m4a", "aac", "wav", "ogg", "oga", "opus", "amr", "flac", "3gp", "wma")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scan" -> pool.execute {
                    try {
                        val r = scanAll()
                        main.post { result.success(r) }
                    } catch (t: Throwable) {
                        main.post { result.error("scan", t.message, null) }
                    }
                }
                "export" -> {
                    val slides = (call.argument<List<Map<String, Any>>>("slides") ?: emptyList()).map {
                        VideoExporter.Slide(((it["start"] as Number).toDouble() * 1_000_000).toLong(), it["path"] as String)
                    }
                    val audio = call.argument<String>("audio") ?: ""
                    val name = call.argument<String>("name") ?: "lecture"
                    val folder = call.argument<String>("folder") ?: ""
                    val kbps = call.argument<Int>("kbps") ?: 500
                    val trimStartUs = ((call.argument<Double>("trimStart") ?: 0.0) * 1_000_000).toLong()
                    val trimEndUs = ((call.argument<Double>("trimEnd") ?: -1.0) * 1_000_000).toLong()
                    cancel.set(false)
                    pool.execute {
                        val tmp = File(cacheDir, "export_out.mp4")
                        try {
                            VideoExporter(cancel, cacheDir, kbps) { p ->
                                main.post { channel.invokeMethod("progress", p) }
                            }.export(slides, audio, tmp, trimStartUs, trimEndUs)
                            val shown = saveToMovies(tmp, name, folder)
                            main.post { result.success(shown) }
                        } catch (e: CancellationException) {
                            main.post { result.error("cancelled", "cancelled", null) }
                        } catch (t: Throwable) {
                            main.post { result.error("failed", t.message ?: t.toString(), null) }
                        } finally {
                            tmp.delete()
                        }
                    }
                }
                "cancelExport" -> { cancel.set(true); result.success(null) }
                "saveText" -> pool.execute {
                    try {
                        val shown = saveToDownloads(
                            call.argument<String>("name") ?: "project.lvm",
                            (call.argument<String>("text") ?: "").toByteArray(Charsets.UTF_8),
                        )
                        main.post { result.success(shown) }
                    } catch (t: Throwable) {
                        main.post { result.error("save", t.message, null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------ file scan
    private fun storageRoots(): List<File> {
        val roots = LinkedHashSet<File>()
        @Suppress("DEPRECATION")
        roots.add(Environment.getExternalStorageDirectory())
        getExternalFilesDirs(null)?.forEach { d ->
            val p = d?.absolutePath ?: return@forEach
            val i = p.indexOf("/Android/data")
            if (i > 0) roots.add(File(p.substring(0, i)))
        }
        return roots.toList()
    }

    private fun scanAll(): Map<String, List<Map<String, Any>>> {
        val audio = ArrayList<Map<String, Any>>()
        val pdf = ArrayList<Map<String, Any>>()
        for (root in storageRoots()) walk(root, root, audio, pdf, 0)
        return mapOf("audio" to audio, "pdf" to pdf)
    }

    private fun walk(dir: File, root: File, audio: MutableList<Map<String, Any>>, pdf: MutableList<Map<String, Any>>, depth: Int) {
        if (depth > 14) return
        val files = dir.listFiles() ?: return
        for (f in files) {
            val name = f.name
            if (f.isDirectory) {
                if (name.startsWith(".")) continue
                val rel = f.relativeTo(root).path
                if (rel == "Android/data" || rel == "Android/obb") continue
                walk(f, root, audio, pdf, depth + 1)
            } else {
                val ext = name.substringAfterLast('.', "").lowercase()
                val size = f.length()
                val entry = {
                    mapOf<String, Any>(
                        "path" to f.absolutePath, "name" to name, "folder" to dir.absolutePath,
                        "size" to size, "modified" to f.lastModified(),
                    )
                }
                if (ext == "pdf" && size > 0) pdf.add(entry())
                else if (ext in audioExt && size > 2048) audio.add(entry())
            }
        }
    }

    // ------------------------------------------------------------- saving
    private fun saveToMovies(tmp: File, name: String, folder: String): String {
        val fileName = if (name.endsWith(".mp4", true)) name else "$name.mp4"
        val sub = folder.trim().trim('/')
        val rel = if (sub.isEmpty()) "Movies" else "Movies/$sub"
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, rel)
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
                ?: throw IllegalStateException("Could not create the video file in $rel")
            contentResolver.openOutputStream(uri)!!.use { o -> tmp.inputStream().use { it.copyTo(o) } }
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
        } else {
            @Suppress("DEPRECATION")
            val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
            val dir = if (sub.isEmpty()) base else File(base, sub)
            dir.mkdirs()
            val dest = File(dir, fileName)
            tmp.copyTo(dest, overwrite = true)
            MediaScannerConnection.scanFile(this, arrayOf(dest.absolutePath), arrayOf("video/mp4"), null)
        }
        return "$rel/$fileName"
    }

    private fun saveToDownloads(fileName: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(MediaStore.Downloads.RELATIVE_PATH, "Download")
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create the file in Download")
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
        } else {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            dir.mkdirs()
            File(dir, fileName).writeBytes(bytes)
        }
        return "Download/$fileName"
    }
}
