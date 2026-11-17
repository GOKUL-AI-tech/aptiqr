# Building AptiQR

Android and Windows need separate builds. An APK runs on Android, not Windows or iOS.

## Windows build machine

Install Flutter and Android Studio with Android SDK Command-line Tools, SDK Platform 36,
build tools, and the NDK requested by Flutter. Run `flutter doctor --android-licenses`
and review the licenses. For desktop builds, install Visual Studio with the
**Desktop development with C++** workload and its Windows SDK/CMake components.
Check the installation with `flutter doctor -v`.

This checkout was inspected with Flutter 3.44.8 and Dart 3.12.2.
The machine currently lacks Android command-line tools and Visual Studio C++ tools.

## Build and verify

From PowerShell in the project directory:

```powershell
.\scripts\build-release.ps1 -Target android
.\scripts\build-release.ps1 -Target windows
.\scripts\build-release.ps1 -Target web
# Or build all:
.\scripts\build-release.ps1 -Target all
```

The script resolves dependencies, regenerates Drift code, analyzes, runs tests,
and builds releases. It uses `env/dev.json`; pass `-Config env/production.json`
for another backend. Use only a Supabase client anon/publishable key, never a
service-role key. The script temporarily uses `build/java-tmp` to avoid the Java
loopback socket failure observed with the build environment's temporary path.

- Android output: `build/app/outputs/flutter-apk/app-release.apk`. This is a
  universal APK for Flutter's default supported Android architectures.
- Windows output: `build/windows/x64/runner/Release/`. Distribute the whole
  folder, including DLLs and `data`, not just `aptiqr.exe`. The build script
  packages it as `build/AptiQR-windows-x64.zip`; extract it before running.
- Web output: `build/web/`. Host this static folder on any web server, CDN, or
  Supabase Storage / Firebase Hosting. It runs on Chrome, Edge, Safari, and Firefox.
- Android currently uses the template debug signing key even for release builds.
  Configure your own signing key before publishing or distributing production updates.

If SQLite native-asset downloads fail with `HandshakeException`, restore HTTPS
access to the official `github.com/simolus3/sqlite3.dart` release assets. Do not
disable certificate verification. This was observed during the initial build;
the downloads, all three tests, and the Android release build succeeded on
November 5, 2026. The APK includes armeabi-v7a, arm64-v8a, and x86_64 libraries.

## iPhone and iPad

Use a Mac with Xcode, configured Apple signing, and Flutter:

```sh
flutter pub get
dart run build_runner build
flutter build ipa --release --dart-define-from-file=env/dev.json
```

The iOS source includes camera/location permission descriptions and the
`aptiqr` password-reset URL scheme. Add `aptiqr://reset-callback` to the Supabase
redirect allowlist. iOS compilation and physical-device behavior have not been
verified from this Windows machine.

## Platform specifics & behavior

- **QR Scanning**: Mobile (Android/iOS) and Web support camera QR code scanning.
  On desktop platforms (Windows/Linux) where camera stream hooks are unavailable,
  students can use the built-in **Enter code** manual entry, backed by the same
  instant server verification.
- **Offline database**: Native builds (Android, iOS, Windows, macOS, Linux) use
  Drift SQLite (`app_database.sqlite`) via native FFI. Web builds use Drift's
  IndexedDB web storage (`aptiqr_offline`) with sql.js support.
- **File & Report exports**: Excel, PDF, and QR exports use universal `XFile`
  buffers (`share_plus` / `cross_file`) that trigger standard system share
  dialogs on mobile/desktop and direct browser downloads on Web.
