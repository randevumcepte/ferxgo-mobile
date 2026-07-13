import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'call_repository.dart';

enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

/// WebRTC sesli görüşme kontrolcüsü — web `call-widget.js` ile birebir uyumlu.
/// Sinyalleşme HTTP polling, ses P2P. Aktif yolculuk ekranında yaşar.
class CallController extends ChangeNotifier {
  CallController(this._repo, this.publicId, this.peerName);

  final CallRepository _repo;
  final String publicId;
  final String peerName;

  // ── Genel durum ───────────────────────────────────────────
  CallPhase phase = CallPhase.idle;
  String? error;
  int seconds = 0;
  bool muted = false;
  bool speakerOn = false;

  // ── İç durum ──────────────────────────────────────────────
  int? _currentCallId;
  String? _myRole;
  bool _isInitiator = false;
  int _lastSignalId = 0;
  bool _offerMade = false;
  bool _remoteDescSet = false;
  final List<Map<String, dynamic>> _pendingIce = [];
  List<Map<String, dynamic>> _iceServers = const [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  Timer? _statePoll;
  Timer? _signalPoll;
  Timer? _timer;
  bool _pulling = false;
  bool _disposed = false;

  bool get isActive => phase != CallPhase.idle && phase != CallPhase.ended;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _setPhase(CallPhase p) {
    phase = p;
    _emit();
  }

  void _setError(String? msg) {
    error = msg;
    _emit();
  }

  // ── Yaşam döngüsü ─────────────────────────────────────────
  /// Ekran açılınca çağrılır: gelen çağrıyı yakalamak için durum polling'i başlat.
  void startStatePolling() {
    _statePoll ??= Timer.periodic(const Duration(milliseconds: 2000), (_) => _pollState());
    _pollState();
  }

  @override
  void dispose() {
    _disposed = true;
    _statePoll?.cancel();
    _signalPoll?.cancel();
    _timer?.cancel();
    _teardownMedia();
    super.dispose();
  }

  // ── Mikrofon ──────────────────────────────────────────────
  Future<bool> _ensureMic() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _setError('Sesli görüşme için mikrofon izni gerekli.');
      return false;
    }
    if (_localStream != null) return true;
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      return true;
    } catch (e) {
      _setError('Mikrofon açılamadı.');
      return false;
    }
  }

  // ── Aksiyonlar ────────────────────────────────────────────
  Future<void> startCall() async {
    if (isActive || _currentCallId != null) return;
    _setError(null);
    if (!await _ensureMic()) return;
    try {
      final data = await _repo.start(publicId);
      if (data['success'] != true) {
        _setError((data['message'] as String?) ?? 'Çağrı başlatılamadı.');
        _teardownMedia();
        return;
      }
      _applyIceServers(data['ice_servers']);
      final call = data['call'] as Map;
      _currentCallId = (call['id'] as num).toInt();
      _myRole = data['role'] as String?;
      _isInitiator = call['initiator'] == _myRole;
      _lastSignalId = 0;
      _setPhase(CallPhase.outgoing);
      _startSignalPolling();
    } catch (e) {
      _setError('Bağlantı hatası.');
      _teardownMedia();
    }
  }

  Future<void> acceptCall() async {
    _stopNothing();
    _setPhase(CallPhase.connecting);
    if (!await _ensureMic()) {
      _setPhase(CallPhase.incoming);
      return;
    }
    try {
      final data = await _repo.accept(publicId);
      if (data['success'] != true) {
        _setError((data['message'] as String?) ?? 'Kabul edilemedi.');
        _endLocal();
        return;
      }
      _applyIceServers(data['ice_servers']);
      // Offer karşı taraftan (initiator) gelecek → handleRemoteOffer
      await _buildPc();
    } catch (e) {
      _setError('Bağlantı hatası.');
      _endLocal();
    }
  }

  Future<void> hangup() => _end(true);

  void toggleMute() {
    muted = !muted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
    _emit();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (_) {}
    _emit();
  }

  // ── Durum polling ─────────────────────────────────────────
  Future<void> _pollState() async {
    try {
      final data = await _repo.state(publicId);
      if (data['success'] != true) return;
      _myRole = data['role'] as String? ?? _myRole;
      _applyIceServers(data['ice_servers']);
      final call = data['call'] as Map?;
      if (call == null) return;

      final status = call['status'] as String?;
      final initiator = call['initiator'] as String?;
      final callId = (call['id'] as num?)?.toInt();

      // Yeni gelen çağrı
      if (phase == CallPhase.idle && status == 'ringing' && initiator != _myRole) {
        _currentCallId = callId;
        _isInitiator = false;
        _lastSignalId = 0;
        _setPhase(CallPhase.incoming);
        _startSignalPolling();
        return;
      }
      // Giden çağrı kabul edildi → initiator offer yapar
      if (phase == CallPhase.outgoing && status == 'accepted' && _currentCallId == callId) {
        _setPhase(CallPhase.connecting);
        if (_isInitiator) await _makeOffer();
        return;
      }
      // Karşı taraf kapattı
      if ((phase == CallPhase.incoming || phase == CallPhase.outgoing || phase == CallPhase.active || phase == CallPhase.connecting) &&
          (status == 'ended' || status == 'rejected' || status == 'missed') &&
          _currentCallId == callId) {
        _endLocal();
      }
    } catch (_) {}
  }

  // ── Sinyal polling ────────────────────────────────────────
  void _startSignalPolling() {
    _signalPoll ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _pullSignals());
  }

  void _stopSignalPolling() {
    _signalPoll?.cancel();
    _signalPoll = null;
  }

  Future<void> _pullSignals() async {
    if (_currentCallId == null || _pulling) return;
    _pulling = true;
    try {
      final signals = await _repo.pullSignals(publicId, _lastSignalId);
      for (final s in signals) {
        _lastSignalId = (s['id'] as num).toInt();
        final type = s['type'] as String?;
        final payload = (s['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
        if (type == 'offer') {
          await _handleRemoteOffer(payload);
        } else if (type == 'answer') {
          await _handleRemoteAnswer(payload);
        } else if (type == 'ice') {
          await _handleRemoteIce(payload);
        } else if (type == 'bye') {
          _endLocal();
        }
      }
    } catch (_) {} finally {
      _pulling = false;
    }
  }

  // ── WebRTC ────────────────────────────────────────────────
  Future<RTCPeerConnection> _buildPc() async {
    if (_pc != null) return _pc!;
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });

    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      _repo.pushSignal(publicId, 'ice', {
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };

    pc.onIceConnectionState = (RTCIceConnectionState st) {
      if (st == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          st == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _goActive();
      }
      if (st == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _setError('Bağlantı kurulamadı (NAT/firewall).');
        Future.delayed(const Duration(milliseconds: 1200), () => _end(true));
      }
    };
    pc.onConnectionState = (RTCPeerConnectionState st) {
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _goActive();
      }
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          st == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (phase == CallPhase.active) {
          Future.delayed(const Duration(milliseconds: 800), () => _end(true));
        }
      }
    };
    // Uzak ses mobilde otomatik oynar; onTrack sadece emniyet.
    pc.onTrack = (RTCTrackEvent e) {};

    _pc = pc;
    return pc;
  }

  void _addLocalTracks(RTCPeerConnection pc) {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      pc.addTrack(track, stream);
    }
  }

  Future<void> _makeOffer() async {
    if (_offerMade) return;
    _offerMade = true;
    if (!await _ensureMic()) return;
    final pc = await _buildPc();
    _addLocalTracks(pc);
    final offer = await pc.createOffer({'offerToReceiveAudio': 1});
    await pc.setLocalDescription(offer);
    await _repo.pushSignal(publicId, 'offer', {
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  Future<void> _handleRemoteOffer(Map<String, dynamic> payload) async {
    final pc = await _buildPc();
    await pc.setRemoteDescription(
      RTCSessionDescription(_fixSdp(payload['sdp'] as String?), payload['type'] as String?),
    );
    _remoteDescSet = true;
    if (!await _ensureMic()) return;
    _addLocalTracks(pc);
    await _drainIce();
    final answer = await pc.createAnswer({'offerToReceiveAudio': 1});
    await pc.setLocalDescription(answer);
    await _repo.pushSignal(publicId, 'answer', {
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  Future<void> _handleRemoteAnswer(Map<String, dynamic> payload) async {
    final pc = _pc;
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(_fixSdp(payload['sdp'] as String?), payload['type'] as String?),
    );
    _remoteDescSet = true;
    await _drainIce();
  }

  Future<void> _handleRemoteIce(Map<String, dynamic> payload) async {
    final cand = (payload['candidate'] as Map?)?.cast<String, dynamic>();
    if (cand == null) return;
    if (!_remoteDescSet || _pc == null) {
      _pendingIce.add(cand);
      return;
    }
    await _addIce(cand);
  }

  Future<void> _drainIce() async {
    while (_pendingIce.isNotEmpty) {
      await _addIce(_pendingIce.removeAt(0));
    }
  }

  Future<void> _addIce(Map<String, dynamic> cand) async {
    try {
      await _pc?.addCandidate(RTCIceCandidate(
        cand['candidate'] as String?,
        cand['sdpMid'] as String?,
        (cand['sdpMLineIndex'] as num?)?.toInt(),
      ));
    } catch (_) {}
  }

  /// Laravel TrimStrings SDP sonundaki \r\n'i kırpabilir → geri ekle.
  String? _fixSdp(String? sdp) {
    if (sdp == null) return null;
    return sdp.endsWith('\r\n') ? sdp : '$sdp\r\n';
  }

  // ── Bağlandı ──────────────────────────────────────────────
  void _goActive() {
    if (phase == CallPhase.active) return;
    _setPhase(CallPhase.active);
    _timer?.cancel();
    seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      seconds++;
      _emit();
    });
  }

  // ── Sonlandırma ───────────────────────────────────────────
  Future<void> _end(bool notifyServer) async {
    if (notifyServer && _currentCallId != null) {
      try {
        await _repo.end(publicId);
      } catch (_) {}
    }
    _endLocal();
  }

  void _endLocal() {
    _stopSignalPolling();
    _timer?.cancel();
    _teardownMedia();
    _currentCallId = null;
    _isInitiator = false;
    _lastSignalId = 0;
    _offerMade = false;
    _remoteDescSet = false;
    _pendingIce.clear();
    seconds = 0;
    muted = false;
    _setPhase(CallPhase.idle);
  }

  void _teardownMedia() {
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    final s = _localStream;
    if (s != null) {
      for (final t in s.getTracks()) {
        t.stop();
      }
      s.dispose();
      _localStream = null;
    }
  }

  void _stopNothing() {} // ringtone yok (mobilde native/UI ile ele alınır)

  void _applyIceServers(Object? raw) {
    if (raw is List && raw.isNotEmpty) {
      _iceServers = raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false);
    }
  }
}

/// Ekran (publicId) başına bir controller. autoDispose → ekrandan çıkınca kapanır.
final callControllerProvider =
    ChangeNotifierProvider.family.autoDispose<CallController, ({String publicId, String peerName})>(
  (ref, arg) {
    final c = CallController(ref.watch(callRepositoryProvider), arg.publicId, arg.peerName);
    ref.onDispose(() {}); // dispose ChangeNotifier.dispose ile zaten çağrılır
    return c;
  },
);
