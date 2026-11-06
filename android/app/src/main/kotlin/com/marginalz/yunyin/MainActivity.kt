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
import androidx.core.app.NotificationManagerCompat
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
        private const val NOTIFY_REQUEST = 4202
    }

    private val themes = listOf("red", "blue", "teal", "orange", "graphite")
    private var pendingScan: Result? = null
    private var pendingIcon: String? = null

    /**
     * 在应用退到后台时切换桌面图标。许多桌面（ZUI、MIUI、ColorOS 等）在应用位于前台时不会刷新
     * activity-alias 的启用状态，桌面上会一直显示旧图标；退到后台后切换，桌面回到前台时即可重新加载。
     */
    // 云音在前台时隐藏桌面歌词与状态栏歌词。
    override fun onResume() {
        super.onResume()
        LyricsOverlay.setAppVisible(this, true)
    }

    override fun onPause() {
        super.onPause()
        LyricsOverlay.setAppVisible(this, false)
    }

    override fun onStop() {
        super.onStop()
        pendingIcon?.let {
            pendingIcon = null
            setIcon(it)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/app_icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> {
                    val name = call.argument<String>("name") ?: "red"
                    if (name !in themes) {
                        result.error("bad_icon", "unknown icon $name", null)
                    } else {
                        // 记下来，退到后台时再切换（见 onStop）。
                        pendingIcon = name
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    WidgetRenderer.save(
                        this,
                        call.argument<String>("title"),
                        call.argument<String>("artist"),
                        call.argument<String>("cover"),
                        call.argument<Boolean>("playing") ?: false,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/lyrics_overlay").setMethodCallHandler { call, result ->
            when (call.method) {
                "canDraw" -> result.success(LyricsOverlay.canDraw(this))
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                "configure" -> {
                    LyricsOverlay.configure(
                        this,
                        call.argument<Boolean>("desktop") ?: false,
                        call.argument<Boolean>("status") ?: false,
                        call.argument<Boolean>("locked") ?: false,
                        call.argument<Number>("accent")?.toInt(),
                        call.argument<Number>("opacity")?.toFloat() ?: 1f,
                        call.argument<Number>("statusOffset")?.toFloat() ?: 0f,
                        call.argument<Number>("statusColor")?.toInt(),
                    )
                    result.success(null)
                }
                "update" -> {
                    LyricsOverlay.update(this, call.argument<String>("line") ?: "", call.argument<String>("next") ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/system").setMethodCallHandler { call, result ->
            when (call.method) {
                // 用户同意使用声明后申请通知权限（Android 13 起需要），用于在通知栏显示播放控制。
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_REQUEST)
                    }
                    result.success(null)
                }
                "permissionStatus" -> result.success(
                    mapOf(
                        "network" to true,
                        "background" to true,
                        "notifications" to NotificationManagerCompat.from(this).areNotificationsEnabled(),
                        "audio" to (ContextCompat.checkSelfPermission(this, audioPermission) == PackageManager.PERMISSION_GRANTED),
                        "install" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()),
                        "overlay" to LyricsOverlay.canDraw(this),
                    ),
                )
                "openAppSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/audio_fx").setMethodCallHandler { call, result ->
            when (call.method) {
                "session" -> result.success(AudioFx.session(applicationContext))
                "configure" -> result.success(
                    AudioFx.configure(
                        applicationContext,
                        call.argument<Number>("boostDb")?.toFloat() ?: 0f,
                        call.argument<Boolean>("limiter") ?: true,
                        call.argument<Number>("spatial")?.toFloat() ?: 0f,
                        call.argument<Number>("bass")?.toFloat() ?: 0f,
                    ),
                )
                "release" -> {
                    AudioFx.releaseAll()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "shareImage" -> result.success(shareImage(File(call.argument<String>("path")!!), call.argument<String>("text") ?: ""))
                "saveImage" -> result.success(saveImage(File(call.argument<String>("path")!!), call.argument<String>("name") ?: "yunyin.png"))
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

    /** 通过系统分享面板分享图片（听歌海报）。图片需位于缓存目录的 yunyin-share 中。 */
    private fun shareImage(image: File, text: String): Boolean {
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.update", image)
            val send = Intent(Intent.ACTION_SEND)
                .setType("image/png")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(Intent.EXTRA_TEXT, text)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(send, "分享听歌海报").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
        }
    }

    /** 把图片保存到系统相册的 Pictures/云音 中（Android 10 起不需要存储权限）。 */
    private fun saveImage(image: File, name: String): Boolean {
        return try {
            val values = android.content.ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/云音")
                } else {
                    @Suppress("DEPRECATION")
                    val dir = File(android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES), "云音")
                    dir.mkdirs()
                    @Suppress("DEPRECATION")
                    put(MediaStore.Images.Media.DATA, File(dir, name).absolutePath)
                }
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
            contentResolver.openOutputStream(uri)?.use { out -> image.inputStream().use { it.copyTo(out) } }
            true
        } catch (e: Exception) {
            false
        }
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
