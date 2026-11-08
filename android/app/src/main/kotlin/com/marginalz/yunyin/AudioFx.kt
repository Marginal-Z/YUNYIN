package com.marginalz.yunyin

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import android.util.Log

/**
 * 系统音效链：挂在播放器专用的音频会话上（mpv 以 audiotrack-session-id 使用同一个会话）。
 *
 * - 音量增强：Android 9 起用 DynamicsProcessing，先按增强量提升输入增益，再经过限幅器（-1 dBFS），
 *   响亮的母带也不会削波破音；更早的系统用 LoudnessEnhancer（自带压缩限幅）。
 *   mpv 自己的软件音量在交给系统之前就截断了超过满刻度的采样，所以增强不能放在 mpv 中做。
 * - 空间音效：系统虚拟环绕（Virtualizer），按当前输出强制使用耳机（双耳）或外放（跨耳）模式；
 *   不指定时多数设备按“自动”处理，外放时直接不生效。播放器的均衡器另外加一条声场曲线，保证都能听出变化。
 * - 低频增强：在播放器的均衡器中完成；只有均衡器不可用时才使用系统 BassBoost（很多设备上它没有效果）。
 *
 * 个别设备不支持某种音效时跳过它，其余照常工作，并把实际生效的结果返回给 Dart。
 */
object AudioFx {
    private const val TAG = "YunYinAudioFx"

    private var session = 0
    private var dynamics: DynamicsProcessing? = null
    private var loudness: LoudnessEnhancer? = null
    private var virtualizer: Virtualizer? = null
    private var bass: BassBoost? = null

    /** 播放器使用的音频会话（第一次调用时向系统申请）。 */
    fun session(context: Context): Int {
        if (session == 0) {
            session = (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager).generateAudioSessionId()
        }
        return session
    }

    /**
     * 应用设置。[boostDb] 为音量增强（dB，0 表示关闭，但限幅器仍然保留，防止均衡器提升后削波）；
     * [spatial] 与 [bassLevel] 为 0–1 的强度。返回各项是否生效。
     */
    fun configure(context: Context, boostDb: Float, limiter: Boolean, spatial: Float, bassLevel: Float): Map<String, Any> {
        val id = session(context)
        val result = HashMap<String, Any>()
        result["session"] = id
        result["limiter"] = applyDynamics(id, boostDb, limiter)
        result["spatial"] = applyVirtualizer(context, id, spatial)
        result["bass"] = applyBass(id, bassLevel)
        return result
    }

    private fun applyDynamics(id: Int, boostDb: Float, limiter: Boolean): Boolean {
        if (!limiter && boostDb <= 0f) {
            release()
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val dp = dynamics ?: DynamicsProcessing(
                    0,
                    id,
                    DynamicsProcessing.Config.Builder(
                        DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                        2,
                        false, 0,
                        false, 0,
                        false, 0,
                        true,
                    ).build(),
                ).also { dynamics = it }
                dp.setInputGainAllChannelsTo(boostDb)
                // 1 ms 起始、80 ms 释放、10:1 的限幅器，阈值 -1 dBFS：只在峰值处压缩，平时不改变声音。
                dp.setLimiterAllChannelsTo(DynamicsProcessing.Limiter(true, true, 0, 1f, 80f, 10f, -1f, 0f))
                dp.enabled = true
                loudness?.release()
                loudness = null
                return true
            } catch (e: Throwable) {
                Log.w(TAG, "DynamicsProcessing unavailable", e)
                dynamics?.release()
                dynamics = null
            }
        }
        return try {
            val le = loudness ?: LoudnessEnhancer(id).also { loudness = it }
            le.setTargetGain((boostDb * 100).toInt())
            le.enabled = boostDb > 0f
            boostDb > 0f
        } catch (e: Throwable) {
            Log.w(TAG, "LoudnessEnhancer unavailable", e)
            loudness = null
            false
        }
    }

    /** 当前是否在用耳机（有线、USB、蓝牙）输出。 */
    private fun headphones(context: Context): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val types = mutableSetOf(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )
        if (Build.VERSION.SDK_INT >= 31) types.add(AudioDeviceInfo.TYPE_BLE_HEADSET)
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in types }
    }

    private fun applyVirtualizer(context: Context, id: Int, strength: Float): Boolean {
        if (strength <= 0f) {
            virtualizer?.release()
            virtualizer = null
            return true
        }
        return try {
            val v = virtualizer ?: Virtualizer(0, id).also { virtualizer = it }
            if (v.strengthSupported) v.setStrength((strength * 1000).toInt().coerceIn(0, 1000).toShort())
            v.enabled = true
            val mode = if (headphones(context)) Virtualizer.VIRTUALIZATION_MODE_BINAURAL else Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL
            val forced = try {
                v.forceVirtualizationMode(mode)
            } catch (e: Throwable) {
                false
            }
            Log.i(TAG, "virtualizer strength=$strength mode=$mode forced=$forced")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "Virtualizer unavailable", e)
            virtualizer = null
            false
        }
    }

    private fun applyBass(id: Int, strength: Float): Boolean {
        if (strength <= 0f) {
            bass?.release()
            bass = null
            return true
        }
        return try {
            val b = bass ?: BassBoost(0, id).also { bass = it }
            if (b.strengthSupported) b.setStrength((strength * 1000).toInt().coerceIn(0, 1000).toShort())
            b.enabled = true
            true
        } catch (e: Throwable) {
            Log.w(TAG, "BassBoost unavailable", e)
            bass = null
            false
        }
    }

    private fun release() {
        dynamics?.release()
        dynamics = null
        loudness?.release()
        loudness = null
    }

    fun releaseAll() {
        release()
        virtualizer?.release()
        virtualizer = null
        bass?.release()
        bass = null
    }
}
