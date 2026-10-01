# TaskFlow app icon

The icon source lives here: `icon.png`, 1024×1024.

The app uses this icon for Android (adaptive icon) and for the web (favicon).
To replace it with your own office branding:

1. Prepare a 1024×1024 PNG with a transparent background.
2. Put it in place as `assets/images/icon.png`.
3. Run icon generation:

```bash
dart run flutter_launcher_icons
```

Without this step the app builds with the standard Flutter icons.

Icon requirements:
- square, 1024×1024
- important elements inside the central circle of 66% diameter — the edges are
  cut off by the Android mask at different screen shapes
- no transparency in debug builds, where it is partly covered by the banner
