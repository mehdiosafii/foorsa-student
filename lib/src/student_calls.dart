import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

String callDeviceId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

bool validStudentCall(Map<String, dynamic> data) {
  final expires = DateTime.tryParse('${data['expiresAt']}');
  return RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch('${data['callId']}') &&
      data['token'] is String &&
      (data['token'] as String).length >= 64 &&
      (data['token'] as String).length <= 2048 &&
      expires != null &&
      expires.isAfter(DateTime.now()) &&
      expires.difference(DateTime.now()).inSeconds <= 60;
}

Future<Map<String, dynamic>> callSignal(
    Map<String, dynamic> invite, String operation,
    {String? sdp}) async {
  final response = await http
      .post(Uri.parse('${AppConfig.baseUrl}/api/portal/chat/call/receive'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${invite['token']}'
          },
          body: jsonEncode(
              {'operation': operation, 'device': invite['device'], 'sdp': sdp}))
      .timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) throw StateError('Call unavailable');
  return jsonDecode(response.body) as Map<String, dynamic>;
}

/// Background Android declines must reach the server even when the UI engine is not running.
@pragma('vm:entry-point')
Future<void> studentCallBackground(CallEvent event) async {
  final params = switch (event) {
    CallEventActionCallDecline(:final callKitParams) => callKitParams,
    CallEventActionCallEnded(:final callKitParams) => callKitParams,
    _ => null
  };
  if (params?.extra != null) {
    try {
      await callSignal(params!.extra!,
          event is CallEventActionCallDecline ? 'decline' : 'end');
    } catch (_) {}
  }
}

Future<void> showStudentCall(Map<String, dynamic> invite) async {
  if (!validStudentCall(invite)) return;
  final calls = await FlutterCallkitIncoming.activeCalls();
  if (calls.any((c) => c.id == invite['callId'])) return;
  final extra = {...invite, 'device': callDeviceId()};
  if (calls.isNotEmpty) {
    try {
      await callSignal(extra, 'decline');
    } catch (_) {}
    return;
  }
  await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
      id: invite['callId'],
      nameCaller: '${invite['callerName'] ?? 'Foorsa adviser'}',
      appName: 'Foorsa Student',
      handle: 'Foorsa adviser',
      type: 0,
      duration: DateTime.parse(invite['expiresAt'])
          .difference(DateTime.now())
          .inMilliseconds,
      extra: extra,
      missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: 'Missed adviser call'),
      callingNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: 'Call in progress'),
      android: const AndroidParams(
          isCustomNotification: true,
          isShowFullLockedScreen: true,
          backgroundColor: '#183250',
          actionColor: '#16a66c',
          textAccept: 'Answer',
          textDecline: 'Decline',
          incomingCallNotificationChannelName: 'Adviser calls',
          missedCallNotificationChannelName: 'Missed adviser calls'),
      ios: const IOSParams(
          handleType: 'generic',
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          includesCallsInRecents: false,
          audioSessionMode: 'voiceChat',
          audioSessionActive: false)));
}

/// Starts adviser calls without ever holding the app back: whatever the
/// platform answers, or however long it takes, the app goes on to draw.
Future<void> startStudentCalls(
    {Future<void> Function()? start,
    Duration patience = const Duration(seconds: 2)}) async {
  try {
    await (start ?? StudentCalls.instance.start)().timeout(patience);
  } catch (error) {
    debugPrint('adviser calls not started: $error');
  }
}

class StudentCalls extends ChangeNotifier {
  static final instance = StudentCalls._();
  StudentCalls._();
  static const native = MethodChannel('ma.foorsa.student/calls');
  Map<String, dynamic>? invite;
  String status = '';
  bool muted = false, speaker = false;
  bool _answering = false;
  bool _started = false;
  int _generation = 0;
  RTCPeerConnection? _peer;
  MediaStream? _stream;
  Timer? _timer;
  DateTime _lastSuccess = DateTime.now();
  DateTime _lastPulse = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> start() async {
    if (_started) return;
    _started = true;
    native.setMethodCallHandler((call) async {
      if (call.method == 'reset') {
        await end();
      }
    });
    // Only Android runs a background isolate for calls. On iOS PushKit wakes
    // the app itself, and the plugin answers this method "not implemented":
    // thrown out of main, that kept every iPhone on the launch screen.
    if (Platform.isAndroid) {
      try {
        await FlutterCallkitIncoming.onBackgroundMessage(studentCallBackground);
      } catch (error) {
        debugPrint('adviser calls: no background handler: $error');
      }
    }
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event is CallEventActionCallAccept) {
        unawaited(answer(event.callKitParams));
      } else if (event is CallEventActionCallIncoming) {
        _watch(event.callKitParams);
      } else if (event is CallEventActionCallDecline) {
        unawaited(end(params: event.callKitParams, operation: 'decline'));
      } else if (event is CallEventActionCallEnded) {
        unawaited(end(params: event.callKitParams));
      } else if (event is CallEventActionCallTimeout) {
        unawaited(end());
      } else if (event is CallEventActionCallToggleMute) {
        mute(event.isMuted, syncSystem: false);
      } else if (event is CallEventActionDidUpdateDevicePushTokenVoip) {
        onTokenChanged?.call();
      }
      // Intentionally no outgoing or callback action.
    }, onError: (Object error) {
      debugPrint('adviser call events: $error');
    });
    try {
      for (final call in await FlutterCallkitIncoming.activeCalls()) {
        if (call.isAccepted) {
          unawaited(answer(call));
        } else {
          _watch(call);
        }
      }
    } catch (error) {
      debugPrint('adviser calls: active calls unknown: $error');
    }
  }

  void Function()? onTokenChanged;
  void _watch(CallKitParams params) {
    if (params.extra == null || invite != null) return;
    invite = params.extra;
    status = 'Incoming call';
    _lastSuccess = DateTime.now();
    notifyListeners();
    _poll();
  }

  Future<void> _poll() async {
    final own = _generation;
    final current = invite;
    if (current == null) return;
    try {
      final pulse =
          _peer != null && DateTime.now().difference(_lastPulse).inSeconds > 15;
      if (pulse) _lastPulse = DateTime.now();
      final result = await callSignal(current, pulse ? 'pulse' : 'get');
      if (own != _generation) return;
      _lastSuccess = DateTime.now();
      final call = result['call'];
      if (call == null ||
          !['ringing', 'connecting', 'active'].contains(call['state']) ||
          (call['receiver_id'] != null &&
              call['receiver_id'] != current['device'])) {
        await end(notifyServer: false);
        return;
      }
      if (DateTime.parse(call['expires_at']).isBefore(DateTime.now())) {
        await end(notifyServer: false);
        return;
      }
    } catch (_) {
      if (own == _generation) {
        if (DateTime.now().difference(_lastSuccess).inSeconds > 60) {
          await end(notifyServer: false);
          return;
        }
        status = 'Reconnecting…';
        notifyListeners();
      }
    }
    if (own == _generation && invite != null) {
      _timer = Timer(const Duration(seconds: 2), _poll);
    }
  }

  Future<void> answer(CallKitParams params) async {
    if (_answering || _peer != null || params.extra == null) return;
    _answering = true;
    invite = params.extra;
    status = 'Connecting…';
    notifyListeners();
    final own = _generation;
    try {
      final result = await callSignal(invite!, 'get');
      if (own != _generation) return;
      final call = result['call'];
      if (call == null ||
          call['state'] != 'ringing' ||
          DateTime.parse(call['expires_at']).isBefore(DateTime.now())) {
        throw StateError('Call ended');
      }
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true
        },
        'video': false
      });
      if (own != _generation) {
        for (final t in stream.getTracks()) {
          await t.stop();
        }
        await stream.dispose();
        return;
      }
      _stream = stream;
      final pc = await createPeerConnection(
          {'iceServers': result['iceServers'], 'sdpSemantics': 'unified-plan'});
      if (own != _generation) {
        await pc.close();
        await pc.dispose();
        return;
      }
      _peer = pc;
      var answerSaved = false;
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      final gathered = Completer<void>();
      pc.onIceGatheringState = (state) {
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !gathered.isCompleted) {
          gathered.complete();
        }
      };
      pc.onConnectionState = (state) {
        if (own != _generation) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          status = 'Connected';
          notifyListeners();
          if (answerSaved) {
            unawaited(callSignal(invite!, 'connected')
                .catchError((_) => <String, dynamic>{}));
          }
          unawaited(FlutterCallkitIncoming.setCallConnected(params.id));
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          unawaited(end());
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          status = 'Reconnecting…';
          notifyListeners();
        }
      };
      await pc
          .setRemoteDescription(RTCSessionDescription(call['offer'], 'offer'));
      await pc.setLocalDescription(await pc.createAnswer());
      await gathered.future.timeout(const Duration(seconds: 12));
      if (own != _generation) return;
      final description = await pc.getLocalDescription();
      await callSignal(invite!, 'answer', sdp: description?.sdp);
      answerSaved = true;
      if (own != _generation) return;
      if (pc.connectionState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        await callSignal(invite!, 'connected');
      }
      if (Platform.isIOS) await native.invokeMethod('answerReady', params.id);
      _timer?.cancel();
      unawaited(_poll());
    } catch (_) {
      if (own == _generation) {
        await end();
        status =
            'Call could not connect. Check microphone permission and your connection.';
        notifyListeners();
      }
    } finally {
      _answering = false;
    }
  }

  void mute(bool value, {bool syncSystem = true}) {
    muted = value;
    if (syncSystem && invite != null) {
      unawaited(FlutterCallkitIncoming.muteCall('${invite!['callId']}',
          isMuted: value));
    }
    for (final track in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !value;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
    notifyListeners();
  }

  Future<void> end(
      {CallKitParams? params,
      String operation = 'end',
      bool notifyServer = true}) async {
    final current = invite ?? params?.extra;
    if (current == null) return;
    _generation++;
    invite = null;
    _timer?.cancel();
    final pc = _peer;
    _peer = null;
    await pc?.close();
    await pc?.dispose();
    final stream = _stream;
    _stream = null;
    for (final t in stream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await stream?.dispose();
    muted = false;
    speaker = false;
    _answering = false;
    status = '';
    notifyListeners();
    await FlutterCallkitIncoming.endCall('${current['callId']}');
    if (notifyServer) {
      try {
        await callSignal(current, operation);
      } catch (_) {}
    }
  }
}

class StudentCallOverlay extends StatelessWidget {
  const StudentCallOverlay({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: StudentCalls.instance,
      builder: (context, _) {
        final calls = StudentCalls.instance;
        final invite = calls.invite;
        return Stack(children: [
          child,
          if (invite != null && calls.status != 'Incoming call')
            Positioned.fill(
                child: Material(
                    color: const Color(0xff102b42),
                    child: SafeArea(
                        child: Column(children: [
                      const SizedBox(height: 60),
                      const Text('FOORSA · VOICE CALL',
                          style: TextStyle(
                              color: Colors.white70, letterSpacing: 2)),
                      const Spacer(),
                      CircleAvatar(
                          radius: 55,
                          backgroundColor: Colors.white12,
                          child: Text(
                              '${invite['callerName'] ?? 'F'}'.substring(0, 1),
                              style: const TextStyle(
                                  fontSize: 42, color: Colors.white))),
                      const SizedBox(height: 28),
                      Text('${invite['callerName'] ?? 'Foorsa adviser'}',
                          style: const TextStyle(
                              fontSize: 28, color: Colors.white)),
                      const SizedBox(height: 14),
                      Text(calls.status,
                          style: const TextStyle(color: Colors.white70)),
                      const Spacer(),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _control(
                                calls.muted ? Icons.mic_off : Icons.mic,
                                calls.muted ? 'Unmute' : 'Mute',
                                () => calls.mute(!calls.muted)),
                            _control(
                                calls.speaker ? Icons.volume_up : Icons.hearing,
                                'Speaker',
                                () => calls.toggleSpeaker()),
                            _control(Icons.call_end, 'End', () => calls.end(),
                                danger: true)
                          ]),
                      const SizedBox(height: 60)
                    ]))))
        ]);
      });
  Widget _control(IconData icon, String label, VoidCallback action,
          {bool danger = false}) =>
      Column(children: [
        IconButton.filled(
            onPressed: action,
            style: IconButton.styleFrom(
                backgroundColor:
                    danger ? const Color(0xffdf4053) : Colors.white24,
                padding: const EdgeInsets.all(22)),
            icon: Icon(icon, color: Colors.white, size: 28)),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white))
      ]);
}
