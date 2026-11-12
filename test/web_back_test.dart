// Android's back button with something open over the portal's screen
// (lib/src/web_back.dart). The page's side of it, the two scripts, runs in
// test/web_back_test.cjs against a page with layers.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/web_back.dart';

/// A page that answers the two scripts as [ask] and [answers] say, and keeps
/// what it was asked.
class _Page {
  _Page({this.ask = 'asked', this.answers = const [true]});
  final Object? ask;
  final List<Object?> answers;
  final asked = <String>[];
  var _look = 0;

  Future<Object?> evaluate(String source) async {
    asked.add(source == webLayerAsk ? 'ask' : source == webLayerAnswered ? 'look' : 'other');
    if (source == webLayerAsk) return ask;
    final answer = answers[_look < answers.length ? _look : answers.length - 1];
    _look++;
    return answer;
  }
}

const _quick = Duration(milliseconds: 1);

void main() {
  test('with nothing open, back is not the page\'s', () async {
    final page = _Page(ask: 'none');
    expect(await closeTopWebLayer(page.evaluate, look: _quick), isFalse);
    expect(page.asked, ['ask'], reason: 'nothing was pressed, so nothing is waited for');
  });

  test('a layer that closes takes the press', () async {
    final page = _Page(answers: [true]);
    expect(await closeTopWebLayer(page.evaluate, look: _quick), isTrue);
    expect(page.asked, ['ask', 'look']);
  });

  test('a dialog that takes the press at once is not waited for', () async {
    // The admission letter goes back into its envelope over a few seconds:
    // it has taken the press long before it is gone.
    final page = _Page(ask: 'taken', answers: [false]);
    expect(await closeTopWebLayer(page.evaluate, look: _quick), isTrue);
    expect(page.asked, ['ask']);
  });

  test('a slow phone is given three looks', () async {
    final page = _Page(answers: [false, false, true]);
    expect(await closeTopWebLayer(page.evaluate, look: _quick), isTrue);
    expect(page.asked, ['ask', 'look', 'look', 'look']);
  });

  test('a layer that does not answer leaves back as it was', () async {
    // The contract to sign is locked on purpose: back then steps through the
    // history, or offers to leave the app, as before.
    final page = _Page(answers: [false]);
    expect(await closeTopWebLayer(page.evaluate, look: _quick), isFalse);
    expect(page.asked, ['ask', 'look', 'look', 'look']);
  });

  test('a page that cannot be asked leaves back as it was', () async {
    expect(await closeTopWebLayer((_) async => throw StateError('no page'), look: _quick), isFalse);
    expect(await closeTopWebLayer((_) async => null, look: _quick), isFalse);
    // A page that never answers is not waited for.
    expect(
        await closeTopWebLayer((_) => Completer<Object?>().future,
            look: _quick, patience: const Duration(milliseconds: 20)),
        isFalse);
  });

  test('the shell offers the press to the page before the history', () {
    final shell = File('lib/src/shell_page.dart').readAsStringSync();
    final answer = shell.substring(shell.indexOf('Future<void> _answerBack() async {'));
    final layer = answer.indexOf('closeTopWebLayer(');
    final history = answer.indexOf('c.canGoBack()');
    expect(layer, isNonNegative);
    expect(history, greaterThan(layer), reason: 'the open layer first, then a step back');
    // One press is answered at a time: a second back while the page is asked
    // must not also step back.
    final handle = shell.substring(shell.indexOf('Future<void> _handleBack() async {'), shell.indexOf('Future<void> _answerBack() async {'));
    expect(handle, contains('if (_backBusy) return;'));
    expect(handle, contains('_backBusy = false;'));
  });

  test('the scripts name the portal\'s layers and press Escape in the topmost', () {
    for (final script in [webLayerAsk, webLayerAnswered]) {
      expect(script, contains('[data-sheet-layer]'));
      expect(script, contains('dialog[open]'));
      expect(script, contains('[role="dialog"]'));
    }
    expect(webLayerAsk, contains("key: 'Escape'"));
    expect(webLayerAsk, contains('bubbles: true'));
    expect(webLayerAsk, contains("return 'asked';"));
    expect(webLayerAsk, contains("return 'taken';"));
    expect(webLayerAsk, contains("new Event('cancel', { cancelable: true })"),
        reason: 'a native dialog hears the press as the browser tells it');
    expect(webLayerAsk, contains("return 'none';"));
  });
}
