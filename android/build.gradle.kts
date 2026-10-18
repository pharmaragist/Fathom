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

// Inject compileSdk fallback when Android plugins apply
subprojects {
    plugins.withId("com.android.application") {
        (project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension)?.apply {
            compileSdkVersion(34)
        }
    }
    plugins.withId("com.android.library") {
        (project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension)?.apply {
            compileSdkVersion(34)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}