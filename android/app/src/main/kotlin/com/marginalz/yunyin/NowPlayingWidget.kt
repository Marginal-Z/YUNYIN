package com.marginalz.yunyin

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.view.KeyEvent
import android.widget.RemoteViews

/** 正在播放小组件（4 × 2）。 */
class NowPlayingWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        WidgetRenderer.render(context, manager, ids, R.layout.widget_now_playing, large = true)
    }
}

/** 正在播放小组件（2 × 2）。 */
class NowPlayingSmallWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        WidgetRenderer.render(context, manager, ids, R.layout.widget_now_playing_small, large = false)
    }
}

/**
 * 小组件的状态保存在 SharedPreferences 中（应用每次换歌或播放状态变化时写入），
 * 系统重建小组件时也能显示最后的内容。按钮通过 audio_service 的媒体按键接收器控制播放，
 * 与通知栏、耳机按键走同一条路径。
 */
object WidgetRenderer {
    private const val PREFS = "yunyin_widget"

    fun save(context: Context, title: String?, artist: String?, cover: String?, playing: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("title", title)
            .putString("artist", artist)
            .putString("cover", cover)
            .putBoolean("playing", playing)
            .apply()
        refreshAll(context)
    }

    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        render(context, manager, manager.getAppWidgetIds(ComponentName(context, NowPlayingWidget::class.java)), R.layout.widget_now_playing, large = true)
        render(context, manager, manager.getAppWidgetIds(ComponentName(context, NowPlayingSmallWidget::class.java)), R.layout.widget_now_playing_small, large = false)
    }

    fun render(context: Context, manager: AppWidgetManager, ids: IntArray, layout: Int, large: Boolean) {
        if (ids.isEmpty()) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val title = prefs.getString("title", null)
        val artist = prefs.getString("artist", null)
        val playing = prefs.getBoolean("playing", false)
        val cover = prefs.getString("cover", null)?.let { loadCover(context, it, if (large) 96 else 160) }

        val views = RemoteViews(context.packageName, layout)
        if (large) {
            views.setTextViewText(R.id.widget_title, title ?: context.getString(R.string.widget_idle))
            views.setTextViewText(R.id.widget_artist, artist ?: context.getString(R.string.widget_idle_sub))
            views.setOnClickPendingIntent(R.id.widget_prev, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            views.setOnClickPendingIntent(R.id.widget_next, mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT))
        }
        if (cover != null) views.setImageViewBitmap(R.id.widget_cover, cover) else views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
        views.setImageViewResource(R.id.widget_play, if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
        views.setOnClickPendingIntent(R.id.widget_play, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        // 点按其他区域打开云音。
        val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
        )
        manager.updateAppWidget(ids, views)
    }

    private fun mediaButton(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
            .setComponent(ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver"))
            .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        return PendingIntent.getBroadcast(context, keyCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** 读取封面并缩放、裁成圆角（RemoteViews 无法给图片加圆角）。 */
    private fun loadCover(context: Context, path: String, sizeDp: Int): Bitmap? {
        return try {
            val px = (sizeDp * context.resources.displayMetrics.density).toInt().coerceAtMost(480)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0) return null
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= px) sample *= 2
            val src = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
            val side = minOf(src.width, src.height)
            val out = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            val scale = px.toFloat() / side
            shader.setLocalMatrix(android.graphics.Matrix().apply {
                setScale(scale, scale)
                postTranslate(-(src.width - side) / 2f * scale, -(src.height - side) / 2f * scale)
            })
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader }
            val r = px * 0.16f
            canvas.drawRoundRect(RectF(0f, 0f, px.toFloat(), px.toFloat()), r, r, paint)
            out
        } catch (e: Exception) {
            null
        }
    }
}
