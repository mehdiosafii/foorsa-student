import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

import 'app_language.dart';

/// Android's fingerprint or face prompt, in the student's language. (An
/// iPhone's Face ID line is Info.plist's NSFaceIDUsageDescription, which iOS
/// shows in the phone's own language: ios/Runner/*.lproj/InfoPlist.strings.)
const biometricPromptTitle =
    Words('Sign in to Foorsa', 'Se connecter à Foorsa', 'تسجيل الدخول إلى فرصة');
const biometricPromptSubtitle = Words(
    'Use your fingerprint or face recognition',
    'Utilisez votre empreinte ou la reconnaissance faciale',
    'باستخدام بصمتك أو التعرف على الوجه');
const biometricPromptCancel =
    Words('Use password', 'Utiliser le mot de passe', 'استخدام كلمة المرور');

/// Only the server can authenticate a token. These claims are used to reject
/// expired/wrong-audience data before touching the vault or making a request.
class StudentSession {
  const StudentSession(this.token, this.owner);
  final String token;
  final String owner;

  static StudentSession? parse(String token, {DateTime? now}) {
    try {
      if (token.length > 16384) return null;
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (claims is! Map ||
          claims['role'] != 'applicant' ||
          claims['applicantId'] is! int ||
          claims['applicantId'] <= 0 ||
          claims['exp'] is! num ||
          claims['exp'] * 1000 <=
              (now ?? DateTime.now()).millisecondsSinceEpoch) {
        return null;
      }
      return StudentSession(token, claims['applicantId'].toString());
    } catch (_) {
      return null;
    }
  }
}

enum SessionValidity { valid, expired, unavailable }

/// The durable copy is device-bound and biometric-gated by the OS, not just
/// guarded by a Dart boolean. Passwords and biometric templates never enter it.
class StudentBiometrics {
  StudentBiometrics({
    required this.origin,
    FlutterSecureStorage? vault,
    LocalAuthentication? auth,
    http.Client? client,
    Future<Directory> Function()? directory,
  })  : _vault = vault ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'foorsa_student_biometrics_v1',
                accessibility: KeychainAccessibility.passcode,
                accessControlFlags: [AccessControlFlag.biometryCurrentSet],
              ),
            ),
        _auth = auth ?? LocalAuthentication(),
        _client = client ?? http.Client(),
        _directory = directory ?? getApplicationSupportDirectory;

  final String origin;
  final FlutterSecureStorage _vault;
  final LocalAuthentication _auth;
  final http.Client _client;
  final Future<Directory> Function() _directory;
  String? owner;
  String _namespace = _newNamespace();
  static String _newNamespace() {
    final random = Random.secure();
    return 'foorsa_student_biometrics_v1_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  AndroidOptions get _androidOptions => AndroidOptions.biometric(
        storageNamespace: _namespace,
        enforceBiometrics: true,
        biometricType: AndroidBiometricType.strongBiometricOnly,
        biometricPromptTitle:
            biometricPromptTitle.of(ShellLanguage.instance.current),
        biometricPromptSubtitle:
            biometricPromptSubtitle.of(ShellLanguage.instance.current),
        biometricPromptNegativeButton:
            biometricPromptCancel.of(ShellLanguage.instance.current),
        resetOnError: false,
        migrateOnAlgorithmChange: false,
      );

  Future<void> _deleteCredential() async {
    if (Platform.isAndroid) {
      // Deletion must not initialize the biometric cipher or demand the very
      // biometric that the user is falling back from. A fresh namespace on
      // enrollment also recovers from an invalidated KeyStore key.
      await const MethodChannel('foorsa/biometrics').invokeMethod<void>(
        'deleteProtectedStorage',
        {'namespace': _namespace},
      );
    } else {
      await _vault.delete(key: _key);
    }
  }

  String? _savedToken;
  Map<String, int> _declined = {};
  String label = 'Face ID or fingerprint';
  /// What the sign-in screen names: face (Face ID), touch (Touch ID) or, on
  /// Android, biometric (the strong fingerprint or face the phone has).
  String get kind => label == 'Face ID' ? 'face' : label == 'Touch ID' ? 'touch' : 'biometric';
  bool get enabled => owner != null;
  bool hasSavedSession(StudentSession session) =>
      owner == session.owner && _savedToken == session.token;

  /// Whether the saved sign-in must go before [session] is offered: always for
  /// another account; for the same student only after a new sign-in on the
  /// page ([fresh]: the password typed although Face ID was saved), which is
  /// then offered in its place. A session the app kept from an earlier launch,
  /// or the portal's renewal of one, is the saved sign-in's own. The app knows
  /// the saved token only once Face ID has read it, so judged by the token
  /// alone it read as a stranger's at every launch and was deleted.
  bool replacedBy(StudentSession session, {required bool fresh}) =>
      enabled &&
      (owner != session.owner || (fresh && _savedToken != session.token));
  String get _key => 'session:$origin';
  Future<void> _mutations = Future.value();
  int _revision = 0;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _mutations = _mutations.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}/biometric_login.json');

  Future<void> initialize() async {
    try {
      final state = jsonDecode(await (await _file()).readAsString());
      if (state['origin'] != origin) return;
      final namespace = state['namespace'];
      if (namespace is! String ||
          !RegExp(r'^foorsa_student_biometrics_v1_[a-f0-9]{32}$')
              .hasMatch(namespace)) {
        return;
      }
      _namespace = namespace;
      owner = state['owner'] as String?;
      label = state['label'] as String? ?? label;
      _declined = Map<String, int>.from(state['declined'] ?? {});
    } catch (_) {
      // Missing metadata never unlocks the Keychain, including after reinstall.
      owner = null;
    }
  }

  Future<void> _persist() async {
    final file = await _file();
    final pending = File('${file.path}.pending');
    await pending.writeAsString(
        jsonEncode({
          'origin': origin,
          'namespace': _namespace,
          'owner': owner,
          'label': label,
          'declined': _declined,
        }),
        flush: true);
    await pending.rename(file.path);
  }

  Future<bool> available() async {
    try {
      if (Platform.isAndroid &&
          await const MethodChannel('foorsa/biometrics')
                  .invokeMethod<bool>('supportsProtectedStorage') !=
              true) {
        return false;
      }
      final types = await _auth.getAvailableBiometrics();
      if (Platform.isIOS) {
        label = types.contains(BiometricType.face) ? 'Face ID' : 'Touch ID';
        return types.contains(BiometricType.face) ||
            types.contains(BiometricType.fingerprint);
      }
      label = 'fingerprint or face recognition';
      // The vault accepts Class 3 biometrics only, never camera-only face unlock.
      return types.contains(BiometricType.strong);
    } catch (_) {
      return false;
    }
  }

  bool shouldOffer(String account, {DateTime? now}) {
    final declined = _declined[account];
    return owner != account &&
        (declined == null ||
            (now ?? DateTime.now()).millisecondsSinceEpoch - declined >
                const Duration(days: 7).inMilliseconds);
  }

  Future<void> defer(String account) => _serialize(() async {
        _declined[account] = DateTime.now().millisecondsSinceEpoch;
        if (_declined.length > 20) _declined.remove(_declined.keys.first);
        await _persist();
      });

  Future<SessionValidity> validate(StudentSession session) async {
    try {
      final result = await _client.get(
        Uri.parse(origin).resolve('/api/portal/me'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      ).timeout(const Duration(seconds: 15));
      if (result.statusCode == 401) {
        return SessionValidity.expired;
      }
      if (result.statusCode != 200 || jsonDecode(result.body) is! Map) {
        return SessionValidity.unavailable;
      }
      return SessionValidity.valid;
    } catch (_) {
      return SessionValidity.unavailable;
    }
  }

  Future<bool> save(StudentSession session) {
    final revision = _revision;
    return _serialize(() async {
      if (revision != _revision) return false;
      _namespace = _newNamespace();
      final record = jsonEncode({
        'token': session.token,
        'owner': session.owner,
        'origin': origin,
      });
      try {
        await _vault.write(key: _key, value: record, aOptions: _androidOptions);
        // iOS insertion alone does not authenticate. Read back through the
        // biometric ACL before marking enabled; this also proves persistence.
        // Android authenticated the write and reuses that unlocked key here.
        if (await _vault.read(key: _key, aOptions: _androidOptions) != record) {
          throw StateError('The secure login could not be verified');
        }
        if (revision != _revision) {
          await _deleteCredential();
          return false;
        }
        owner = session.owner;
        await _persist();
        if (revision != _revision) return false;
        _savedToken = session.token;
      } catch (_) {
        owner = null;
        _savedToken = null;
        await _deleteCredential();
        rethrow;
      }
      return true;
    });
  }

  Future<StudentSession?> unlock() async {
    if (!enabled) return null;
    final value = await _vault.read(key: _key, aOptions: _androidOptions);
    if (value == null) return null;
    try {
      final record = jsonDecode(value);
      final session = StudentSession.parse(record['token'] as String);
      final valid = record['origin'] == origin &&
          session?.owner == owner &&
          record['owner'] == owner;
      if (!valid) return null;
      _savedToken = session!.token;
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> forget() {
    // Disable discovery first. A failed deletion must not offer an old account.
    owner = null;
    _savedToken = null;
    _revision++;
    return _serialize(() async {
      owner = null;
      _savedToken = null;
      try {
        await _persist();
      } finally {
        // Still remove the credential when a full disk prevents metadata writes.
        await _deleteCredential();
      }
    });
  }

  void dispose() => _client.close();
}
