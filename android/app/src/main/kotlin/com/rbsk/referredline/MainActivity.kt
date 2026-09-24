package com.rbsk.referredline

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream

/**
 * Recovery-package file handling through Android's Storage Access Framework
 * (the user picks every location; no storage permission is used), and
 * FLAG_SECURE while recovery secrets are on screen.
 *
 * Copies run on a background thread. Nothing here logs file contents.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.rbsk.referredline/recovery_files"
    private val requestSave = 7101
    private val requestOpen = 7102
    private val maxPackageBytes = 1024L * 1024L * 1024L + 64L * 1024L

    private var pendingResult: MethodChannel.Result? = null
    private var pendingPath: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> {
                        val source = call.argument<String>("sourcePath")
                        val name = call.argument<String>("suggestedName") ?: "recovery.rbskrp"
                        if (source == null || !beginRequest(result, source)) return@setMethodCallHandler
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                        startActivityForResult(intent, requestSave)
                    }
                    "openFile" -> {
                        val destination = call.argument<String>("destinationPath")
                        if (destination == null || !beginRequest(result, destination)) return@setMethodCallHandler
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, requestOpen)
                    }
                    "setSecureScreen" -> {
                        if (call.argument<Boolean>("enabled") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun beginRequest(result: MethodChannel.Result, path: String): Boolean {
        if (pendingResult != null) {
            result.error("busy", "Another file request is in progress.", null)
            return false
        }
        pendingResult = result
        pendingPath = path
        return true
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestSave && requestCode != requestOpen) return
        val result = pendingResult ?: return
        val path = pendingPath
        pendingResult = null
        pendingPath = null

        val uri: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || path == null) {
            result.success(null)
            return
        }

        Thread {
            try {
                if (requestCode == requestSave) {
                    contentResolver.openOutputStream(uri, "wt").use { out ->
                        File(path).inputStream().use { input -> copy(input, requireNotNull(out)) }
                    }
                    mainHandler.post { result.success(uri.toString()) }
                } else {
                    contentResolver.openInputStream(uri).use { input ->
                        File(path).outputStream().use { out -> copy(requireNotNull(input), out) }
                    }
                    mainHandler.post { result.success(true) }
                }
            } catch (e: Exception) {
                if (requestCode == requestOpen) File(path).delete()
                mainHandler.post { result.error("io", "The file could not be copied.", null) }
            }
        }.start()
    }

    /** Copies with a size cap so an unexpected huge file can't fill storage. */
    private fun copy(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            total += read
            if (total > maxPackageBytes) throw IllegalStateException("File too large")
            output.write(buffer, 0, read)
        }
        output.flush()
    }
}
