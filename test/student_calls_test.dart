import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/student_calls.dart';

void main() {
  test('incoming call requires a bounded fresh signed capability', () {
    final invite = <String, dynamic>{
      'callId': 'a1111111-1111-4111-8111-111111111111',
      'token': 'x' * 128,
      'expiresAt':
          DateTime.now().add(const Duration(seconds: 40)).toIso8601String()
    };
    expect(validStudentCall(invite), isTrue);
    expect(validStudentCall({...invite, 'token': ''}), isFalse);
    expect(
        validStudentCall({
          ...invite,
          'expiresAt': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .toIso8601String()
        }),
        isFalse);
    expect(
        validStudentCall({
          ...invite,
          'expiresAt':
              DateTime.now().add(const Duration(hours: 1)).toIso8601String()
        }),
        isFalse);
  });
  test('each answering device receives its own UUID', () {
    final first = callDeviceId(), second = callDeviceId();
    expect(
        first,
        matches(RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$')));
    expect(first, isNot(second));
  });
}
