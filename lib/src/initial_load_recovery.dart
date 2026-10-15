import 'dart:async';

import 'package:flutter/foundation.dart';

enum InitialLoadProblem { slow, interrupted }

/// Bounds the native loading overlay, without reloading the page on a deadline.
/// A completed attempt stays completed until an explicit retry starts another.
class InitialLoadRecovery extends ChangeNotifier {
  InitialLoadRecovery({this.deadline = const Duration(seconds: 45)});

  final Duration deadline;
  Timer? _timer;
  bool _finished = false;
  InitialLoadProblem? _problem;

  bool get blocksContent => !_finished && _problem == null;
  InitialLoadProblem? get problem => _problem;

  void start() {
    _timer?.cancel();
    _finished = false;
    _problem = null;
    _timer = Timer(deadline, () => _showProblem(InitialLoadProblem.slow));
    notifyListeners();
  }

  void finish() {
    _timer?.cancel();
    _timer = null;
    _finished = true;
    _problem = null;
    notifyListeners();
  }

  void interrupted() => _showProblem(InitialLoadProblem.interrupted);

  void _showProblem(InitialLoadProblem problem) {
    if (_finished) return;
    _timer?.cancel();
    _timer = null;
    _problem = problem;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
