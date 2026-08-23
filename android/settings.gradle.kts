pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()

            file("local.properties").inputStream().use {
                properties.load(it)
            }

            val flutterSdkPath = properties.getProperty("flutter.sdk")

            require(flutterSdkPath != null) {
                "flutter.sdk not set in local.properties"
            }

            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.0" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

gradle.rootProject {
    subprojects {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
                // Alinha TODOS os plugins ao mesmo compileSdk do app —
                // resolve o "AAR metadata" (androidx exigindo API 34+)
                compileSdkVersion(36)

                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }

            tasks.withType<JavaCompile>().configureEach {
                sourceCompatibility = "17"
                targetCompatibility = "17"
            }

            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions.jvmTarget.set(
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                )
            }
        }
    }
}

include(":app")