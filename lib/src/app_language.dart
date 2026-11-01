/// The student's language in the app's own screens: English (the default),
/// French or Arabic (the owner, 1 Nov 2026: "give to the student three choices
/// of language when he first use the app first thing, arabic, french or
/// english (the default); if he chooses either everything turns into that
/// language properly").
///
/// The portal owns the language once it runs (foorsa-reward,
/// src/portal/language.ts: `localStorage.foorsa_portal_language`, `en`, `fr`
/// or `ar`, and a cookie of the same name). The app keeps its own copy for its
/// own screens, which draw before the portal or without it: the onboarding,
/// the loading and offline screens, the quick sign-in question, the call
/// screen, the scanner, notifications.
///
/// - A first-time downloader chooses in the onboarding's first step. The
///   portal is loading behind the onboarding, so the choice is handed to it
///   ([portalLanguageScript]): written into its storage before its code runs,
///   and, on a page already open, announced with `foorsa:language`, on which
///   the portal starts again in it, unseen.
/// - The portal says its language with `FoorsaShellLanguage` when it starts
///   and when the student changes it in Profile › Settings: the app follows
///   ([ShellLanguage.portalSays]).
///
/// The words are written here by hand, one [Words] per sentence, rather than
/// through a localisation package: three languages, and the app stays light.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

enum AppLanguage {
  en,
  fr,
  ar;

  /// The portal's value for it (`StudentLanguage`).
  String get code => name;

  bool get isRtl => this == AppLanguage.ar;

  TextDirection get direction => isRtl ? TextDirection.rtl : TextDirection.ltr;

  Locale get locale => Locale(code);

  /// Each language named in itself, as the portal's chooser and Settings
  /// show it (LANGUAGE_NAMES in shared/i18n/languages.ts).
  String get nativeName => switch (this) {
        AppLanguage.en => 'English',
        AppLanguage.fr => 'Français',
        AppLanguage.ar => 'العربية',
      };

  /// A stored or sent value as a language, or null for anything else: the
  /// portal's `parseStudentLanguage`, rule for rule (the first two letters,
  /// whatever their case).
  static AppLanguage? parse(Object? value) {
    if (value is! String) return null;
    final text = value.trim().toLowerCase();
    if (text.length < 2) return null;
    final code = text.substring(0, 2);
    for (final language in AppLanguage.values) {
      if (language.code == code) return language;
    }
    return null;
  }
}

/// One thing said in the three languages.
@immutable
class Words {
  const Words(this.en, this.fr, this.ar);
  final String en, fr, ar;

  String of(AppLanguage language) => switch (language) {
        AppLanguage.en => en,
        AppLanguage.fr => fr,
        AppLanguage.ar => ar,
      };
}

/// The language the widgets under it speak. Without one, English.
class AppLanguageScope extends InheritedWidget {
  const AppLanguageScope(
      {super.key, required this.language, required super.child});
  final AppLanguage language;

  static AppLanguage of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguageScope>()?.language ??
      AppLanguage.en;

  @override
  bool updateShouldNotify(AppLanguageScope old) => old.language != language;
}

/// [style] for text in [language]. Arabic letters join one to the next, so
/// any spacing between letters breaks the word apart, and its marks reach
/// above and below a Latin line: no letter spacing, and a little more room
/// between lines.
TextStyle scriptStyle(TextStyle style, AppLanguage language) {
  if (language != AppLanguage.ar) return style;
  final height = style.height;
  return style.copyWith(
      letterSpacing: 0, height: height == null ? null : math.max(height, 1.3));
}

/// What the app keeps: the language, and, until the portal has said it runs
/// in it, the stamp of a choice made in the onboarding.
@immutable
class StoredLanguage {
  const StoredLanguage(this.language, {this.handOver});
  final AppLanguage language;
  final String? handOver;

  @override
  bool operator ==(Object other) =>
      other is StoredLanguage &&
      other.language == language &&
      other.handOver == handOver;

  @override
  int get hashCode => Object.hash(language, handOver);
}

/// The language beside the onboarding's record, one small file. Like the
/// app's other stores it never throws: a language must not stop the app.
class AppLanguageStore {
  AppLanguageStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _fileName = 'portal_language';
  static final _stamp = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$_fileName');

  /// The first line is the language; a second `handover <stamp>` line is a
  /// choice the portal has not confirmed yet.
  static StoredLanguage? parse(String text) {
    final lines = text.split('\n').map((line) => line.trim()).toList();
    final language = AppLanguage.parse(lines.first);
    if (language == null || lines.first.length != 2) return null;
    String? handOver;
    for (final line in lines.skip(1)) {
      if (!line.startsWith('handover ')) continue;
      final stamp = line.substring('handover '.length).trim();
      if (_stamp.hasMatch(stamp)) handOver = stamp;
    }
    return StoredLanguage(language, handOver: handOver);
  }

  static String format(StoredLanguage value) => value.handOver == null
      ? value.language.code
      : '${value.language.code}\nhandover ${value.handOver}';

  /// What was kept; null when nothing was chosen on this phone.
  Future<StoredLanguage?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return parse(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Keeps [value] for the next start; null forgets it.
  Future<void> write(StoredLanguage? value) async {
    try {
      final file = await _file();
      if (value == null) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.writeAsString(format(value), flush: true);
    } catch (_) {
      // The next start speaks English until the portal says otherwise.
    }
  }
}

/// The app's language now, for every screen of the app and for what is said
/// outside a widget (notifications, the call screen, the scanner's errors).
class ShellLanguage extends ChangeNotifier {
  ShellLanguage({AppLanguageStore? store, DateTime Function()? clock})
      : _store = store ?? AppLanguageStore(),
        _clock = clock ?? DateTime.now;

  static final ShellLanguage instance = ShellLanguage();

  final AppLanguageStore _store;
  final DateTime Function() _clock;
  AppLanguage? _chosen;
  String? _handOver;
  DateTime? _handOverAt;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();

  /// How long a page that started before the onboarding's choice may still
  /// say its old language without being believed.
  static const handOverWindow = Duration(minutes: 2);

  /// What the student chose, here or in the portal; null when nobody has.
  AppLanguage? get chosen => _chosen;

  /// What the app speaks: the choice, else English.
  AppLanguage get current => _chosen ?? AppLanguage.en;

  /// The stamp of a choice made in the onboarding that the portal has not
  /// confirmed yet ([portalLanguageScript] writes it once, by this stamp).
  String? get handOver => _handOver;

  /// Reads what was kept, once (main.dart, before the first frame; a
  /// background isolate, before it says anything). Never throws.
  Future<void> load() => _loading ??= () async {
        final stored = await _store.read();
        // A choice made while this was reading wins.
        if (stored == null || _chosen != null) return;
        _chosen = stored.language;
        _handOver = stored.handOver;
      }();

  void _save() {
    final language = _chosen;
    final value =
        language == null ? null : StoredLanguage(language, handOver: _handOver);
    _writes = _writes.then((_) => _store.write(value));
  }

  /// Finishes the writes started so far (tests, and the gate's last step).
  Future<void> flush() => _writes;

  /// The student chose in the onboarding's first step: the app speaks it at
  /// once, and the portal behind the onboarding is handed it.
  void chooseInOnboarding(AppLanguage language) {
    _loading ??= Future<void>.value();
    _chosen = language;
    _handOver = _newStamp();
    _handOverAt = _clock();
    _save();
    notifyListeners();
  }

  /// The portal said the language it runs in (`FoorsaShellLanguage`).
  /// Returns whether the app took it.
  bool portalSays(Object? value) {
    final language = AppLanguage.parse(value);
    if (language == null) return false;
    if (_handOver != null) {
      final since = _handOverAt;
      if (language != _chosen &&
          since != null &&
          _clock().difference(since) < handOverWindow) {
        // A page that loaded before the choice reached it: it starts again
        // in the choice in a moment and says so.
        return false;
      }
      _handOver = null;
      _handOverAt = null;
      _chosen = language;
      _save();
      notifyListeners();
      return true;
    }
    if (language == _chosen) return true;
    _chosen = language;
    _save();
    notifyListeners();
    return true;
  }

  @visibleForTesting
  void debugReset() {
    _chosen = null;
    _handOver = null;
    _handOverAt = null;
    _loading = null;
  }

  static String _newStamp() {
    final random = math.Random.secure();
    return base64UrlEncode(List<int>.generate(12, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}

/// The key and stamp the portal reads (language.ts: `LANGUAGE_KEY`).
const portalLanguageKey = 'foorsa_portal_language';
const portalLanguageHandOverKey = 'foorsa_shell_language_handover';

/// The script that gives the portal the app's language, run in the page only
/// on [origin], the trusted portal (trusted_portal.dart).
///
/// It writes the language only where the portal would otherwise ask (no
/// language kept yet), or once for a choice made in the onboarding
/// ([handOver]: written once per stamp, so a change the student makes later
/// in the portal's Settings is never undone by a reload). With [announce] it
/// also tells a page already running (`foorsa:language`), which starts again
/// in it.
String portalLanguageScript({
  required String origin,
  required AppLanguage language,
  String? handOver,
  bool announce = false,
}) {
  final stamp = handOver == null ? 'null' : jsonEncode(handOver);
  return '(function () {'
      'try {'
      'if (location.origin !== ${jsonEncode(origin)}) return;'
      'var key = ${jsonEncode(portalLanguageKey)};'
      'var mark = ${jsonEncode(portalLanguageHandOverKey)};'
      'var language = ${jsonEncode(language.code)};'
      'var handOver = $stamp;'
      'var kept = String(localStorage.getItem(key) || "").trim().toLowerCase();'
      'var chosen = /^(en|fr|ar)/.test(kept);'
      'if (handOver ? localStorage.getItem(mark) !== handOver : !chosen) {'
      'localStorage.setItem(key, language);'
      'if (handOver) localStorage.setItem(mark, handOver);'
      '}'
      '${announce ? 'window.dispatchEvent(new CustomEvent("foorsa:language", { detail: language }));' : ''}'
      '} catch (e) {}'
      '})();';
}

/// The script for a page about to load, or null when nobody has chosen on
/// this phone: the portal then shows its own chooser.
String? portalLanguageScriptFor(ShellLanguage shell, String origin) {
  final language = shell.chosen;
  if (language == null) return null;
  return portalLanguageScript(
      origin: origin, language: language, handOver: shell.handOver);
}
