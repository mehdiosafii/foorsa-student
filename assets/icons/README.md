# Launcher artwork

The Foorsa mark has no baked-in ring. The default and dark iOS icons use the same opaque white-background artwork. The supplied tinted asset also has an opaque white base; system tinting can recolor it according to user preferences.

- `app_icon.png`: opaque white 1024px source for iOS default/dark/tinted and legacy Android icons.
- `app_icon_foreground.png`: transparent mark for Android adaptive masking.
- Android adaptive background is white in both day and night configuration. No monochrome themed layer is supplied.

Regenerate with `dart run flutter_launcher_icons`. iOS controls the rounded-square mask; Android launchers control their own shapes and may override colors with user-selected themes.
