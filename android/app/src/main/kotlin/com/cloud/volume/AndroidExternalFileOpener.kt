package com.cloud.volume

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.Locale
import java.util.UUID

// Bridges app-private cache files to Android's system app chooser.
class AndroidExternalFileOpener(private val activity: Activity) {
    fun openWithSystem(path: String?, result: MethodChannel.Result) {
        Thread {
            try {
                val sharedFile = copyToSharedCache(sourceFile(path))
                val uri = FileProvider.getUriForFile(
                    activity,
                    "${activity.packageName}.fileprovider",
                    sharedFile,
                )
                activity.runOnUiThread {
                    try {
                        val viewIntent = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, mimeTypeFor(sharedFile.name))
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        viewIntent.clipData = ClipData.newRawUri("云卷文件", uri)
                        activity.startActivity(Intent.createChooser(viewIntent, "使用其它应用打开"))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "OPEN_FAILED",
                            "没有可打开此文件的应用：${error.message ?: "请安装支持该格式的应用"}",
                            null,
                        )
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("OPEN_FAILED", readableError(error), null)
                }
            }
        }.start()
    }

    private fun sourceFile(path: String?): File {
        val source = File(path?.trim().orEmpty())
        if (!source.isFile || !source.canRead()) {
            throw IOException("文件不存在或无法读取")
        }
        return source.canonicalFile
    }

    private fun copyToSharedCache(source: File): File {
        val directory = File(activity.cacheDir, SHARED_DIRECTORY)
        if (!directory.exists() && !directory.mkdirs()) {
            throw IOException("无法创建供其它应用读取的临时文件")
        }
        pruneExpiredSharedFiles(directory)
        val destination = File(directory, "${UUID.randomUUID()}-${safeFileName(source.name)}")
        source.copyTo(destination)
        return destination
    }

    private fun pruneExpiredSharedFiles(directory: File) {
        val deadline = System.currentTimeMillis() - SHARED_FILE_MAX_AGE_MS
        directory.listFiles()?.forEach { file ->
            if (file.lastModified() < deadline) {
                file.delete()
            }
        }
    }

    private fun mimeTypeFor(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return when (extension) {
            "md", "markdown", "mdown", "mkdn" -> "text/markdown"
            "txt", "log" -> "text/plain"
            "json" -> "application/json"
            else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
        }
    }

    private fun safeFileName(candidate: String): String {
        val trimmed = candidate.trim().ifEmpty { "file" }
        return if (trimmed.length <= MAX_SHARED_FILE_NAME_LENGTH) {
            trimmed
        } else {
            trimmed.take(MAX_SHARED_FILE_NAME_LENGTH)
        }
    }

    private fun readableError(error: Exception): String =
        error.message?.takeIf { it.isNotBlank() } ?: "文件操作失败"

    private companion object {
        const val SHARED_DIRECTORY = "external-open"
        const val MAX_SHARED_FILE_NAME_LENGTH = 120
        const val SHARED_FILE_MAX_AGE_MS = 24L * 60L * 60L * 1000L
    }
}
