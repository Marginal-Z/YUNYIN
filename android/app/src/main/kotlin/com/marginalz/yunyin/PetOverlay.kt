package com.marginalz.yunyin

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/**
 * 桌宠悬浮窗（需要“显示在其他应用上层”权限）：在单独的 Flutter 引擎中画桌宠（入口 petOverlayMain），
 * 触摸在这里处理：点按 → 通知主程序开始 / 停止说话；长按 → 打开云音；拖动 → 移动位置（记住位置）。
 *
 * 云音在前台时收起（应用内有自己的助手界面），退到后台后显示。桌宠的状态（表情、气泡文字）由主程序推送，
 * 这里缓存最近一次的状态，桌宠引擎启动后取走。
 */
object PetOverlay {
    private const val PREFS = "yunyin_pet_overlay"

    /** 主程序的通道（MainActivity 设置）：点按时调用 "tap"。 */
    var mainChannel: MethodChannel? = null

    private var enabled = false
    private var appVisible = true
    private var engine: FlutterEngine? = null
    private var petChannel: MethodChannel? = null
    private var container: FrameLayout? = null
    private var flutterView: FlutterView? = null
    private var params: WindowManager.LayoutParams? = null
    private var lastState: Map<String, Any?>? = null

    /** 桌宠引擎报告的窗口大小（像素）。 */
    private var widthPx = 0
    private var heightPx = 0

    fun configure(context: Context, on: Boolean) {
        enabled = on
        if (!on) destroy(context.applicationContext) else refresh(context)
    }

    fun update(context: Context, state: Map<String, Any?>) {
        lastState = state
        petChannel?.invokeMethod("state", state)
        if (enabled) refresh(context)
    }

    fun setAppVisible(context: Context, visible: Boolean) {
        appVisible = visible
        refresh(context)
    }

    private fun refresh(context: Context) {
        val app = context.applicationContext
        val show = enabled && !appVisible && LyricsOverlay.canDraw(app)
        if (show) add(app) else remove(app)
    }

    private fun dp(context: Context, v: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics).toInt()

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

    /** 桌宠引擎：只运行 petOverlayMain，不注册插件（只需要画图与一条通道）。 */
    private fun ensureEngine(app: Context): FlutterEngine {
        engine?.let { return it }
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val e = FlutterEngine(app, null, false)
        val channel = MethodChannel(e.dartExecutor.binaryMessenger, "yunyin/pet_view")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> result.success(lastState)
                "size" -> {
                    val w = call.argument<Double>("w") ?: 0.0
                    val h = call.argument<Double>("h") ?: 0.0
                    resize(app, dp(app, w.toFloat()), dp(app, h.toFloat()))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "petOverlayMain"))
        engine = e
        petChannel = channel
        return e
    }

    private fun add(app: Context) {
        if (container != null) return
        val e = ensureEngine(app)
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val metrics = app.resources.displayMetrics
        if (widthPx == 0) {
            widthPx = dp(app, 170f)
            heightPx = dp(app, 170f)
        }
        // 透明的纹理视图：桌宠以外的区域透出桌面。
        val texture = FlutterTextureView(app).apply { isOpaque = false }
        val view = FlutterView(app, texture)
        view.attachToFlutterEngine(e)
        val frame = TouchFrame(app)
        frame.contentDescription = "云音桌宠"
        frame.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        // 位置按左边与底边保存：气泡出现时窗口向上加高，桌宠本身不动。
        val bottom = prefs.getInt("bottom", (metrics.heightPixels * 0.72).toInt())
        val p = WindowManager.LayoutParams(
            widthPx,
            heightPx,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = prefs.getInt("x", metrics.widthPixels - widthPx - dp(app, 8f))
            y = bottom - heightPx
        }
        try {
            wm.addView(frame, p)
            container = frame
            flutterView = view
            params = p
            e.lifecycleChannel.appIsResumed()
            lastState?.let { petChannel?.invokeMethod("state", it) }
        } catch (ex: Exception) {
            android.util.Log.w("YunYin", "pet overlay: $ex")
            view.detachFromFlutterEngine()
        }
    }

    private fun resize(app: Context, w: Int, h: Int) {
        if (w <= 0 || h <= 0 || (w == widthPx && h == heightPx)) return
        val p = params
        val v = container
        if (p != null && v != null) {
            val bottom = p.y + p.height
            p.x += (p.width - w) / 2
            p.width = w
            p.height = h
            p.y = bottom - h
            try {
                (app.getSystemService(Context.WINDOW_SERVICE) as WindowManager).updateViewLayout(v, p)
            } catch (_: Exception) {
            }
        }
        widthPx = w
        heightPx = h
    }

    private fun remove(app: Context) {
        val v = container ?: return
        try {
            (app.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
        }
        flutterView?.detachFromFlutterEngine()
        engine?.lifecycleChannel?.appIsPaused()
        container = null
        flutterView = null
        params = null
    }

    private fun destroy(app: Context) {
        remove(app)
        engine?.destroy()
        engine = null
        petChannel = null
    }

    private fun savePosition(app: Context) {
        val p = params ?: return
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putInt("x", p.x).putInt("bottom", p.y + p.height).apply()
    }

    private fun openApp(app: Context) {
        val intent = app.packageManager.getLaunchIntentForPackage(app.packageName) ?: Intent(app, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        try {
            app.startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.w("YunYin", "pet open: $e")
        }
    }

    /** 拦截所有触摸（桌宠引擎不处理触摸），区分点按、长按与拖动。 */
    @SuppressLint("ViewConstructor")
    private class TouchFrame(context: Context) : FrameLayout(context) {
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private val handler = Handler(Looper.getMainLooper())
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var lastX = 0f
        private var lastT = 0L
        private var dragging = false
        private var longPressed = false
        // 长按时只振动提示，松手后再打开云音：手指还按着时打开，这一按剩下的部分会落进云音的界面造成误触。
        private val longPress = Runnable {
            longPressed = true
            performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        }

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean = true

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(e: MotionEvent): Boolean {
            val app = context.applicationContext
            val p = params ?: return true
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    startX = p.x
                    startY = p.y
                    lastX = e.rawX
                    lastT = e.eventTime
                    dragging = false
                    longPressed = false
                    handler.postDelayed(longPress, ViewConfiguration.getLongPressTimeout().toLong())
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!dragging && !longPressed && (abs(dx) > slop || abs(dy) > slop)) {
                        dragging = true
                        handler.removeCallbacks(longPress)
                    }
                    if (dragging) {
                        val dt = (e.eventTime - lastT).coerceAtLeast(1)
                        val vx = (e.rawX - lastX) / dt * 1000f / resources.displayMetrics.density
                        lastX = e.rawX
                        lastT = e.eventTime
                        p.x = (startX + dx).toInt()
                        p.y = (startY + dy).toInt()
                        try {
                            (app.getSystemService(Context.WINDOW_SERVICE) as WindowManager).updateViewLayout(this, p)
                        } catch (_: Exception) {
                        }
                        petChannel?.invokeMethod("drag", mapOf("active" to true, "vx" to vx.toDouble()))
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPress)
                    if (dragging) {
                        // 不让桌宠整个跑出屏幕。
                        val m = resources.displayMetrics
                        p.x = p.x.coerceIn(-p.width / 3, m.widthPixels - p.width * 2 / 3)
                        p.y = p.y.coerceIn(0, m.heightPixels - p.height / 2)
                        try {
                            (app.getSystemService(Context.WINDOW_SERVICE) as WindowManager).updateViewLayout(this, p)
                        } catch (_: Exception) {
                        }
                        petChannel?.invokeMethod("drag", mapOf("active" to false, "vx" to 0.0))
                        savePosition(app)
                    } else if (longPressed && e.actionMasked == MotionEvent.ACTION_UP) {
                        openApp(app)
                    } else if (!longPressed && e.actionMasked == MotionEvent.ACTION_UP) {
                        petChannel?.invokeMethod("poke", null)
                        mainChannel?.invokeMethod("tap", null)
                    }
                    dragging = false
                }
            }
            return true
        }
    }
}
