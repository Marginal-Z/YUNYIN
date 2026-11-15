package com.marginalz.yunyin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale

/**
 * 语音唤醒的前台服务（麦克风类型）：Android 11 起应用退到后台后不能再使用麦克风，除非在前台时启动了
 * 麦克风类型的前台服务。服务本身只维持一条常驻通知，录音与识别仍在 Flutter 中进行。
 * 通知上的“关闭”按钮停止语音唤醒（通知 Flutter 关闭设置）。
 */
class VoiceService : Service() {
    companion object {
        private const val TAG = "YunYinVoice"
        private const val CHANNEL = "yunyin_voice"
        private const val NOTIFY_ID = 4301
        const val ACTION_STOP = "com.marginalz.yunyin.VOICE_STOP"

        /** 用户在通知上点了“关闭”（由 MainActivity 转给 Flutter）。 */
        var onStopRequested: (() -> Unit)? = null

        fun start(context: Context): Boolean = try {
            // 没有麦克风权限时启动麦克风类型的前台服务会失败；以 startForegroundService 启动却没能进入前台，
            // 系统会让应用崩溃（“did not then call Service.startForeground()”），所以先检查权限。
            if (androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                throw SecurityException("没有麦克风权限")
            }
            val intent = Intent(context, VoiceService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
            true
        } catch (e: Throwable) {
            // Android 12 起只有应用在前台时才能启动前台服务。
            Log.w(TAG, "start failed", e)
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, VoiceService::class.java))
        }

        private var tts: TextToSpeech? = null
        private var ttsReady = false

        /** 声音是否从耳机播放（有线、蓝牙或 USB 耳机）：外放时麦克风会收到朗读声，不能用“开口打断”。 */
        fun headset(context: Context): Boolean {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                @Suppress("DEPRECATION")
                return am.isWiredHeadsetOn || am.isBluetoothA2dpOn
            }
            val headsets = mutableSetOf(
                android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET,
                android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                android.media.AudioDeviceInfo.TYPE_USB_HEADSET,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) headsets.add(android.media.AudioDeviceInfo.TYPE_BLE_HEADSET)
            return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in headsets }
        }

        /** 用系统的文字转语音朗读（第一次调用时初始化引擎）。 */
        fun speak(context: Context, text: String) {
            withTts(context) { engine ->
                engine?.language = Locale.SIMPLIFIED_CHINESE
                engine?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "yunyin")
            }
        }

        fun stopSpeaking() {
            tts?.stop()
        }

        /** 初始化期间等待引擎的调用（初始化只进行一次，不会重复创建引擎）。 */
        private val waiting = mutableListOf<(TextToSpeech?) -> Unit>()
        private var initializing = false

        /** 进行中的合成：按 utteranceId 回调（多处同时合成时互不覆盖）。 */
        private val utterances = java.util.concurrent.ConcurrentHashMap<String, (Boolean) -> Unit>()

        /** 确保系统朗读引擎已初始化，然后在主线程执行 [block]（初始化失败时传入 null）。 */
        private fun withTts(context: Context, block: (TextToSpeech?) -> Unit) {
            val engine = tts
            if (engine != null && ttsReady) {
                block(engine)
                return
            }
            waiting += block
            if (initializing) return
            initializing = true
            // 上一次初始化失败的引擎先释放，避免每次重试泄漏一个与系统语音服务的绑定。
            tts?.shutdown()
            tts = TextToSpeech(context.applicationContext) { status ->
                initializing = false
                ttsReady = status == TextToSpeech.SUCCESS
                if (ttsReady) {
                    tts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}
                        override fun onDone(utteranceId: String?) { utteranceId?.let { utterances.remove(it)?.invoke(true) } }
                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) { utteranceId?.let { utterances.remove(it)?.invoke(false) } }
                        override fun onError(utteranceId: String?, errorCode: Int) { utteranceId?.let { utterances.remove(it)?.invoke(false) } }
                    })
                } else {
                    tts?.shutdown()
                    tts = null
                }
                val list = waiting.toList()
                waiting.clear()
                list.forEach { it(if (ttsReady) tts else null) }
            }
        }

        /** 系统朗读中已安装、不需要联网的中文（大陆）声音的名称。 */
        fun systemVoices(context: Context, callback: (List<String>) -> Unit) {
            withTts(context) { engine ->
                val voices = try {
                    engine?.voices.orEmpty()
                        .filter { it.locale.language == "zh" && (it.locale.country.isEmpty() || it.locale.country == "CN") }
                        .filter { !it.isNetworkConnectionRequired && TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED !in it.features }
                        .map { it.name }
                        .sorted()
                } catch (e: Exception) {
                    Log.w(TAG, "voices: $e")
                    emptyList()
                }
                callback(voices)
            }
        }

        /** 用系统的文字转语音合成到 WAV 文件（音色系统的最后降级），完成后回调是否成功。[voice] 为空时用系统默认的中文声音。 */
        fun synthesize(context: Context, text: String, path: String, rate: Float, lang: String, voice: String?, callback: (Boolean) -> Unit) {
            // 合成结果可能经由多个回调到达（onDone / 两个 onError），只回报一次。
            val reported = java.util.concurrent.atomic.AtomicBoolean(false)
            val done: (Boolean) -> Unit = { ok -> if (reported.compareAndSet(false, true)) callback(ok) }
            fun run(engine: TextToSpeech) {
                val chosen = voice?.let { name -> engine.voices?.firstOrNull { it.name == name } }
                if (chosen != null) engine.voice = chosen else engine.language = Locale.SIMPLIFIED_CHINESE
                engine.setSpeechRate(rate)
                val id = "yunyin-${System.nanoTime()}"
                utterances[id] = done
                val r = engine.synthesizeToFile(text, null, java.io.File(path), id)
                if (r != TextToSpeech.SUCCESS) {
                    utterances.remove(id)
                    done(false)
                }
            }
            withTts(context) { engine -> if (engine != null) run(engine) else done(false) }
        }

        /** 调整媒体音量：[level] 为 0..1 的绝对音量，或 [delta] 为相对调整。 */
        fun volume(context: Context, level: Double?, delta: Double?): Double {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            val target = when {
                level != null -> (level * max).toInt()
                delta != null -> cur + Math.round(delta * max).toInt().let { if (it == 0) (if (delta > 0) 1 else -1) else it }
                else -> cur
            }.coerceIn(0, max)
            am.setStreamVolume(AudioManager.STREAM_MUSIC, target, AudioManager.FLAG_SHOW_UI)
            return target.toDouble() / max
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            onStopRequested?.invoke()
            stopSelf()
            return START_NOT_STICKY
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "语音唤醒", NotificationManager.IMPORTANCE_LOW).apply {
                description = "语音唤醒开启时的常驻通知"
                setShowBadge(false)
            })
        }
        val open = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, VoiceService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_voice)
            .setContentTitle("语音唤醒已开启")
            .setContentText("说“你好云音”控制播放、点歌或提问")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "关闭", stop).build())
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(NOTIFY_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIFY_ID, notification)
            }
        } catch (e: Throwable) {
            Log.w(TAG, "startForeground failed", e)
            stopSelf()
        }
        return START_STICKY
    }
}
