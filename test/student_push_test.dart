import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/student_push.dart';

void main() {
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
