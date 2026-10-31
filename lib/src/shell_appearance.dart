/// The theme the student chose in the portal, kept for the app's next start.
///
/// The portal says it with `FoorsaShellAppearance` ('light', 'dark' or
/// 'system') when it starts and whenever the student changes it in Settings.
/// The app reads it back before its first frame, so its loading screen and
/// its offline screen open in that theme: a student who chose dark on a phone
/// set to light used to see a white loader, then the portal's navy one.
///
/// A student who never chose gets light (the owner, 31 Oct 2026: "light mode
/// is the one in the app by default and they can change it later"), as the
/// portal does; only one who picked System follows the phone.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum ShellAppearance { light, dark, system }

class ShellAppearanceStore {
  ShellAppearanceStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  /// 'light', 'dark' or 'system'; anything else is no choice at all.
  static ShellAppearance? parse(Object? value) => switch (value) {
        'dark' => ShellAppearance.dark,
        'light' => ShellAppearance.light,
        'system' => ShellAppearance.system,
        _ => null,
      };

  /// Whether the app's own screens are dark: the student's choice, the
  /// phone's for System, and light for a student who never chose.
  static bool isDark(ShellAppearance? appearance, {required bool phoneIsDark}) =>
      switch (appearance) {
        ShellAppearance.dark => true,
        ShellAppearance.system => phoneIsDark,
        ShellAppearance.light || null => false,
      };

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}portal_appearance');

  /// What the portal said last; null when it never said.
  /// Never throws: a theme must not stop the app from starting.
  Future<ShellAppearance?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return parse((await file.readAsString()).trim());
    } catch (_) {
      return null;
    }
  }

  /// Keeps [value] for the next start; null forgets it.
  Future<void> write(ShellAppearance? value) async {
    try {
      final file = await _file();
      if (value == null) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.writeAsString(value.name, flush: true);
    } catch (_) {
      // Next start opens light, the default.
    }
  }
}
