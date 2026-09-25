package com.an.anbookkeep

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.an.anbookkeep/shared_images"
        private const val CONSUME_METHOD = "consumePendingShares"
        private const val AVAILABLE_METHOD = "sharedImagesAvailable"
        private const val INSPECT_IMAGE_METHOD = "inspectImagePath"
        private const val MAX_IMAGE_COUNT = 20
        private const val MAX_IMAGE_BYTES = 25L * 1024L * 1024L
        private const val MAX_TOTAL_BYTES = 200L * 1024L * 1024L
        private const val BUFFER_SIZE = 64 * 1024
        private const val TEMPORARY_DIRECTORY = "smart_bookkeeping"
        private const val MAX_IMAGE_DIMENSION = 12_000
        private const val MAX_IMAGE_PIXELS = 40_000_000L
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingSessions = mutableListOf<Map<String, Any>>()
    private val processingFingerprints = mutableSetOf<String>()
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    CONSUME_METHOD -> result.success(consumePendingSessions())
                    INSPECT_IMAGE_METHOD -> {
                        val path = call.argument<String>("path")
                        result.success(inspectImagePath(path))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        receiveSharedImages(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveSharedImages(intent)
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdownNow()
        super.onDestroy()
    }

    private fun receiveSharedImages(intent: Intent?) {
        if (intent == null ||
            (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE)
        ) {
            return
        }
        val declaredType = intent.type
        if (declaredType == null || !declaredType.startsWith("image/")) return

        val uris = extractUris(intent)
        val fingerprint = buildString {
            append(intent.action)
            append('|')
            append(uris.joinToString("|"))
        }
        synchronized(processingFingerprints) {
            if (!processingFingerprints.add(fingerprint)) return
        }

        worker.execute {
            val payload = copySharedImages(uris)
            synchronized(processingFingerprints) {
                processingFingerprints.remove(fingerprint)
            }
            synchronized(pendingSessions) {
                pendingSessions.add(payload)
            }
            mainHandler.post { channel?.invokeMethod(AVAILABLE_METHOD, null) }
        }
    }

    private fun consumePendingSessions(): List<Map<String, Any>> =
        synchronized(pendingSessions) {
            pendingSessions.toList().also { pendingSessions.clear() }
        }

    private fun extractUris(intent: Intent): List<Uri> {
        val values = linkedSetOf<Uri>()
        intent.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(values::add)
            }
        }
        if (intent.action == Intent.ACTION_SEND) {
            streamUri(intent)?.let(values::add)
        } else {
            streamUris(intent)?.let(values::addAll)
        }
        intent.data?.let(values::add)
        return values.toList()
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamUris(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }

    private fun copySharedImages(uris: List<Uri>): Map<String, Any> {
        val sessionId = UUID.randomUUID().toString()
        if (uris.isEmpty()) return errorPayload(sessionId, "no_images")
        if (uris.size > MAX_IMAGE_COUNT) {
            return errorPayload(sessionId, "too_many_images", rejectedCount = uris.size)
        }

        val directory = File(cacheDir, TEMPORARY_DIRECTORY).apply { mkdirs() }
        val paths = mutableListOf<String>()
        var rejectedCount = 0
        var totalBytes = 0L
        try {
            for ((index, uri) in uris.withIndex()) {
                if (uri.scheme != "content") {
                    rejectedCount++
                    continue
                }
                val target = File(directory, "share_${sessionId}_$index.img")
                val copied = copyOne(uri, target, MAX_IMAGE_BYTES)
                if (copied == null || !isSupportedImage(target)) {
                    target.delete()
                    rejectedCount++
                    continue
                }
                totalBytes += copied
                if (totalBytes > MAX_TOTAL_BYTES) {
                    target.delete()
                    paths.forEach { File(it).delete() }
                    return errorPayload(sessionId, "total_too_large")
                }
                paths.add(target.absolutePath)
            }
        } catch (_: SecurityException) {
            paths.forEach { File(it).delete() }
            return errorPayload(sessionId, "permission_denied")
        } catch (_: Exception) {
            paths.forEach { File(it).delete() }
            return errorPayload(sessionId, "read_failed")
        }

        if (paths.isEmpty()) {
            return errorPayload(
                sessionId,
                "no_valid_images",
                rejectedCount = rejectedCount,
            )
        }
        return mapOf(
            "sessionId" to sessionId,
            "paths" to paths,
            "rejectedCount" to rejectedCount,
            "receivedAt" to System.currentTimeMillis(),
        )
    }

    private fun copyOne(uri: Uri, target: File, limit: Long): Long? {
        try {
            val input = contentResolver.openInputStream(uri) ?: return null
            var total = 0L
            var exceeded = false
            input.use { source ->
                FileOutputStream(target).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > limit) {
                            exceeded = true
                            break
                        }
                        output.write(buffer, 0, count)
                    }
                }
            }
            if (exceeded) {
                target.delete()
                return null
            }
            return total
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }

    private fun isSupportedImage(file: File): Boolean {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return false
        if (options.outWidth > MAX_IMAGE_DIMENSION ||
            options.outHeight > MAX_IMAGE_DIMENSION ||
            options.outWidth.toLong() * options.outHeight.toLong() > MAX_IMAGE_PIXELS
        ) {
            return false
        }
        return options.outMimeType in setOf(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/heic",
            "image/heif",
        )
    }

    private fun inspectImagePath(path: String?): Map<String, Any> {
        if (path.isNullOrBlank()) return mapOf("valid" to false)
        val file = File(path)
        if (!file.isFile || file.length() <= 0L || file.length() > MAX_IMAGE_BYTES) {
            return mapOf("valid" to false)
        }
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, options)
        val valid = options.outWidth > 0 &&
            options.outHeight > 0 &&
            options.outMimeType in setOf(
                "image/jpeg",
                "image/png",
                "image/webp",
                "image/heic",
                "image/heif",
            )
        return mapOf(
            "valid" to valid,
            "width" to options.outWidth,
            "height" to options.outHeight,
        )
    }

    private fun errorPayload(
        sessionId: String,
        errorCode: String,
        rejectedCount: Int = 0,
    ): Map<String, Any> = mapOf(
        "sessionId" to sessionId,
        "paths" to emptyList<String>(),
        "rejectedCount" to rejectedCount,
        "errorCode" to errorCode,
        "receivedAt" to System.currentTimeMillis(),
    )
}
