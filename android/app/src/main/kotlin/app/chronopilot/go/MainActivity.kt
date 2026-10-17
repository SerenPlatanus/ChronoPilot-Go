package app.chronopilot.go

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var pendingWallpaper: MethodChannel.Result? = null
    private val requestWallpaper = 6071
    private val wallpaperDirectory get() = File(filesDir, "wallpapers")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.chronopilot.go/wallpaper")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickWallpaper" -> {
                        if (pendingWallpaper != null) {
                            result.error("busy", "正在选择壁纸", null)
                        } else {
                            pendingWallpaper = result
                            try {
                                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "image/*"
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }, requestWallpaper)
                            } catch (_: Exception) {
                                pendingWallpaper = null
                                result.error("picker", "无法打开图片选择器", null)
                            }
                        }
                    }
                    "deleteWallpaper" -> {
                        try {
                            val file = call.argument<String>("path")?.let { File(it) }
                            val owned = file != null && file.canonicalFile.parentFile == wallpaperDirectory.canonicalFile
                            result.success(owned && (!file!!.exists() || file.delete()))
                        } catch (_: Exception) {
                            result.error("file", "无法清理旧壁纸", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestWallpaper) return
        val result = pendingWallpaper ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingWallpaper = null
            result.success(null)
            return
        }
        // Never decode a full camera photo or copy provider bytes on the UI thread.
        Thread {
            var temporary: File? = null
            var output: File? = null
            try {
                wallpaperDirectory.mkdirs()
                val source = File.createTempFile("import-", ".tmp", cacheDir)
                temporary = source
                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "无法读取图片" }
                    source.outputStream().use { target ->
                        val buffer = ByteArray(8192)
                        var total = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            require(total <= 20L * 1024 * 1024) { "请选择不超过 20 MB 的图片" }
                            target.write(buffer, 0, count)
                        }
                    }
                }
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(source.absolutePath, bounds)
                require(bounds.outWidth > 0 && bounds.outHeight > 0) { "图片格式不可用" }
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2560) sample *= 2
                val bitmap = requireNotNull(BitmapFactory.decodeFile(source.absolutePath,
                    BitmapFactory.Options().apply { inSampleSize = sample })) { "无法读取图片" }
                val orientation = try { ExifInterface(source.absolutePath)
                    .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
                val matrix = Matrix().apply {
                    when (orientation) {
                        ExifInterface.ORIENTATION_ROTATE_90 -> postRotate(90f)
                        ExifInterface.ORIENTATION_ROTATE_180 -> postRotate(180f)
                        ExifInterface.ORIENTATION_ROTATE_270 -> postRotate(270f)
                        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> postScale(-1f, 1f)
                        ExifInterface.ORIENTATION_FLIP_VERTICAL -> postScale(1f, -1f)
                        ExifInterface.ORIENTATION_TRANSPOSE -> { postRotate(90f); postScale(-1f, 1f) }
                        ExifInterface.ORIENTATION_TRANSVERSE -> { postRotate(270f); postScale(-1f, 1f) }
                    }
                }
                val oriented = if (matrix.isIdentity) bitmap else Bitmap.createBitmap(bitmap, 0, 0,
                    bitmap.width, bitmap.height, matrix, true)
                output = File(wallpaperDirectory, "wallpaper-${UUID.randomUUID()}.jpg")
                output.outputStream().use { require(oriented.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
                if (oriented !== bitmap) oriented.recycle()
                bitmap.recycle()
                val path = output.absolutePath
                runOnUiThread { pendingWallpaper = null; result.success(path) }
            } catch (e: Exception) {
                output?.delete()
                val message = if (e is IllegalArgumentException) e.message ?: "图片格式不可用" else "无法读取图片，请重新选择"
                runOnUiThread { pendingWallpaper = null; result.error("image", message, null) }
            } catch (_: OutOfMemoryError) {
                output?.delete()
                runOnUiThread { pendingWallpaper = null; result.error("image", "图片过大，请选择较小的图片", null) }
            } finally { temporary?.delete() }
        }.start()
    }
}
