import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/student_biometrics.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String token({int owner = 42, String role = 'applicant', int? expiry}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
              'role': role,
              'applicantId': owner,
              'exp': expiry ??
                  DateTime.now()
                          .add(const Duration(days: 1))
                          .millisecondsSinceEpoch ~/
                      1000,
            }))).replaceAll('=', '')}.signature';

/// flutter_secure_storage 10.3.4's words for a new biometric store's first opening.
const newStoreRefusal = 'Key mismatch after algorithm change (Algorithm changed detected). '
    'Enable migrateOnAlgorithmChange=true to preserve data, or resetOnError=true to delete.';

class FakeVault extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failWrite = false;
  bool failDelete = false;
  bool cancelRead = false;
  bool dropWrite = false;
  int writes = 0;
  /// How many writes the Android plugin refuses as a new store's first opening.
  int refuseNewStore = 0;
  PlatformException? writeError;
  Completer<void>? pauseWrite;
  Completer<void>? writeStarted;
  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    writes += 1;
    if (failWrite) throw StateError('storage unavailable');
    if (refuseNewStore > 0) {
      refuseNewStore -= 1;
      throw PlatformException(code: 'Exception encountered', message: newStoreRefusal);
    }
    final error = writeError;
    if (error != null) {
      writeError = null;
      throw error;
    }
    if (value != null && !dropWrite) values[key] = value;
    writeStarted?.complete();
    await pauseWrite?.future;
  }

  @override
  Future<String?> read(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (cancelRead) throw StateError('authentication cancelled');
    return values[key];
  }

  @override
  Future<void> delete(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (failDelete) throw StateError('storage unavailable');
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const origin = 'https://student.foorsa.ma';
  late Directory directory;
  late FakeVault vault;
  StudentBiometrics service({http.Client? client, String url = origin}) =>
      StudentBiometrics(
          origin: url,
          vault: vault,
          directory: () async => directory,
          client: client ?? MockClient((_) async => http.Response('{}', 200)));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('foorsa-biometric-test');
    vault = FakeVault();
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
      'rejects expired, malformed, staff, ambassador and invalid account tokens',
      () {
    expect(StudentSession.parse('broken'), isNull);
    expect(StudentSession.parse(token(expiry: 1)), isNull);
    expect(StudentSession.parse(token(role: 'agent')), isNull);
    expect(StudentSession.parse(token(role: 'staff')), isNull);
    expect(StudentSession.parse(token(owner: 0)), isNull);
    expect(StudentSession.parse(token())?.owner, '42');
  });

  test('server rejection cannot be confused with offline or a valid session',
      () async {
    final session = StudentSession.parse(token())!;
    for (final entry in {
      200: SessionValidity.valid,
      401: SessionValidity.expired,
      403: SessionValidity.unavailable,
      500: SessionValidity.unavailable
    }.entries) {
      final store = service(client: MockClient((request) async {
        expect(request.url.toString(), '$origin/api/portal/me');
        expect(request.headers['Authorization'], 'Bearer ${session.token}');
        return http.Response('{}', entry.key);
      }));
      expect(await store.validate(session), entry.value);
      store.dispose();
    }
    final offline = service(
        client:
            MockClient((_) async => throw const SocketException('offline')));
    expect(await offline.validate(session), SessionValidity.unavailable);
    offline.dispose();
  });

  test(
      'restarts preserve opt-in and the vault session without a plaintext file copy',
      () async {
    final session = StudentSession.parse(token())!;
    final first = service();
    expect(await first.save(session), true);
    final metadata =
        await File('${directory.path}/biometric_login.json').readAsString();
    expect(metadata, isNot(contains(session.token)));
    final second = service();
    await second.initialize();
    expect(second.enabled, true);
    expect(await second.unlock(), isA<StudentSession>());
    expect((await second.unlock())!.token, session.token);
  });

  test(
      'cancelled biometric authentication never returns a session or removes opt-in',
      () async {
    final store = service();
    await store.save(StudentSession.parse(token())!);
    vault.cancelRead = true;
    await expectLater(store.unlock(), throwsStateError);
    expect(store.enabled, true);
  });

  test('a new Android store\'s first refusal is passed, so the prompt comes up',
      () async {
    final session = StudentSession.parse(token())!;
    final store = service();
    vault.refuseNewStore = 1;
    expect(await store.save(session), true);
    expect(vault.writes, 2);
    expect(store.enabled, true);
    expect((await store.unlock())!.token, session.token);
    expect(isNewAndroidStoreRefusal(PlatformException(code: 'x', message: newStoreRefusal)), true);
  });

  test('only that refusal is tried again, and only once', () async {
    final store = service();
    vault.writeError = PlatformException(
        code: 'Exception encountered', message: 'Biometric authentication error [10]: Cancelled');
    await expectLater(store.save(StudentSession.parse(token())!), throwsA(isA<PlatformException>()));
    expect(vault.writes, 1);
    expect(store.enabled, false);
    vault.refuseNewStore = 2;
    await expectLater(store.save(StudentSession.parse(token())!), throwsA(isA<PlatformException>()));
    expect(vault.writes, 3);
    expect(store.enabled, false);
    expect(vault.values, isEmpty);
    expect(isNewAndroidStoreRefusal(StateError(newStoreRefusal)), false);
  });

  test('failed secure write never advertises a saved login', () async {
    final store = service();
    vault.failWrite = true;
    await expectLater(
        store.save(StudentSession.parse(token())!), throwsStateError);
    expect(store.enabled, false);
    final restarted = service();
    await restarted.initialize();
    expect(restarted.enabled, false);
  });

  test('a silently failed write is detected before enrollment is confirmed',
      () async {
    final store = service();
    vault.dropWrite = true;
    await expectLater(
        store.save(StudentSession.parse(token())!), throwsStateError);
    expect(store.enabled, false);
  });

  test('cancelling enrollment authentication removes the unconfirmed record',
      () async {
    final store = service();
    vault.cancelRead = true;
    await expectLater(
        store.save(StudentSession.parse(token())!), throwsStateError);
    expect(store.enabled, false);
    expect(vault.values, isEmpty);
  });

  test('sign-out during enrollment cannot resurrect a saved account', () async {
    final store = service();
    vault.pauseWrite = Completer<void>();
    vault.writeStarted = Completer<void>();
    final saving = store.save(StudentSession.parse(token())!);
    await vault.writeStarted!.future;
    final forgetting = store.forget();
    vault.pauseWrite!.complete();
    expect(await saving, false);
    await forgetting;
    final restarted = service();
    await restarted.initialize();
    expect(restarted.enabled, false);
    expect(vault.values, isEmpty);
  });

  test('sign-out deletes the vault record even when metadata cannot be written',
      () async {
    var diskFailed = false;
    final store = StudentBiometrics(
        origin: origin,
        vault: vault,
        directory: () async {
          if (diskFailed) throw const FileSystemException('disk unavailable');
          return directory;
        });
    await store.save(StudentSession.parse(token())!);
    diskFailed = true;
    await expectLater(store.forget(), throwsA(isA<FileSystemException>()));
    expect(vault.values, isEmpty);
    final restarted = service();
    await restarted.initialize();
    expect(await restarted.unlock(), isNull);
  });

  test('sign-out disables restoration even if the native deletion fails',
      () async {
    final store = service();
    await store.save(StudentSession.parse(token())!);
    vault.failDelete = true;
    await expectLater(store.forget(), throwsStateError);
    final restarted = service();
    await restarted.initialize();
    expect(restarted.enabled, false);
    expect(await restarted.unlock(), isNull);
  });

  test('another origin or account cannot use a saved credential', () async {
    final store = service();
    await store.save(StudentSession.parse(token())!);
    final differentOrigin = service(url: 'https://preview.vercel.app');
    await differentOrigin.initialize();
    expect(await differentOrigin.unlock(), isNull);
    vault.values['session:$origin'] =
        jsonEncode({'origin': origin, 'owner': '7', 'token': token(owner: 7)});
    expect(await store.unlock(), isNull);
  });

  test(
      'Not now is remembered per account and can be offered again after a week',
      () async {
    final store = service();
    await store.defer('42');
    final restarted = service();
    await restarted.initialize();
    expect(restarted.shouldOffer('42'), false);
    expect(restarted.shouldOffer('7'), true);
    expect(
        restarted.shouldOffer('42',
            now: DateTime.now().add(const Duration(days: 8))),
        true);
  });

  test(
      'missing installation metadata cannot restore a surviving iOS Keychain item',
      () async {
    final store = service();
    await store.save(StudentSession.parse(token())!);
    await File('${directory.path}/biometric_login.json').delete();
    final reinstalled = service();
    await reinstalled.initialize();
    expect(await reinstalled.unlock(), isNull);
  });
}
