package com.marginalz.yunyin

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 桌面歌词与状态栏歌词：两个悬浮窗（需要“显示在其他应用上层”权限）。
 *
 * - 桌面歌词：当前句 + 下一句，可拖动位置（记住位置）；锁定后不接收触摸，点按穿透到下方应用。
 * - 状态栏歌词：单行小字，贴在状态栏所在的高度，避开挖孔，不接收触摸。
 *
 * 云音在前台时隐藏（应用内已有歌词），退到后台后显示。
 */
object LyricsOverlay {
    private const val PREFS = "yunyin_lyrics_overlay"

    private var desktopEnabled = false
    private var statusEnabled = false
    private var locked = false
    private var appVisible = true
    private var line = ""
    private var next = ""
    private var accent = Color.parseColor("#FF5A73")
    private var opacity = 1f
    private var statusOffset = 0f
    private var statusColor = Color.WHITE

    private var desktopView: LinearLayout? = null
    private var desktopLine: TextView? = null
    private var desktopNext: TextView? = null
    private var statusView: TextView? = null

    fun canDraw(context: Context): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    fun configure(context: Context, desktop: Boolean, status: Boolean, lock: Boolean, accentColor: Int?, alpha: Float, offset: Float, statusTextColor: Int?) {
        desktopEnabled = desktop
        statusEnabled = status
        // 颜色、不透明度、锁定或位置变化时重建悬浮窗，使用新的样式。
        val restyle = lock != locked || (accentColor != null && accentColor != accent) || alpha != opacity
        if (accentColor != null) accent = accentColor
        opacity = alpha.coerceIn(0.3f, 1f)
        locked = lock
        if (restyle) removeDesktop(context)
        if (offset != statusOffset || (statusTextColor != null && statusTextColor != statusColor)) {
            statusOffset = offset
            if (statusTextColor != null) statusColor = statusTextColor
            removeStatus(context)
        }
        refresh(context)
    }

    fun update(context: Context, current: String, upcoming: String) {
        line = current
        next = upcoming
        desktopLine?.text = line
        desktopNext?.text = next
        statusView?.text = line
        refresh(context)
    }

    fun setAppVisible(context: Context, visible: Boolean) {
        appVisible = visible
        refresh(context)
    }

    private fun refresh(context: Context) {
        val app = context.applicationContext
        val show = !appVisible && canDraw(app)
        if (show && desktopEnabled) addDesktop(app) else removeDesktop(app)
        if (show && statusEnabled && line.isNotEmpty()) addStatus(app) else removeStatus(app)
    }

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

    private fun dp(context: Context, v: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics).toInt()

    @SuppressLint("ClickableViewAccessibility")
    private fun addDesktop(context: Context) {
        if (desktopView != null) return
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(context, 18f), dp(context, 10f), dp(context, 18f), dp(context, 10f))
            // 未锁定时显示半透明底板，提示可以拖动。
            background = if (locked) null else GradientDrawable().apply {
                cornerRadius = dp(context, 18f).toFloat()
                setColor(Color.argb(90, 0, 0, 0))
            }
        }
        val current = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 21f)
            setTextColor(accent)
            paint.isFakeBoldText = true
            setShadowLayer(6f, 0f, 1f, Color.argb(200, 0, 0, 0))
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER
            text = line
        }
        val upcoming = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(Color.argb(220, 255, 255, 255))
            setShadowLayer(5f, 0f, 1f, Color.argb(200, 0, 0, 0))
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER
            text = next
        }
        root.addView(current)
        root.addView(upcoming)
        root.alpha = opacity
        val width = (context.resources.displayMetrics.widthPixels * 0.92).toInt()
        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        if (locked) flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        val params = WindowManager.LayoutParams(width, WindowManager.LayoutParams.WRAP_CONTENT, overlayType(), flags, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = prefs.getInt("y", (context.resources.displayMetrics.heightPixels * 0.62).toInt())
            // Android 12 起，穿透触摸的悬浮窗不透明度不能超过 0.8，否则下方应用收不到点按。
            if (locked) alpha = minOf(0.8f, opacity)
        }
        if (!locked) {
            var startY = 0
            var downY = 0f
            root.setOnTouchListener { v, e ->
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startY = params.y
                        downY = e.rawY
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.y = (startY + (e.rawY - downY)).toInt().coerceAtLeast(0)
                        wm.updateViewLayout(v, params)
                    }
                    MotionEvent.ACTION_UP -> prefs.edit().putInt("y", params.y).apply()
                }
                true
            }
        }
        try {
            wm.addView(root, params)
            desktopView = root
            desktopLine = current
            desktopNext = upcoming
        } catch (e: Exception) {
            desktopView = null
        }
    }

    private fun removeDesktop(context: Context) {
        val v = desktopView ?: return
        try {
            (context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
        }
        desktopView = null
        desktopLine = null
        desktopNext = null
    }

    private fun addStatus(context: Context) {
        if (statusView != null) return
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val res = context.resources
        val id = res.getIdentifier("status_bar_height", "dimen", "android")
        val barHeight = if (id > 0) res.getDimensionPixelSize(id) else dp(context, 24f)
        val screen = res.displayMetrics.widthPixels
        // 放在状态栏左半边（时间之后），挖孔居中的机型止于挖孔左侧。
        var left = (screen * 0.2).toInt()
        var right = (screen * 0.62).toInt()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val cutout = wm.currentWindowMetrics.windowInsets.displayCutout
            val rect = cutout?.boundingRects?.firstOrNull { it.top == 0 }
            if (rect != null && rect.centerX() in (screen / 4)..(screen * 3 / 4)) right = rect.left - dp(context, 8f)
            if (rect != null && rect.centerX() < screen / 4) left = maxOf(left, rect.right + dp(context, 8f))
        }
        // 用户在设置中左右调整的位置。
        val shift = (screen * statusOffset).toInt()
        left = (left + shift).coerceIn(0, screen - dp(context, 80f))
        right = (right + shift).coerceIn(left + dp(context, 80f), screen)
        val view = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(statusColor)
            setShadowLayer(4f, 0f, 1f, Color.argb(180, 0, 0, 0))
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER_VERTICAL or Gravity.START
            text = line
        }
        val params = WindowManager.LayoutParams(
            maxOf(dp(context, 80f), right - left),
            barHeight,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = left
            y = 0
            alpha = 0.8f
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        try {
            wm.addView(view, params)
            statusView = view
        } catch (e: Exception) {
            statusView = null
        }
    }

    private fun removeStatus(context: Context) {
        val v = statusView ?: return
        try {
            (context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
        }
        statusView = null
    }
}
