# Lecture Stamper (Android)

Play a lecture next to its PDF slides, tap **Stamp** when a slide appears, save the project,
and export a small slideshow video. Companion to the desktop *Lecture Video Maker*.
Built with Flutter (no Android Studio). Video is made on the phone with Android's own encoder.

## Build the APK (no Android Studio)
1. Create a GitHub repository and upload everything in this folder (keep `.github/`).
2. Open **Actions → Build Android APK → Run workflow** (it also runs on every push).
3. When it turns green, open the run and download **LectureStamper-apk**. Unzip, install `app-release.apk`.
4. First launch: allow "All files access" so the app can see audio (WhatsApp, Recordings…) and PDFs.

The workflow runs the Python rule tests, the Arabic-text check, `flutter analyze`, `flutter test`, then builds.

## Layout
- `lib/core/` stamp rules, time parsing, grid layout, project data (pure Dart)
- `lib/services/` file scan + export bridge, settings, project storage, slide renderer
- `lib/ui/` home, file browser, player, audio bar, stamp list, settings, export
- `lib/l10n/` English/Arabic (English text is the key)
- `android_overlay/` Kotlin: file scan, MediaCodec exporter, manifest (copied in by the workflow)
- `tools/mirror/` + `test_py/` Python mirror of the rules, cross-checked with the desktop `core.py`
- `tools/check_translations.py` lists texts without Arabic

## Behaviour choices (change if you prefer)
- **Stamp style:** default is pause-then-stamp: first tap pauses and keeps that second (button turns orange with the time),
  pick the page, tap again to stamp, audio resumes. Settings switch it to one-tap stamping while playing.
- Same-second pages are drawn together (side by side / grid), first slide starts at 0:00, last one stays to the end.
- Video: 1920x1080, 2 fps, H.264 bitrate mode (Smallest 300 / Balanced 500 / Sharpest 1000 kbps), AAC 96 kbps.
  Android's encoder has no CRF mode, so size is set by bitrate; a sync frame is forced at each slide change.
- Export folder is a sub-folder of **Movies** (empty = Movies itself).
- Projects auto-save; **Save for the desktop program (.lvm)** writes a desktop-format project to Download.
