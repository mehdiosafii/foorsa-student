import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/file_fetch.dart';

/// The loader over the portal while a file is fetched. It used to be taken
/// away with `Navigator.pop()`: on Android a student who pressed back while it
/// showed had already closed it, so when the file arrived the pop took the
/// app's own page instead (a blank app, the stress test of 11 Nov 2026).
void main() {
  Future<BuildContext> home(WidgetTester tester, {NavigatorObserver? observer}) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [if (observer != null) observer],
      home: const Scaffold(body: Text('Portal')),
    ));
    return tester.element(find.text('Portal'));
  }

  testWidgets('it shows over the page and goes when the file has arrived', (tester) async {
    final context = await home(tester);
    final spinner = ShellSpinner.show(context, child: const Text('loading'))!;
    await tester.pump();
    expect(find.text('loading'), findsOneWidget);
    expect(spinner.showing, isTrue);
    spinner.dismiss();
    await tester.pump();
    expect(find.text('loading'), findsNothing);
    expect(find.text('Portal'), findsOneWidget);
    expect(spinner.showing, isFalse);
    // A second call (the error path after the success path) changes nothing.
    spinner.dismiss();
    await tester.pump();
    expect(find.text('Portal'), findsOneWidget);
  });

  testWidgets('closed by the back button, its later dismissal leaves the app page alone', (tester) async {
    final context = await home(tester);
    final spinner = ShellSpinner.show(context, child: const Text('loading'))!;
    await tester.pump();
    // Android's back button, while the file is still on its way.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('loading'), findsNothing);
    // The file arrives.
    spinner.dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Portal'), findsOneWidget);
    expect(Navigator.of(context).canPop(), isFalse);
  });

  testWidgets('with a page opened over it, only the loader goes', (tester) async {
    final context = await home(tester);
    final spinner = ShellSpinner.show(context, child: const Text('loading'))!;
    await tester.pump();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Preview'))));
    await tester.pumpAndSettle();
    spinner.dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsOneWidget);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(find.text('Portal'), findsOneWidget);
    expect(find.text('loading'), findsNothing);
  });

  testWidgets('a page already gone shows no loader', (tester) async {
    final context = await home(tester);
    await tester.pumpWidget(const SizedBox());
    expect(ShellSpinner.show(context, child: const Text('loading')), isNull);
  });
}
