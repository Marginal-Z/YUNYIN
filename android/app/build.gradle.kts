import java.util.Properties
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：本地读取 android/key.properties，CI 从环境变量读取。固定签名才能让新版本覆盖安装旧版本。
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signing(key: String, env: String): String? = keyProps.getProperty(key) ?: System.getenv(env)

// ── 本机语音的 ONNX Runtime ──────────────────────────────
// 离线语音识别（sherpa-onnx）自带 ONNX Runtime 1.28.2 的 libonnxruntime.so；Maven 上的 onnxruntime-android 只有 1.28.0，
// 它的 Java 绑定（libonnxruntime4j_jni.so）按符号版本 VERS_1.28.0 链接，sherpa 按 VERS_1.28.2 链接，两者不能共用一份库，
// 同名文件也只能打包一个。这里取官方 AAR，把其中的 libonnxruntime.so 改名为 libortmoss1280.so（同长度，只改 SONAME 与
// Java 绑定的依赖项这两处字符串），两份运行时互不影响。只打包 arm64-v8a：本机语音要求内存 6 GB 以上的手机，都是 64 位。
val mossOrt: Configuration by configurations.creating
val mossOrtDir = layout.buildDirectory.dir("mossOrt")
val prepareMossOrt by tasks.registering {
    inputs.files(mossOrt)
    outputs.dir(mossOrtDir)
    doLast {
        val out = mossOrtDir.get().asFile
        out.deleteRecursively()
        val from = "libonnxruntime.so".toByteArray()
        val to = "libortmoss1280.so".toByteArray()
        fun rename(b: ByteArray): ByteArray {
            var hits = 0
            var i = 0
            while (i <= b.size - from.size) {
                if ((from.indices).all { b[i + it] == from[it] }) {
                    to.copyInto(b, i)
                    hits++
                    i += from.size
                } else {
                    i++
                }
            }
            check(hits == 1) { "onnxruntime-android：预期替换 1 处库名，实际 $hits 处" }
            return b
        }
        ZipFile(mossOrt.singleFile).use { zip ->
            fun read(name: String) = zip.getInputStream(zip.getEntry(name) ?: error("AAR 中没有 $name")).readBytes()
            out.mkdirs()
            File(out, "classes.jar").writeBytes(read("classes.jar"))
            val dir = File(out, "jniLibs/arm64-v8a").apply { mkdirs() }
            File(dir, "libortmoss1280.so").writeBytes(rename(read("jni/arm64-v8a/libonnxruntime.so")))
            File(dir, "libonnxruntime4j_jni.so").writeBytes(rename(read("jni/arm64-v8a/libonnxruntime4j_jni.so")))
        }
    }
}
tasks.named("preBuild") { dependsOn(prepareMossOrt) }

android {
    namespace = "com.marginalz.yunyin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.marginalz.yunyin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        val store = signing("storeFile", "ANDROID_KEYSTORE_PATH")
        if (store != null) {
            create("release") {
                storeFile = file(store)
                storePassword = signing("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signing("keyAlias", "ANDROID_KEY_ALIAS") ?: "yunyin"
                keyPassword = signing("keyPassword", "ANDROID_KEY_PASSWORD") ?: storePassword
                storeType = "pkcs12"
            }
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(mossOrtDir.map { it.dir("jniLibs") })
        }
    }

    packaging {
        jniLibs {
            // 离线语音（sherpa-onnx）带有 x86 的动态库，Flutter 不支持 x86，打进通用安装包只会白占体积。
            excludes += "lib/x86/**"
            // 动态库压缩后存放：语音识别的动态库约 27 MB，压缩后安装包小一半左右（安装时解压）。
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // 没有配置发布密钥时（例如他人 fork 后本地构建）退回调试签名。
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            proguardFiles("proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 应用内更新使用 FileProvider 把安装包交给系统安装器。
    implementation("androidx.core:core:1.13.1")
    // 云音助手的本机语音（MOSS-TTS-Nano）用 ONNX Runtime 在 CPU 上推理，见 MossTts.kt 与下方的 prepareMossOrt。
    implementation(files(mossOrtDir.map { it.file("classes.jar") }).builtBy(prepareMossOrt))
    mossOrt("com.microsoft.onnxruntime:onnxruntime-android:1.28.0@aar")
}
