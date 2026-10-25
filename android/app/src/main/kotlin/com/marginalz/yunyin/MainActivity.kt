package com.marginalz.yunyin

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// 使用 audio_service 提供的 Activity，以支持后台播放与媒体通知。
class MainActivity : AudioServiceActivity() {
    private val themes = listOf("red", "blue", "teal", "orange", "graphite")

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> result.success(installApk(File(call.argument<String>("path")!!)))
                else -> result.notImplemented()
            }
        }
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
