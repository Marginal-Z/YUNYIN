package com.marginalz.yunyin

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OnnxTensorLike
import ai.onnxruntime.OnnxValue
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.IntBuffer
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.min
import org.json.JSONObject

/**
 * 云音助手的本机语音：MOSS-TTS-Nano（OpenMOSS，Apache-2.0）的 ONNX 模型，用 ONNX Runtime 在 CPU 上合成。
 *
 * 推理流程按官方 Android 示例（examples/android_onnx_runtime）移植：内置声音的参考音频编码 + 文字 ID →
 * prefill → 逐帧（每帧 16 个声音码，12.5 帧 / 秒）decode_step 与 local_fixed_sampled_frame → 声音解码器还原为 48 kHz 音频。
 * 分词在 Dart 端完成（lib/voice/moss/sentencepiece.dart），这里只接收文字 ID。
 *
 * 模型约 700 MB，加载后常驻内存；空闲 3 分钟后释放。所有推理在单独的后台线程上进行，可以随时取消。
 */
object MossTts {
    private const val TAG = "MossTts"
    private val worker = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "moss-tts").apply { priority = Thread.NORM_PRIORITY - 1 }
    }
    private val main = Handler(Looper.getMainLooper())
    private var engine: Engine? = null
    private var release: ScheduledFuture<*>? = null

    /** 已取消的请求（按请求编号取消，旧的取消不会误伤之后的句子）；释放模型时取消全部。 */
    private val cancelled = java.util.Collections.newSetFromMap(java.util.concurrent.ConcurrentHashMap<Int, Boolean>())
    @Volatile private var cancelBefore = 0

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "yunyin/moss").setMethodCallHandler { call, result ->
            when (call.method) {
                "synthesize" -> {
                    val dir = call.argument<String>("dir") ?: ""
                    val ids = call.argument<IntArray>("ids") ?: IntArray(0)
                    val voice = call.argument<String>("voice") ?: ""
                    val path = call.argument<String>("path") ?: ""
                    val maxFrames = call.argument<Int>("maxFrames") ?: 375
                    val seed = (call.argument<Number>("seed") ?: 1234).toLong()
                    val id = call.argument<Int>("id") ?: 0
                    val isCancelled = { id <= cancelBefore || cancelled.contains(id) }
                    worker.execute {
                        val reply = try {
                            release?.cancel(false)
                            if (isCancelled()) throw CancelledException()
                            val e = engine?.takeIf { it.root == dir } ?: run {
                                engine?.close()
                                engine = null
                                val t0 = System.currentTimeMillis()
                                Engine(File(dir)).also {
                                    engine = it
                                    Log.i(TAG, "model loaded in ${System.currentTimeMillis() - t0} ms")
                                }
                            }
                            val r = e.synthesize(ids, voice, File(path), maxFrames, seed, isCancelled)
                            if (r == null) mapOf("ok" to false, "cancelled" to true)
                            else mapOf("ok" to true, "frames" to r.frames, "elapsedMs" to r.elapsedMs, "durationMs" to r.durationMs, "peak" to r.peak.toDouble())
                        } catch (c: CancelledException) {
                            mapOf("ok" to false, "cancelled" to true)
                        } catch (t: Throwable) {
                            Log.e(TAG, "synthesize failed", t)
                            // 内存不足等错误后释放模型，下次重新加载。
                            if (t is OutOfMemoryError) {
                                engine?.close()
                                engine = null
                            }
                            mapOf("ok" to false, "error" to (t.message ?: t.javaClass.simpleName))
                        } finally {
                            cancelled.remove(id)
                            // 成功与失败都按时释放模型（约 700 MB 内存）。
                            if (engine != null) scheduleRelease()
                        }
                        main.post { result.success(reply) }
                    }
                }
                "cancel" -> {
                    call.argument<Int>("id")?.let { cancelled.add(it) }
                    result.success(null)
                }
                "release" -> {
                    // 释放时取消编号小于 before 的全部请求（Dart 传入下一个请求的编号）。
                    call.argument<Int>("before")?.let { cancelBefore = it }
                    worker.execute {
                        engine?.close()
                        engine = null
                    }
                    result.success(null)
                }
                "memory" -> {
                    val am = app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
                    result.success(
                        mapOf(
                            "total" to info.totalMem,
                            "available" to info.availMem,
                            "cores" to Runtime.getRuntime().availableProcessors(),
                            // 推理库只打包了 arm64-v8a（见 build.gradle.kts 的 prepareMossOrt）。
                            "abi" to (android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleRelease() {
        release?.cancel(false)
        release = worker.schedule({
            engine?.close()
            engine = null
            Log.i(TAG, "model released after idle")
        }, 3, TimeUnit.MINUTES)
    }

    private class CancelledException : Exception()

    class Result(val frames: Int, val elapsedMs: Long, val durationMs: Long, val peak: Float)

    private class Engine(rootDir: File) : AutoCloseable {
        val root: String = rootDir.absolutePath
        private val env = OrtEnvironment.getEnvironment()
        private val ttsDir = File(rootDir, "MOSS-TTS-Nano-100M-ONNX")
        private val codecDir = File(rootDir, "MOSS-Audio-Tokenizer-Nano-ONNX")
        private val manifest = JSONObject(File(ttsDir, "browser_poc_manifest.json").readText())
        private val ttsMeta = JSONObject(File(ttsDir, "tts_browser_onnx_meta.json").readText())
        private val codecMeta = JSONObject(File(codecDir, "codec_browser_onnx_meta.json").readText())
        private val cfg = manifest.getJSONObject("tts_config")
        private val nVq = cfg.getInt("n_vq")
        private val audioPad = cfg.getInt("audio_pad_token_id")
        private val audioStart = cfg.getInt("audio_start_token_id")
        private val audioEnd = cfg.getInt("audio_end_token_id")
        private val userSlot = cfg.optInt("audio_user_slot_token_id", 8)
        private val assistantSlot = cfg.getInt("audio_assistant_slot_token_id")
        private val codebook = cfg.getJSONArray("audio_codebook_sizes").optInt(0, 1024)
        private val templates = manifest.getJSONObject("prompt_templates")
        private val sampleRate = codecMeta.getJSONObject("codec_config").getInt("sample_rate")
        private val maxNewFrames = manifest.optJSONObject("generation_defaults")?.optInt("max_new_frames", 375) ?: 375
        private val decodeInputs = ttsMeta.getJSONObject("onnx").getJSONArray("decode_input_names").let { a -> List(a.length()) { a.getString(it) } }.drop(2)
        private val decodeOutputs = ttsMeta.getJSONObject("onnx").getJSONArray("decode_output_names").let { a -> List(a.length()) { a.getString(it) } }.drop(1)
        private val options = OrtSession.SessionOptions().apply {
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            // 4 个线程：大核数量通常为 4 个左右，再多反而被小核拖慢，也让界面保持流畅。
            setIntraOpNumThreads(min(4, Runtime.getRuntime().availableProcessors()).coerceAtLeast(1))
            setInterOpNumThreads(1)
        }
        private val files = ttsMeta.getJSONObject("files")
        private val created = ArrayList<OrtSession>()
        private val prefill: OrtSession
        private val decode: OrtSession
        private val localFrame: OrtSession
        private val codecDecode: OrtSession

        init {
            // 某个会话加载失败（内存不足、文件损坏）时关掉已经加载的，避免每次重试再泄漏几百 MB。
            try {
                prefill = session(File(ttsDir, files.getString("prefill")))
                decode = session(File(ttsDir, files.getString("decode_step")))
                localFrame = session(File(ttsDir, files.getString("local_fixed_sampled_frame")))
                codecDecode = session(File(codecDir, codecMeta.getJSONObject("files").getString("decode_full")))
            } catch (t: Throwable) {
                created.forEach { runCatching { it.close() } }
                runCatching { options.close() }
                throw t
            }
        }

        private fun session(f: File): OrtSession {
            require(f.isFile) { "缺少模型文件 ${f.name}" }
            return env.createSession(f.absolutePath, options).also { created += it }
        }

        private fun ints(key: String): IntArray = templates.getJSONArray(key).let { a -> IntArray(a.length()) { a.getInt(it) } }

        private fun voiceCodes(voice: String): List<IntArray> {
            val voices = manifest.getJSONArray("builtin_voices")
            var chosen: JSONObject? = null
            for (i in 0 until voices.length()) {
                val v = voices.getJSONObject(i)
                if (v.optString("voice") == voice) chosen = v
            }
            val codes = (chosen ?: error("没有这个声音：$voice")).getJSONArray("prompt_audio_codes")
            return List(codes.length()) { i -> codes.getJSONArray(i).let { row -> IntArray(row.length()) { row.getInt(it) } } }
        }

        fun synthesize(ids: IntArray, voice: String, out: File, maxFrames: Int, seed: Long, cancelled: () -> Boolean): Result? {
            require(ids.isNotEmpty()) { "没有文字" }
            val t0 = System.currentTimeMillis()
            val width = nVq + 1
            val rows = ArrayList<IntArray>()
            fun text(tokens: IntArray) = tokens.forEach { t -> rows += IntArray(width) { i -> if (i == 0) t else audioPad } }
            text(ints("user_prompt_prefix_token_ids") + audioStart)
            for (code in voiceCodes(voice)) {
                rows += IntArray(width) { i ->
                    when {
                        i == 0 -> userSlot
                        i - 1 < min(code.size, nVq) -> code[i - 1]
                        else -> audioPad
                    }
                }
            }
            text(intArrayOf(audioEnd) + ints("user_prompt_after_reference_token_ids") + ids + ints("assistant_prompt_prefix_token_ids") + audioStart)

            val frames = ArrayList<IntArray>()
            val flat = IntArray(rows.size * width).also { a -> rows.forEachIndexed { r, row -> row.copyInto(a, r * width) } }
            val input = OnnxTensor.createTensor(env, IntBuffer.wrap(flat), longArrayOf(1, rows.size.toLong(), width.toLong()))
            val mask = OnnxTensor.createTensor(env, IntBuffer.wrap(IntArray(rows.size) { 1 }), longArrayOf(1, rows.size.toLong()))
            var past: OrtSession.Result
            try {
                past = prefill.run(mapOf("input_ids" to input, "attention_mask" to mask))
            } finally {
                input.close()
                mask.close()
            }
            var hidden = try {
                lastHidden(past.tensor("global_hidden"))
            } catch (t: Throwable) {
                past.close()
                throw t
            }
            var pastLength = rows.size
            val seen = Array(nVq) { HashSet<Int>() }
            val random = java.util.Random(seed)
            try {
                for (step in 0 until min(maxFrames, maxNewFrames)) {
                    if (cancelled()) return null
                    val (more, frame) = sampleFrame(hidden, seen, random)
                    if (!more) break
                    frames += frame
                    val row = IntArray(width) { i -> if (i == 0) assistantSlot else audioPad }
                    for (q in 0 until nVq) {
                        row[q + 1] = frame[q]
                        seen[q].add(frame[q])
                    }
                    OnnxTensor.createTensor(env, IntBuffer.wrap(row), longArrayOf(1, 1, width.toLong())).use { input ->
                        OnnxTensor.createTensor(env, IntBuffer.wrap(intArrayOf(pastLength)), longArrayOf(1)).use { len ->
                            val feeds = linkedMapOf<String, OnnxTensorLike>("input_ids" to input, "past_valid_lengths" to len)
                            for (i in decodeInputs.indices) feeds[decodeInputs[i]] = past.tensor(decodeOutputs[i])
                            val next = decode.run(feeds)
                            val nextHidden = try {
                                lastHidden(next.tensor("global_hidden"))
                            } catch (t: Throwable) {
                                next.close()
                                throw t
                            }
                            hidden.close()
                            past.close()
                            past = next
                            hidden = nextHidden
                            pastLength++
                        }
                    }
                }
            } finally {
                hidden.close()
                past.close()
            }
            if (cancelled()) return null
            require(frames.isNotEmpty()) { "没有生成声音" }
            val pcm = decodeAudio(frames)
            val peak = finish(pcm)
            writeWav(pcm, out)
            return Result(frames.size, System.currentTimeMillis() - t0, pcm.size * 1000L / sampleRate, peak)
        }

        private fun sampleFrame(hidden: OnnxTensor, seen: Array<HashSet<Int>>, random: java.util.Random): Pair<Boolean, IntArray> {
            val mask = IntArray(nVq * codebook)
            for (q in seen.indices) for (t in seen[q]) if (t in 0 until codebook) mask[q * codebook + t] = 1
            val u = floatArrayOf(random.nextDouble().coerceIn(1e-6, 1 - 1e-6).toFloat())
            val audioU = FloatArray(nVq) { random.nextDouble().coerceIn(1e-6, 1 - 1e-6).toFloat() }
            OnnxTensor.createTensor(env, IntBuffer.wrap(mask), longArrayOf(1, nVq.toLong(), codebook.toLong())).use { m ->
                OnnxTensor.createTensor(env, FloatBuffer.wrap(u), longArrayOf(1)).use { a ->
                    OnnxTensor.createTensor(env, FloatBuffer.wrap(audioU), longArrayOf(1, nVq.toLong())).use { b ->
                        localFrame.run(mapOf("global_hidden" to hidden, "repetition_seen_mask" to m, "assistant_random_u" to a, "audio_random_u" to b)).use {
                            return (flatInts(it.tensor("should_continue").value).first() > 0) to flatInts(it.tensor("frame_token_ids").value)
                        }
                    }
                }
            }
        }

        private fun decodeAudio(frames: List<IntArray>): FloatArray {
            val codes = IntArray(frames.size * nVq)
            frames.forEachIndexed { f, frame -> for (q in 0 until nVq) codes[f * nVq + q] = frame[q] }
            OnnxTensor.createTensor(env, IntBuffer.wrap(codes), longArrayOf(1, frames.size.toLong(), nVq.toLong())).use { c ->
                OnnxTensor.createTensor(env, IntBuffer.wrap(intArrayOf(frames.size)), longArrayOf(1)).use { l ->
                    codecDecode.run(mapOf("audio_codes" to c, "audio_code_lengths" to l)).use {
                        val channels = ((it.tensor("audio").value as Array<*>)[0] as Array<*>).map { ch -> ch as FloatArray }
                        val length = min(flatInts(it.tensor("audio_lengths").value).first(), channels.minOf { ch -> ch.size })
                        // 双声道取平均（两个声道几乎相同）。
                        return FloatArray(length) { i -> channels.sumOf { ch -> ch[i].toDouble() }.toFloat() / channels.size }
                    }
                }
            }
        }

        /** 峰值超过 -0.3 dBFS 时整体压低（不削波），首尾各 8 毫秒淡入淡出（避免“咔哒”声）。返回处理前的峰值。 */
        private fun finish(pcm: FloatArray): Float {
            var peak = 0f
            for (s in pcm) peak = maxOf(peak, abs(s))
            val gain = if (peak > 0.966f) 0.966f / peak else 1f
            val fade = min(sampleRate * 8 / 1000, pcm.size / 2)
            for (i in pcm.indices) {
                var g = gain
                if (i < fade) g *= i.toFloat() / fade
                if (i >= pcm.size - fade) g *= (pcm.size - 1 - i).toFloat() / fade
                pcm[i] *= g
            }
            return peak
        }

        private fun writeWav(pcm: FloatArray, out: File) {
            out.parentFile?.mkdirs()
            val data = pcm.size * 2
            val b = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
            b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
            b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1).putInt(sampleRate).putInt(sampleRate * 2).putShort(2).putShort(16)
            b.put("data".toByteArray()).putInt(data)
            for (s in pcm) b.putShort(Math.round(s.coerceIn(-1f, 1f) * 32767f).toShort())
            FileOutputStream(out).use { it.write(b.array()) }
        }

        override fun close() {
            codecDecode.close()
            localFrame.close()
            decode.close()
            prefill.close()
            options.close()
        }

        private fun lastHidden(t: OnnxTensor): OnnxTensor {
            val v = t.value as Array<*>
            val h = when (t.info.shape.size) {
                2 -> v[0] as FloatArray
                3 -> (v[0] as Array<*>).let { batch -> batch[batch.size - 1] as FloatArray }
                else -> error("global_hidden 的维度不对：${t.info.shape.size}")
            }
            return OnnxTensor.createTensor(env, FloatBuffer.wrap(h.copyOf()), longArrayOf(1, h.size.toLong()))
        }

        private fun OrtSession.Result.tensor(name: String): OnnxTensor =
            (get(name).orElseThrow { IllegalStateException("缺少输出 $name") } as OnnxValue) as OnnxTensor

        private fun flatInts(raw: Any?): IntArray {
            val out = ArrayList<Int>()
            fun add(v: Any?) {
                when (v) {
                    is Int -> out += v
                    is Long -> out += v.toInt()
                    is IntArray -> v.forEach { out += it }
                    is LongArray -> v.forEach { out += it.toInt() }
                    is Array<*> -> v.forEach { add(it) }
                    null -> Unit
                    else -> error("不支持的整数输出 ${v.javaClass}")
                }
            }
            add(raw)
            return out.toIntArray()
        }
    }
}
