import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/student_push.dart';

void main() {
  test('updates open only the fixed inbox with an opaque event id', () {
    const id = '00000000-0000-4000-8000-000000000001';
    expect(studentUpdateRoute({'type': 'student_update', 'route': '/notifications', 'eventId': id}), '/notifications?event=$id');
    expect(studentUpdateRoute({'type': 'student_update', 'route': 'https://evil.test', 'eventId': id}), isNull);
    expect(studentUpdateRoute({'type': 'student_update', 'route': '/notifications', 'eventId': '$id&route=/admin'}), isNull);
    expect(studentUpdateRoute({'type': 'student_update', 'route': '/notifications'}), isNull);
  });
  test('calendar drops missed and malformed alarms and sorts real instants', () {
    final now = DateTime.utc(2026, 10, 27, 10);
    expect(validCalendarTimes([
      {'at': '2026-10-27T12:00:00Z'}, {'at': '2026-10-27T09:00:00Z'},
      {'at': 'bad'}, {'at': '2026-10-27T11:00:00Z'}, {'at': '2030-01-01T00:00:00Z'},
    ], now), [DateTime.utc(2026, 10, 27, 11), DateTime.utc(2026, 10, 27, 12)]);
  });
  test('only student chat payloads open the chat', () {
    expect(
        isStudentChatPush({'type': 'student_chat', 'route': '/contact/chat'}),
        isTrue);
    expect(isStudentChatPush({'type': 'message', 'route': '/contact/chat'}),
        isFalse);
    expect(
        isStudentChatPush(
            {'type': 'student_chat', 'route': 'https://evil.test'}),
        isFalse);
    expect(isStudentChatPush({}), isFalse);
  });
}
