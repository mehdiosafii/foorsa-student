import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/shell_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('foorsa/haptics');

  late List<Object?> native;
  late List<String> system;

  /// [answer] is what the Android side returns; null stands for an app
  /// built before the channel existed.
  void stage({bool? answer = true}) {
    native = <Object?>[];
    system = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      native.add(call.arguments);
      if (answer == null) throw MissingPluginException();
      return answer;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        system.add('${call.arguments}'.replaceFirst('HapticFeedbackType.', ''));
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
    expect(ShellHaptics.touchFrom('heartbeat'), 'heartbeat');
    expect(ShellHaptics.touchFrom(8), 'select');
    expect(ShellHaptics.touchFrom(<int>[8, 30]), 'select');
    expect(ShellHaptics.touchFrom(null), 'select');
    expect(ShellHaptics.touchFrom('shake'), 'select');
  });

  test('reads how far the pull has come, and treats nonsense as full', () {
    expect(ShellHaptics.levelFrom(0.4), 0.4);
    expect(ShellHaptics.levelFrom(3), 1.0);
    expect(ShellHaptics.levelFrom(-1), 0.0);
    expect(ShellHaptics.levelFrom(null), 1.0);
    expect(ShellHaptics.levelFrom('high'), 1.0);
  });

  test('tells the portal it plays textures', () {
    expect(ShellHaptics.capabilities['hapticTextures'], 2);
  });

  test('portal buttons keep the light tick they have always had', () async {
    stage();
    await ShellHaptics(android: true).play(8);
    expect(native, isEmpty);
    expect(system, <String>['lightImpact']);
  });

  test(
    'on Android every texture plays natively, with the pull level',
    () async {
      stage();
      final haptics = ShellHaptics(android: true);
      for (final touch in ShellHaptics.textures) {
        await haptics.play(touch, touch == 'grain' ? 0.25 : null);
      }
      expect(
        native,
        ShellHaptics.textures.map(
          (touch) => {'touch': touch, 'level': touch == 'grain' ? 0.25 : 1.0},
        ),
      );
      expect(system, isEmpty);
    },
  );

  test('a phone that cannot play one falls back to system impacts', () async {
    stage(answer: false);
    await ShellHaptics(android: true).play('land');
    expect(native, hasLength(1));
    expect(system, <String>['mediumImpact']);
  });

  test('an app without the channel stops asking for it', () async {
    stage(answer: null);
    final haptics = ShellHaptics(android: true);
    await haptics.play('press');
    await haptics.play('press');
    expect(native, hasLength(1));
    expect(system, <String>['lightImpact', 'lightImpact']);
  });

  test('on iOS the heart beats strong, then softer', () async {
    stage();
    await ShellHaptics(android: false).play('heartbeat');
    expect(native, isEmpty);
    expect(system, <String>['heavyImpact', 'mediumImpact']);
  });

  test('on iOS the grain firms up as the letter comes out', () async {
    stage();
    final haptics = ShellHaptics(android: false);
    await haptics.play('grain', 0.2);
    await haptics.play('grain', 0.9);
    expect(system, <String>['selectionClick', 'lightImpact']);
  });

  test(
    'the arrival lands on the downbeat and the melody\'s first notes',
    () async {
      stage();
      await ShellHaptics(android: false).play('arrive');
      expect(system, <String>[
        'heavyImpact',
        'lightImpact',
        'lightImpact',
        'mediumImpact',
      ]);
    },
  );
}
