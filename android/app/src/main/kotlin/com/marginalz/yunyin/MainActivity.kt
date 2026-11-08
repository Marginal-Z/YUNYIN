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

    private val themes = listOf("red", "blue", "teal", "orange", "graphite", "default")
    private var pendingScan: Result? = null
    private var pendingIcon: String? = null

    // 云音在前台时隐藏桌面歌词与状态栏歌词。
    override fun onResume() {
        super.onResume()
        LyricsOverlay.setAppVisible(this, true)
        PetOverlay.setAppVisible(this, true)
        preferHighRefreshRate()
    }

    /**
     * 使用屏幕支持的最高刷新率。Flutter 不会自己请求高刷新率：三星（自适应刷新率）、小米、一加等机型上
     * 没有请求的应用被系统限制在 60Hz，而系统界面是 120Hz，切换页面与滚动明显不如系统流畅。
     * 这里选择分辨率与当前相同、刷新率最高的显示模式；省电模式下系统仍可能限制刷新率。
     */
    private fun preferHighRefreshRate() {
        try {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else @Suppress("DEPRECATION") windowManager.defaultDisplay
            if (display == null) return
            val current = display.mode
            val best = display.supportedModes
                .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
                .maxByOrNull { it.refreshRate } ?: return
            val attrs = window.attributes
            if (attrs.preferredDisplayModeId != best.modeId || attrs.preferredRefreshRate != best.refreshRate) {
                attrs.preferredDisplayModeId = best.modeId
                attrs.preferredRefreshRate = best.refreshRate
                window.attributes = attrs
            }
            maxRefreshRate = best.refreshRate
            // Android 15（One UI 7）起系统会为省电在画面变化较小时降低帧率，三星机型上滚动与动画会被限制到 60Hz。
            if (Build.VERSION.SDK_INT >= 35) window.setFrameRatePowerSavingsBalanced(false)
            voteSurfaceFrameRate(window.decorView)
        } catch (e: Throwable) {
            android.util.Log.w("YunYin", "refresh rate: $e")
        }
    }

    private var maxRefreshRate = 0f
    private val votedSurfaces = java.util.WeakHashMap<android.view.SurfaceView, Boolean>()

    /**
     * 为 Flutter 的绘制表面单独声明期望的帧率。三星的自适应刷新率主要按各个表面声明的帧率决定屏幕刷新率，
     * 只设置窗口的显示模式时，没有声明帧率的表面仍可能被按 60Hz 处理，滚动与转场动画掉到 60 帧。
     */
    private fun voteSurfaceFrameRate(view: android.view.View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || maxRefreshRate <= 0f) return
        if (view is android.view.SurfaceView) {
            fun apply() {
                val surface = view.holder.surface
                if (surface != null && surface.isValid) {
                    try {
                        surface.setFrameRate(maxRefreshRate, android.view.Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
                    } catch (e: Throwable) {
                        android.util.Log.w("YunYin", "surface frame rate: $e")
                    }
                }
            }
            apply()
            if (votedSurfaces.put(view, true) == null) {
                // 表面重建（切到后台再回来、旋转屏幕）后重新声明。
                view.holder.addCallback(object : android.view.SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: android.view.SurfaceHolder) = apply()
                    override fun surfaceChanged(holder: android.view.SurfaceHolder, format: Int, width: Int, height: Int) = apply()
                    override fun surfaceDestroyed(holder: android.view.SurfaceHolder) {}
                })
            }
        }
        if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) voteSurfaceFrameRate(view.getChildAt(i))
        }
    }

    /** 当前屏幕的刷新率与支持的刷新率（流畅度检测显示）。 */
    private fun displayInfo(): Map<String, Any> {
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else @Suppress("DEPRECATION") windowManager.defaultDisplay
        return mapOf(
            "current" to (display?.refreshRate?.toDouble() ?: 0.0),
            "modes" to (display?.supportedModes?.map { it.refreshRate.toDouble() }?.distinct()?.sorted() ?: emptyList<Double>()),
            "preferred" to window.attributes.preferredRefreshRate.toDouble(),
            "device" to "${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE}",
        )
    }

    override fun onPause() {
        super.onPause()
        LyricsOverlay.setAppVisible(this, false)
        PetOverlay.setAppVisible(this, false)
    }

    /**
     * 在应用退到后台时切换桌面图标。许多桌面（ZUI、MIUI、ColorOS 等）在应用位于前台时不会刷新
     * activity-alias 的启用状态，桌面上会一直显示旧图标；退到后台后切换，桌面回到前台时即可重新加载。
     */
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
                // 三星 Good Lock“主题公园”的图标主题按应用包名替换图标，不区分入口：使用中时切换入口看不到效果。
                "iconTheme" -> result.success(
                    try {
                        Settings.System.getString(contentResolver, "current_sec_appicon_theme_package")?.takeIf { it.isNotBlank() }
                    } catch (e: Exception) {
                        null
                    },
                )
                else -> result.notImplemented()
            }
        }
        // AI 助手：语音唤醒的前台服务、系统朗读与媒体音量。只使用 applicationContext（引擎可能比界面活得久）。
        val app = applicationContext
        val voice = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/voice")
        VoiceService.onStopRequested = { android.os.Handler(android.os.Looper.getMainLooper()).post { voice.invokeMethod("stopRequested", null) } }
        voice.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> result.success(VoiceService.start(app))
                "stopService" -> {
                    VoiceService.stop(app)
                    result.success(null)
                }
                "speak" -> {
                    VoiceService.speak(app, call.argument<String>("text") ?: "")
                    result.success(null)
                }
                "stopSpeaking" -> {
                    VoiceService.stopSpeaking()
                    result.success(null)
                }
                "volume" -> result.success(VoiceService.volume(app, call.argument<Double>("level"), call.argument<Double>("delta")))
                "headset" -> result.success(VoiceService.headset(app))
                "synthesize" -> {
                    val main = android.os.Handler(android.os.Looper.getMainLooper())
                    VoiceService.synthesize(
                        app,
                        call.argument<String>("text") ?: "",
                        call.argument<String>("path") ?: "",
                        (call.argument<Double>("rate") ?: 1.0).toFloat(),
                        call.argument<String>("lang") ?: "zh",
                        call.argument<String>("voice"),
                    ) { ok -> main.post { result.success(ok) } }
                }
                "systemVoices" -> {
                    val main = android.os.Handler(android.os.Looper.getMainLooper())
                    VoiceService.systemVoices(app) { voices -> main.post { result.success(voices) } }
                }
                else -> result.notImplemented()
            }
        }
        // 桌宠悬浮窗（见 PetOverlay）：主程序推送开关与状态，悬浮窗上的点按经由这条通道回到主程序。
        val pet = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yunyin/pet")
        PetOverlay.mainChannel = pet
        pet.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    PetOverlay.configure(app, call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }
                "state" -> {
                    @Suppress("UNCHECKED_CAST")
                    PetOverlay.update(app, (call.arguments as? Map<String, Any?>) ?: emptyMap())
                    result.success(null)
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
                        "microphone" to (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED),
                    ),
                )
                "displayInfo" -> result.success(displayInfo())
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

    /**
     * 启用对应主题色的桌面入口并停用其他入口；DONT_KILL_APP 保证当前界面不被关闭。
     *
     * 先启用新入口、再停用旧入口：此前按列表顺序逐个设置，切换时会有一瞬间所有入口都被停用，
     * 三星、MIUI 等桌面会因此移除桌面上的图标或不再刷新。Android 13 起一次提交全部变更，桌面只刷新一次。
     */
    private fun setIcon(name: String) {
        val pm = packageManager
        fun component(t: String) = ComponentName(this, "$packageName.Icon${t.replaceFirstChar { it.uppercase() }}")
        val changes = mutableListOf<Pair<ComponentName, Int>>()
        val target = component(name)
        if (pm.getComponentEnabledSetting(target) != PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
            changes.add(target to PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
        }
        for (t in themes) {
            if (t == name) continue
            val c = component(t)
            val state = pm.getComponentEnabledSetting(c)
            // 清单中默认启用的入口（IconRed）在未设置过时报告 DEFAULT，同样需要停用。
            if (state != PackageManager.COMPONENT_ENABLED_STATE_DISABLED) {
                changes.add(c to PackageManager.COMPONENT_ENABLED_STATE_DISABLED)
            }
        }
        if (changes.isEmpty()) return
        if (Build.VERSION.SDK_INT >= 33) {
            pm.setComponentEnabledSettings(
                changes.map { (c, s) -> PackageManager.ComponentEnabledSetting(c, s, PackageManager.DONT_KILL_APP) },
            )
        } else {
            for ((c, s) in changes) pm.setComponentEnabledSetting(c, s, PackageManager.DONT_KILL_APP)
        }
    }
}
