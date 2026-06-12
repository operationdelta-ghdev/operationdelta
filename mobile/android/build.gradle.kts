allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val javaCompile = project.tasks.withType<JavaCompile>().firstOrNull()
        val javaTarget = javaCompile?.targetCompatibility
        val targetEnum = when (javaTarget) {
            "1.8", "8", "JVM_1_8" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
            "11" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
            "17" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
        compilerOptions {
            jvmTarget.set(targetEnum)
        }
    }
}
