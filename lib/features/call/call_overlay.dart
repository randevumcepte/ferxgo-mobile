import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import 'call_controller.dart';

typedef CallArg = ({String publicId, String peerName});

/// Aktif yolculuk ekranlarına Stack ile bindirilir. Gelen çağrıyı yakalamak
/// için durum polling'ini başlatır; çağrı varsa tam ekran arama arayüzü gösterir.
class CallOverlay extends ConsumerStatefulWidget {
  const CallOverlay({super.key, required this.publicId, required this.peerName});
  final String publicId;
  final String peerName;

  @override
  ConsumerState<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends ConsumerState<CallOverlay> {
  CallArg get _arg => (publicId: widget.publicId, peerName: widget.peerName);

  @override
  void initState() {
    super.initState();
    // İlk frame sonrası polling'i başlat (gelen çağrı yakalansın).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(callControllerProvider(_arg)).startStatePolling();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(callControllerProvider(_arg));
    if (c.phase == CallPhase.idle || c.phase == CallPhase.ended) {
      return const SizedBox.shrink();
    }
    return _CallScreen(c: c);
  }
}

/// Butondan çağrı başlatmak için kısa yol.
void startCallFor(WidgetRef ref, CallArg arg) {
  ref.read(callControllerProvider(arg)).startCall();
}

class _CallScreen extends StatelessWidget {
  const _CallScreen({required this.c});
  final CallController c;

  String get _statusText => switch (c.phase) {
        CallPhase.outgoing => 'Arıyor…',
        CallPhase.incoming => 'Gelen çağrı',
        CallPhase.connecting => 'Bağlanıyor…',
        CallPhase.active => _fmt(c.seconds),
        _ => '',
      };

  static String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = c.phase == CallPhase.active;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 24),
                Column(
                  children: [
                    // Avatar
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [FerxgoColors.brand, Color(0xFFB8860B)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: FerxgoColors.brand.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 4)],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.person, color: Colors.black, size: 60),
                    ),
                    const SizedBox(height: 22),
                    Text(c.peerName,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(_statusText,
                      style: TextStyle(
                        color: isActive ? FerxgoColors.brand : Colors.white70,
                        fontSize: isActive ? 26 : 15,
                        fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                        fontFeatures: isActive ? const [FontFeature.tabularFigures()] : null,
                      )),
                    if (c.error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: FerxgoColors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: FerxgoColors.danger.withValues(alpha: 0.4)),
                        ),
                        child: Text(c.error!, textAlign: TextAlign.center,
                          style: const TextStyle(color: FerxgoColors.danger, fontSize: 13)),
                      ),
                    ],
                  ],
                ),

                // Butonlar
                _buttons(context, isActive),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context, bool isActive) {
    if (c.phase == CallPhase.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _bigBtn(icon: Icons.call_end, color: FerxgoColors.danger, label: 'Reddet', onTap: c.hangup),
          _bigBtn(icon: Icons.call, color: FerxgoColors.success, label: 'Kabul et', onTap: c.acceptCall),
        ],
      );
    }
    if (isActive || c.phase == CallPhase.connecting) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _smallBtn(
                icon: c.muted ? Icons.mic_off : Icons.mic,
                active: !c.muted,
                label: c.muted ? 'Kapalı' : 'Mikrofon',
                onTap: c.toggleMute,
              ),
              _smallBtn(
                icon: c.speakerOn ? Icons.volume_up : Icons.hearing,
                active: c.speakerOn,
                label: c.speakerOn ? 'Hoparlör' : 'Kulaklık',
                onTap: c.toggleSpeaker,
              ),
            ],
          ),
          const SizedBox(height: 28),
          _bigBtn(icon: Icons.call_end, color: FerxgoColors.danger, label: 'Kapat', onTap: c.hangup),
        ],
      );
    }
    // outgoing
    return _bigBtn(icon: Icons.call_end, color: FerxgoColors.danger, label: 'İptal', onTap: c.hangup);
  }

  Widget _bigBtn({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }

  Widget _smallBtn({required IconData icon, required bool active, required String label, required VoidCallback onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? FerxgoColors.brand.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon, color: active ? FerxgoColors.brand : Colors.white70, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
