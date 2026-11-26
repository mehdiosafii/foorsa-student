/// Where this copy of the iPhone app came from: TestFlight, the App Store, or
/// a build run from Xcode (AppDelegate.distribution(), from 1.2.44). Asked
/// once; Android, an older native side or any failure answers null, and the
/// portal then treats the app as the App Store's.
library;

import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('ma.foorsa.student/app');
Future<String?>? _asked;

Future<String?> appDistribution() {
  if (!Platform.isIOS) return Future.value(null);
  return _asked ??= _channel
      .invokeMethod<String>('distribution')
      .then<String?>((value) => value)
      .catchError((Object _) => null);
}
