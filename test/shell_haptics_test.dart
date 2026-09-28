import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/shell_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('foorsa/haptics');

  late List<String> native;
  late List<String> system;

  /// [answer] is what the Android side returns; null stands for an app
  /// built before the channel existed.
  void stage({bool? answer = true}) {
    native = <String>[];
    system = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      native.add('${call.method}:${call.arguments}');
      if (answer == null) throw MissingPluginException();
      return answer;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        system.add('${call.arguments}');
      }
      return null;
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('reads a texture name and nothing else', () {
    expect(ShellHaptics.touchFrom('crack'), 'crack');
    expect(ShellHaptics.touchFrom(8), 'select');
    expect(ShellHaptics.touchFrom(<int>[8, 30]), 'select');
    expect(ShellHaptics.touchFrom(null), 'select');
    expect(ShellHaptics.touchFrom('shake'), 'select');
  });

  test('portal buttons keep the light tick they have always had', () async {
    stage();
    await ShellHaptics(android: true).play(8);
    expect(native, isEmpty);
    expect(system, <String>['HapticFeedbackType.lightImpact']);
  });

  test('on Android the reveal plays its textures natively', () async {
    stage();
    final haptics = ShellHaptics(android: true);
    for (final touch in ShellHaptics.textures) {
      await haptics.play(touch);
    }
    expect(native, ShellHaptics.textures.map((touch) => 'play:$touch'));
    expect(system, isEmpty);
  });

  test('a phone that cannot play one falls back to system impacts', () async {
    stage(answer: false);
    await ShellHaptics(android: true).play('land');
    expect(native, <String>['play:land']);
    expect(system, <String>['HapticFeedbackType.mediumImpact']);
  });

  test('an app without the channel stops asking for it', () async {
    stage(answer: null);
    final haptics = ShellHaptics(android: true);
    await haptics.play('grain');
    await haptics.play('grain');
    expect(native, <String>['play:grain']);
    expect(system, <String>[
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
    ]);
  });

  test('on iOS the seal cracks as a heavy impact and an after-shock', () async {
    stage();
    await ShellHaptics(android: false).play('crack');
    expect(native, isEmpty);
    expect(system, <String>[
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  test('the arrival is two taps, with the chime', () async {
    stage();
    await ShellHaptics(android: false).play('arrive');
    expect(system, <String>[
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });
}
