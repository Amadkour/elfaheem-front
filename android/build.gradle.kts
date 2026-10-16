plugins {
    id("com.google.gms.google-services") version "4.4.3" apply false
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
}

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
// Some plugins (e.g. moyasar) still compile against an old API level (33), which
// fails the AAR metadata check now that their androidx dependencies need 34+.
// Raise compileSdk for every plugin module. This block MUST stay before the
// evaluationDependsOn block below (afterEvaluate can't be added once evaluated).
subprojects {
    if (name != "app") {
        afterEvaluate {
            extensions.findByName("android")?.withGroovyBuilder {
                "compileSdkVersion"(37)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}