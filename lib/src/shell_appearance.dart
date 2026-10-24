/// The theme the student chose in the portal, kept for the app's next start.
///
/// The portal says it with `FoorsaShellAppearance` ('light', 'dark' or
/// 'system') when it starts and whenever the student changes it in Settings.
/// The app reads it back before its first frame, so its loading screen and
/// its offline screen open in that theme: a student who chose dark on a phone
/// set to light used to see a white loader, then the portal's navy one.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum ShellAppearance { light, dark }

class ShellAppearanceStore {
  ShellAppearanceStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  /// 'light' or 'dark'; anything else ('system', nonsense) follows the phone.
  static ShellAppearance? parse(Object? value) => switch (value) {
        'dark' => ShellAppearance.dark,
        'light' => ShellAppearance.light,
        _ => null,
      };

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}portal_appearance');

  /// What the portal said last; null when it never said, or said 'system'.
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

  /// Keeps [value] for the next start; null (the phone's theme) forgets it.
  Future<void> write(ShellAppearance? value) async {
    try {
      final file = await _file();
      if (value == null) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.writeAsString(value.name, flush: true);
    } catch (_) {
      // Next start follows the phone, as before.
    }
  }
}
