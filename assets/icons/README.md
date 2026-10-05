# Launcher artwork

The Foorsa mark has no baked-in ring. The default and dark iOS icons use the same opaque white-background artwork. The supplied tinted asset also has an opaque white base; system tinting can recolor it according to user preferences.

- `app_icon.png`: unchanged opaque white 1024px master and legacy Android source.
- `app_icon_ios.png`: iOS default/dark/tinted source. The master is resized to 922px (90%) and centered on an opaque white 1024px canvas, giving the mark more space.
- `app_icon_foreground.png`: transparent mark for Android adaptive masking.
- Android adaptive background is white in both day and night configuration. No monochrome themed layer is supplied.

Regenerate the iOS source on macOS with `./scripts/generate-ios-icon.sh`, then run `dart run flutter_launcher_icons`. iOS controls the rounded-square mask; Android launchers control their own shapes and may override colors with user-selected themes.
