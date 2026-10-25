plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.abdirakhym.sandy"
    compileSdk = 35
    defaultConfig { applicationId = "com.abdirakhym.sandy.phone"; minSdk = 30; targetSdk = 35; versionCode = 1; versionName = "0.1.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("org.bouncycastle:bcprov-jdk18on:1.80")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation(platform("com.google.firebase:firebase-bom:33.12.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
}
