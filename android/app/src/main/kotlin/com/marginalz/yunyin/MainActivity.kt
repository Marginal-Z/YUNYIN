package com.marginalz.yunyin

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

// 使用 audio_service 提供的 Activity，以支持后台播放与媒体通知。
class MainActivity : AudioServiceActivity() {
    companion object {
        private const val SCAN_REQUEST = 4201
    }

    private val themes = listOf("red", "blue", "teal", "orange", "graphite")
    private var pendingScan: Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/app_icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> {
                    val name = call.argument<String>("name") ?: "red"
                    if (name !in themes) {
                        result.error("bad_icon", "unknown icon $name", null)
                    } else {
                        setIcon(name)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "scanAudio" -> scanAudio(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> result.success(installApk(File(call.argument<String>("path")!!)))
                else -> result.notImplemented()
            }
        }
    }

    private val audioPermission: String
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE

    /** 扫描系统媒体库中的音乐（时长不少于 30 秒），没有权限时先请求。 */
    private fun scanAudio(result: Result) {
        if (ContextCompat.checkSelfPermission(this, audioPermission) == PackageManager.PERMISSION_GRANTED) {
            queryAudio(result)
            return
        }
        pendingScan?.error("cancelled", "新的扫描请求", null)
        pendingScan = result
        ActivityCompat.requestPermissions(this, arrayOf(audioPermission), SCAN_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != SCAN_REQUEST) return
        val result = pendingScan ?: return
        pendingScan = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            queryAudio(result)
        } else {
            result.error("denied", "permission denied", null)
        }
    }

    private fun queryAudio(result: Result) {
        Thread {
            val paths = ArrayList<String>()
            try {
                @Suppress("DEPRECATION")
                val projection = arrayOf(MediaStore.Audio.Media.DATA)
                val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} >= 30000"
                contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, selection, null, null)?.use { c ->
                    while (c.moveToNext()) c.getString(0)?.let { paths.add(it) }
                }
                runOnUiThread { result.success(paths) }
            } catch (e: Exception) {
                runOnUiThread { result.error("query", e.message, null) }
            }
        }.start()
    }

    /** 打开系统安装界面覆盖安装新版本；首次需要用户允许“安装未知应用”。 */
    private fun installApk(apk: File): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            return "permission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.update", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return "ok"
    }

    /** 启用对应主题色的桌面入口并停用其他入口；DONT_KILL_APP 保证当前界面不被关闭。 */
    private fun setIcon(name: String) {
        val pm = packageManager
        for (t in themes) {
            val component = ComponentName(this, "$packageName.Icon${t.replaceFirstChar { it.uppercase() }}")
            val state = if (t == name) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            if (pm.getComponentEnabledSetting(component) != state) {
                pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
            }
        }
    }
}
