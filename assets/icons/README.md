# Launcher artwork

The Foorsa mark has no baked-in ring, disc, or rounded outer boundary. Platform launchers apply their own masks.

- `app_icon.png`: opaque white 1024px source for the default iOS/legacy Android icon.
- `app_icon_foreground.png`: transparent navy/silver mark for iOS dark appearance and Android adaptive icons.
- iOS tinted assets are desaturated by `flutter_launcher_icons`; Android themed icons use the foreground alpha mask.
- Android adaptive background uses white by default and `#101826` from `values-night/colors.xml` in dark configuration. Launcher support and user icon preferences govern appearance.

Regenerate from the repository root with `dart run flutter_launcher_icons`. Configuration is in `pubspec.yaml`. Preserve transparency in the foreground and keep the mark within the adaptive safe area. iOS always controls its rounded-square mask; Android launchers may select circles, squares, or other shapes.
