import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

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
              aOptions: AndroidOptions.biometric(
                storageNamespace: 'foorsa_student_biometrics_v1',
                enforceBiometrics: true,
                biometricType: AndroidBiometricType.strongBiometricOnly,
                biometricPromptTitle: 'Sign in to Foorsa',
                biometricPromptSubtitle:
                    'Use your fingerprint or face recognition',
                biometricPromptNegativeButton: 'Use password',
                resetOnError: false,
              ),
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
  Map<String, int> _declined = {};
  String label = 'Face ID or fingerprint';
  bool get enabled => owner != null;
  String get _key => 'session:$origin';

  Future<File> _file() async =>
      File('${(await _directory()).path}/biometric_login.json');

  Future<void> initialize() async {
    try {
      final state = jsonDecode(await (await _file()).readAsString());
      if (state['origin'] != origin) return;
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
          'owner': owner,
          'label': label,
          'declined': _declined,
        }),
        flush: true);
    await pending.rename(file.path);
  }

  Future<bool> available() async {
    try {
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

  Future<void> defer(String account) async {
    _declined[account] = DateTime.now().millisecondsSinceEpoch;
    if (_declined.length > 20) _declined.remove(_declined.keys.first);
    await _persist();
  }

  Future<SessionValidity> validate(StudentSession session) async {
    try {
      final result = await _client.get(
        Uri.parse(origin).resolve('/api/portal/me'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      ).timeout(const Duration(seconds: 15));
      if (result.statusCode == 401 || result.statusCode == 403) {
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

  Future<bool> save(StudentSession session) async {
    final record = jsonEncode({
      'token': session.token,
      'owner': session.owner,
      'origin': origin,
    });
    try {
      await _vault.write(key: _key, value: record);
      // iOS insertion alone does not authenticate. Read back through the
      // biometric ACL before marking enabled; this also proves persistence.
      // Android authenticated the write and reuses that unlocked key here.
      if (await _vault.read(key: _key) != record) {
        throw StateError('The secure login could not be verified');
      }
      owner = session.owner;
      await _persist();
    } catch (_) {
      owner = null;
      await _vault.delete(key: _key);
      rethrow;
    }
    return true;
  }

  Future<StudentSession?> unlock() async {
    if (!enabled) return null;
    final value = await _vault.read(key: _key);
    if (value == null) return null;
    try {
      final record = jsonDecode(value);
      final session = StudentSession.parse(record['token'] as String);
      return record['origin'] == origin &&
              session?.owner == owner &&
              record['owner'] == owner
          ? session
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> forget() async {
    // Disable discovery first. A failed deletion must not offer an old account.
    owner = null;
    await _persist();
    await _vault.delete(key: _key);
  }

  void dispose() => _client.close();
}
