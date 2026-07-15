import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../../../core/location/location_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/price_stepper.dart';
import '../../call/call_overlay.dart';
import '../../customer/models/ride_status.dart' show RideMessage;
import '../../safety/panic_button.dart';
import '../driver_repository.dart';
import '../models/driver_state.dart';

/// Sürücü ana ekranı (Faz 2). Tek `/driver/state` endpoint'i 3 sn polling ile
/// idle / teklif / aktif yolculuk arasında geçiş yapar.
class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final MapController _map = MapController();
  Timer? _stateTimer;
  Timer? _locationTimer;

  DriverState? _state;
  String? _error;
  bool _busy = false; // online toggle / offer aksiyonları

  // Görünürlük/hizmet çapı (km) — slider ile ayarlanır.
  double? _radiusDraft;
  bool _radiusBusy = false;

  LatLng? _myPosition;

  // Aktif yolculuk chat
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _msgScroll = ScrollController();
  final List<RideMessage> _messages = [];
  int _lastMessageId = 0;
  bool _sendingMsg = false;
  bool _chatOpen = false;

  // Sesli uyarı: teklif gelince cihaz sesi çalar, teklif kalkınca susar.
  bool _ringing = false;

  DriverRepository get _repo => ref.read(driverRepositoryProvider);

  void _startOfferSound() {
    if (_ringing) return;
    _ringing = true;
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.electronic,
        looping: true,   // teklif ekranda durdukça çalmaya devam etsin
        volume: 1.0,
        asAlarm: false,
      );
    } catch (_) {}
    HapticFeedback.heavyImpact();
  }

  void _stopOfferSound() {
    if (!_ringing) return;
    _ringing = false;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _poll();
    _stateTimer = Timer.periodic(AppConfig.driverPollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _stopOfferSound();
    _stateTimer?.cancel();
    _locationTimer?.cancel();
    _msgCtrl.dispose();
    _msgScroll.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final s = await _repo.state(sinceId: _lastMessageId);
      if (!mounted) return;
      // Aktif yolculuktaki yeni mesajları biriktir
      if (s.messages.isNotEmpty) {
        _messages.addAll(s.messages);
        _lastMessageId = s.messages.last.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_msgScroll.hasClients) {
            _msgScroll.jumpTo(_msgScroll.position.maxScrollExtent);
          }
        });
      }
      // Aktif yolculuk bitince chat sıfırlansın
      if (s.active == null && _messages.isNotEmpty) {
        _messages.clear();
        _lastMessageId = 0;
        _chatOpen = false;
      }
      setState(() {
        _state = s;
        _error = null;
      });
      // Sesli uyarı: yeni teklif geldiyse çal, teklif kalktıysa durdur.
      if (s.hasOffer && !s.hasActive) {
        _startOfferSound();
      } else {
        _stopOfferSound();
      }
      _syncLocationTimer(s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {}
  }

  /// Online iken periyodik konum gönderimini aç/kapat.
  void _syncLocationTimer(DriverState s) {
    if (s.isOnline && !s.hasActive) {
      _locationTimer ??= Timer.periodic(const Duration(seconds: 25), (_) => _pushLocation());
    } else {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  Future<void> _pushLocation() async {
    final loc = await ref.read(locationServiceProvider).currentPosition();
    if (loc is LocationFix) {
      _myPosition = loc.position;
      try {
        await _repo.updateLocation(loc.position.latitude, loc.position.longitude);
      } catch (_) {}
    }
  }

  // ─── Online / offline ─────────────────────────────────────
  Future<void> _toggleOnline(bool goOnline) async {
    setState(() { _busy = true; _error = null; });
    try {
      double? lat, lng;
      if (goOnline) {
        final loc = await ref.read(locationServiceProvider).currentPosition();
        if (loc is LocationError) {
          if (mounted) setState(() => _error = loc.reason.userMessage);
          return;
        }
        if (loc is LocationFix) {
          _myPosition = loc.position;
          lat = loc.position.latitude;
          lng = loc.position.longitude;
        }
      }
      await _repo.setAvailability(goOnline ? 'online' : 'offline', lat: lat, lng: lng);
      await _poll();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Görünürlük çapı ──────────────────────────────────────
  Future<void> _setRadius(double km) async {
    setState(() => _radiusBusy = true);
    try {
      final saved = await _repo.setServiceRadius(km);
      if (!mounted) return;
      setState(() => _radiusDraft = saved);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Görünürlük çapın ${saved.toStringAsFixed(saved % 1 == 0 ? 0 : 1)} km olarak kaydedildi.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FerxgoColors.inkMuted,
        ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _radiusBusy = false);
    }
  }

  // ─── Teklif aksiyonları ───────────────────────────────────
  Future<void> _acceptOffer(DriverOffer offer) async {
    _stopOfferSound();
    setState(() => _busy = true);
    try {
      await _repo.acceptOffer(offer.publicId);
      await _poll();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectOffer(DriverOffer offer) async {
    _stopOfferSound();
    setState(() => _busy = true);
    try {
      await _repo.rejectOffer(offer.publicId);
      await _poll();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _counterOffer(DriverOffer offer) async {
    _stopOfferSound();
    final neg = offer.negotiation;
    final base = offer.customerOffer;
    final min = neg?.minFare ?? (base * 0.6).roundToDouble();
    final max = neg?.maxFare ?? (base * 1.6).roundToDouble();
    var draft = base.roundToDouble().clamp(min, max);

    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FerxgoColors.inkSoft,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Karşı teklifin',
                style: TextStyle(color: FerxgoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text('Yolcu ${offer.customerOffer.toStringAsFixed(0)} ₺ teklif etti',
                style: const TextStyle(color: FerxgoColors.textLow, fontSize: 13),
              ),
              const SizedBox(height: 16),
              PriceStepper(
                value: draft.toDouble(),
                min: min, max: max, step: 10,
                onChanged: (v) => setSheet(() => draft = v),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, draft.toDouble()),
                child: const Text('Karşı teklifi gönder'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;
    setState(() => _busy = true);
    try {
      await _repo.counterOffer(offer.publicId, result);
      await _poll();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Aktif yolculuk aksiyonları ───────────────────────────
  Future<void> _runActive(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _poll();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendMessage() async {
    final txt = _msgCtrl.text.trim();
    if (txt.isEmpty || _sendingMsg) return;
    setState(() => _sendingMsg = true);
    try {
      final msg = await _repo.sendMessage(txt);
      _msgCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _lastMessageId = msg.id;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sendingMsg = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      body: SafeArea(
        child: s == null
            ? const Center(child: CircularProgressIndicator(color: FerxgoColors.brand))
            : s.hasActive
                ? _buildActive(s, s.active!)
                : s.hasOffer
                    ? _buildOffer(s, s.offer!)
                    : _buildIdle(s),
      ),
    );
  }

  // ─── IDLE (dashboard) ─────────────────────────────────────
  Widget _buildIdle(DriverState s) {
    final d = s.driver;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Merhaba, ${d.name}',
                style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 22, fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Profil',
              onPressed: () => context.push(AppRoutes.profile),
              icon: const Icon(Icons.account_circle_outlined, color: FerxgoColors.textMid),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Online durum kartı
        _OnlineCard(
          online: s.isOnline,
          busy: _busy,
          onToggle: _busy ? null : () => _toggleOnline(!s.isOnline),
        ),
        const SizedBox(height: 16),

        // İstatistikler
        Row(
          children: [
            Expanded(child: _StatTile(
              icon: Icons.star, iconColor: FerxgoColors.brand,
              value: d.rating > 0 ? d.rating.toStringAsFixed(1) : '—', label: 'Puan',
            )),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(
              icon: Icons.route, iconColor: FerxgoColors.info,
              value: '${d.totalRides}', label: 'Yolculuk',
            )),
          ],
        ),
        const SizedBox(height: 16),

        // Görünürlük/hizmet çapı
        _ServiceRadiusCard(
          value: (_radiusDraft ?? d.serviceRadiusKm).clamp(2.0, 20.0),
          busy: _radiusBusy,
          onChanged: (v) => setState(() => _radiusDraft = v),
          onChangeEnd: _setRadius,
        ),
        const SizedBox(height: 20),

        if (_error != null) ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FerxgoColors.inkSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FerxgoColors.line),
          ),
          child: Row(
            children: [
              Icon(s.isOnline ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                color: s.isOnline ? FerxgoColors.success : FerxgoColors.textLow),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.isOnline
                      ? 'Çevrimiçisin. Yeni talepler burada görünecek.'
                      : 'Çevrimdışısın. Talep almak için çevrimiçi ol.',
                  style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── OFFER (gelen teklif) ─────────────────────────────────
  Widget _buildOffer(DriverState s, DriverOffer offer) {
    final neg = offer.negotiation;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 72, height: 72,
                child: Stack(alignment: Alignment.center, children: [
                  const CircularProgressIndicator(strokeWidth: 5, color: FerxgoColors.brand, backgroundColor: FerxgoColors.inkMuted),
                  Text('${offer.secondsRemaining}',
                    style: const TextStyle(color: FerxgoColors.brand, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Yeni yolculuk teklifi',
            textAlign: TextAlign.center,
            style: TextStyle(color: FerxgoColors.textHigh, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),

          // Ücret vurgusu
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: FerxgoColors.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.45)),
            ),
            child: Column(
              children: [
                const Text('Yolcunun teklifi', style: TextStyle(color: FerxgoColors.textMid, fontSize: 13)),
                const SizedBox(height: 4),
                Text('${offer.customerOffer.toStringAsFixed(0)} ₺',
                  style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 40, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Rota
          _RouteRow(icon: Icons.circle_outlined, color: FerxgoColors.brand, text: offer.pickupAddress),
          const SizedBox(height: 6),
          _RouteRow(icon: Icons.place, color: FerxgoColors.danger, text: offer.dropoffAddress),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.route, color: FerxgoColors.textLow, size: 15),
              const SizedBox(width: 4),
              Text('${offer.distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13)),
              const SizedBox(width: 16),
              const Icon(Icons.timer_outlined, color: FerxgoColors.textLow, size: 15),
              const SizedBox(width: 4),
              Text('~${offer.durationMinutes} dk',
                style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13)),
            ],
          ),

          const Spacer(),
          if (_error != null) ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
          const SizedBox(height: 8),

          FilledButton.icon(
            onPressed: _busy ? null : () => _acceptOffer(offer),
            icon: const Icon(Icons.check_circle),
            label: Text('Kabul et · ${offer.customerOffer.toStringAsFixed(0)} ₺'),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 54)),
          ),
          const SizedBox(height: 8),
          if (neg != null && neg.hasRoundsLeft)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _counterOffer(offer),
              icon: const Icon(Icons.swap_vert),
              label: const Text('Karşı teklif ver'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => _rejectOffer(offer),
            child: const Text('Reddet', style: TextStyle(color: FerxgoColors.danger)),
          ),
        ],
      ),
    );
  }

  // ─── ACTIVE (aktif yolculuk) ──────────────────────────────
  /// Harici navigasyon (Google Maps / varsayılan) — hedefe kilitli sesli yol tarifi.
  /// Başlamadıysa buluşma noktası, başladıysa varış noktası.
  Future<void> _openNavigation(DriverActive a) async {
    final target = (a.started ? a.dropoffPosition : null) ?? a.pickupPosition;
    final lat = target.latitude.toStringAsFixed(6);
    final lng = target.longitude.toStringAsFixed(6);
    // Önce Google Maps turn-by-turn (intent), yoksa evrensel yol tarifi linki.
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    try {
      if (await canLaunchUrl(navUri)) {
        await launchUrl(navUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navigasyon uygulaması açılamadı.')));
      }
    }
  }

  Widget _buildActive(DriverState s, DriverActive a) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: a.pickupPosition,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.ferxgo',
              maxZoom: 19,
            ),
            MarkerLayer(markers: [
              Marker(
                point: a.pickupPosition,
                width: 60, height: 60,
                child: const Icon(Icons.person_pin_circle, color: FerxgoColors.brand, size: 40),
              ),
              if (_myPosition != null)
                Marker(
                  point: _myPosition!,
                  width: 50, height: 50,
                  child: const Icon(Icons.local_taxi, color: FerxgoColors.info, size: 32),
                ),
            ]),
          ],
        ),
        // Acil yardım (panik) butonu — sol üstte
        Positioned(
          top: 12, left: 14,
          child: PanicButton(
            ridePublicId: a.publicId,
            shareDescription: 'Yolcu: ${a.customerName}. '
                'Güzergah: ${a.pickupAddress} → ${a.dropoffAddress}.',
          ),
        ),
        // Navigasyonu Aç — sağ üstte (hedefe kilitli harici navigasyon)
        Positioned(
          top: 12, right: 14,
          child: Material(
            color: FerxgoColors.brand,
            borderRadius: BorderRadius.circular(14),
            elevation: 4,
            child: InkWell(
              onTap: () => _openNavigation(a),
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.navigation, color: Colors.black, size: 18),
                    SizedBox(width: 6),
                    Text('Navigasyon',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ),

        DraggableScrollableSheet(
          initialChildSize: _chatOpen ? 0.7 : 0.42,
          minChildSize: 0.28,
          maxChildSize: 0.85,
          builder: (ctx, sc) => Container(
            decoration: const BoxDecoration(
              color: FerxgoColors.inkSoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                top: BorderSide(color: FerxgoColors.line),
                left: BorderSide(color: FerxgoColors.line),
                right: BorderSide(color: FerxgoColors.line),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(width: 36, height: 4, decoration: BoxDecoration(color: FerxgoColors.line, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                _ActiveHeader(
                  active: a, chatOpen: _chatOpen,
                  onChat: () => setState(() => _chatOpen = !_chatOpen),
                  onCall: () => startCallFor(ref, (publicId: a.publicId, peerName: a.customerName)),
                ),
                const Divider(color: FerxgoColors.line, height: 20),
                if (_error != null) Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
                ),
                Expanded(
                  child: _chatOpen
                      ? _DriverChat(scroll: _msgScroll, messages: _messages)
                      : _ActiveActions(active: a, busy: _busy, scroll: sc,
                          onArrived: () => _arrivedThenCode(),
                          onNoShow: () => _confirmNoShow(),
                          onComplete: () => _confirmComplete(),
                          onStart: () => _startWithCode(),
                          onCancelRide: () => _confirmCancelActive(),
                        ),
                ),
                if (_chatOpen) _DriverMessageInput(
                  controller: _msgCtrl, sending: _sendingMsg, onSend: _sendMessage,
                ),
              ],
            ),
          ),
        ),
        // Uygulama-içi sesli arama overlay (gelen çağrı + aktif görüşme)
        CallOverlay(publicId: a.publicId, peerName: a.customerName),
      ],
    );
  }

  Future<void> _confirmNoShow() async {
    final ok = await _confirm('Yolcu gelmedi mi?',
        'No-show bildirimi yolcunun güven puanını etkiler. Emin misin?', 'Gelmedi bildir', FerxgoColors.danger);
    if (ok != true) return;
    final loc = _myPosition;
    await _runActive(() => _repo.reportNoShow(lat: loc?.latitude, lng: loc?.longitude));
  }

  /// "Vardım" → varış kaydedilir, hemen ardından kod giriş ekranı açılır.
  Future<void> _arrivedThenCode() async {
    await _runActive(_repo.markArrived);
    if (mounted) await _startWithCode();
  }

  /// Eşleşme kodu ile yolculuğu başlat — yolcunun 4 haneli kodunu gir.
  Future<void> _startWithCode() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) {
        String? err;
        return StatefulBuilder(
          builder: (dctx, setD) {
            Future<void> submit() async {
              final code = ctrl.text.trim();
              if (code.length != 4) {
                setD(() => err = 'Kod 4 haneli olmalı.');
                return;
              }
              try {
                await _repo.startWithCode(code);
                if (dctx.mounted) Navigator.pop(dctx, true);
              } on ApiException catch (e) {
                setD(() => err = e.message);
              }
            }

            return AlertDialog(
              backgroundColor: FerxgoColors.inkSoft,
              title: const Text('Yolculuğu başlat',
                style: TextStyle(color: FerxgoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w800)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Yolcunun uygulamasındaki 4 haneli eşleşme kodunu gir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 4,
                    style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 14),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••',
                      hintStyle: const TextStyle(color: FerxgoColors.textLow, letterSpacing: 14),
                      filled: true,
                      fillColor: FerxgoColors.ink,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (_) { if (err != null) setD(() => err = null); },
                    onSubmitted: (_) => submit(),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Text(err!, textAlign: TextAlign.center,
                      style: const TextStyle(color: FerxgoColors.danger, fontSize: 13)),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Vazgeç')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: FerxgoColors.success, foregroundColor: Colors.white),
                  onPressed: submit,
                  child: const Text('Başlat'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true) await _poll();
  }

  Future<void> _confirmCancelActive() async {
    final ok = await _confirm('Yolculuğu iptal et?',
        'Aktif yolculuk iptal edilecek ve tekrar çevrimiçi olacaksın. Emin misin?',
        'Yolculuğu iptal et', FerxgoColors.danger);
    if (ok != true) return;
    await _runActive(_repo.cancelActive);
  }

  Future<void> _confirmComplete() async {
    final ok = await _confirm('Yolculuğu tamamla?',
        'Yolculuğun bittiğini onaylıyor musun?', 'Tamamla', FerxgoColors.success);
    if (ok != true) return;
    await _runActive(_repo.completeRide);
  }

  Future<bool?> _confirm(String title, String body, String cta, Color color) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FerxgoColors.inkSoft,
        title: Text(title, style: const TextStyle(color: FerxgoColors.textHigh)),
        content: Text(body, style: const TextStyle(color: FerxgoColors.textMid)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: Text(cta),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Alt widget'lar
// ─────────────────────────────────────────────────────────────
class _OnlineCard extends StatelessWidget {
  const _OnlineCard({required this.online, required this.busy, required this.onToggle});
  final bool online;
  final bool busy;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: online
            ? const LinearGradient(colors: [Color(0xFF16351F), Color(0xFF14141B)])
            : null,
        color: online ? null : FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: online ? FerxgoColors.success.withValues(alpha: 0.5) : FerxgoColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: online ? FerxgoColors.success : FerxgoColors.textLow,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(online ? 'Çevrimiçi' : 'Çevrimdışı',
                style: TextStyle(
                  color: online ? FerxgoColors.success : FerxgoColors.textMid,
                  fontSize: 16, fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onToggle,
            style: FilledButton.styleFrom(
              backgroundColor: online ? FerxgoColors.inkMuted : FerxgoColors.brand,
              foregroundColor: online ? FerxgoColors.textHigh : Colors.black,
              minimumSize: const Size(double.infinity, 52),
            ),
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: FerxgoColors.brand))
                : Text(online ? 'Çevrimdışı ol' : 'Çevrimiçi ol'),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.iconColor, required this.value, required this.label});
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FerxgoColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Görünürlük/hizmet çapı kartı — 2..20 km slider (0.5 adım).
class _ServiceRadiusCard extends StatelessWidget {
  const _ServiceRadiusCard({
    required this.value,
    required this.busy,
    required this.onChanged,
    required this.onChangeEnd,
  });
  final double value;
  final bool busy;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final label = value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FerxgoColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location, color: FerxgoColors.brand, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Görünürlük çapım',
                  style: TextStyle(color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text('$label km',
                style: const TextStyle(color: FerxgoColors.brand, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Yalnızca çevrende bu mesafedeki yolculara görünür ve eşleşirsin.',
            style: TextStyle(color: FerxgoColors.textLow, fontSize: 12, height: 1.3)),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: FerxgoColors.brand,
              inactiveTrackColor: FerxgoColors.inkMuted,
              thumbColor: FerxgoColors.brand,
              overlayColor: FerxgoColors.brand.withValues(alpha: 0.15),
              valueIndicatorColor: FerxgoColors.brand,
            ),
            child: Slider(
              value: value,
              min: 2,
              max: 20,
              divisions: 36, // 0.5 km adım
              label: '$label km',
              onChanged: busy ? null : onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('2 km', style: TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
                Text('20 km', style: TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
          style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 14, height: 1.3),
          maxLines: 2, overflow: TextOverflow.ellipsis,
        )),
      ],
    );
  }
}

class _ActiveHeader extends StatelessWidget {
  const _ActiveHeader({required this.active, required this.chatOpen, required this.onChat, required this.onCall});
  final VoidCallback onCall;
  final DriverActive active;
  final bool chatOpen;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: FerxgoColors.brand.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(26),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.person, color: FerxgoColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(active.customerName,
                  style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 17, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: active.customerIsNew ? FerxgoColors.info.withValues(alpha: 0.18) : FerxgoColors.success.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(active.customerTrustLabel.isNotEmpty ? active.customerTrustLabel : (active.customerIsNew ? 'Yeni yolcu' : 'Yolcu'),
                        style: TextStyle(
                          color: active.customerIsNew ? FerxgoColors.info : FerxgoColors.success,
                          fontSize: 11, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${active.customerCompletedRides} yolculuk',
                      style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                onPressed: onCall,
                icon: const Icon(Icons.call),
                tooltip: 'Ara',
                style: IconButton.styleFrom(
                  backgroundColor: FerxgoColors.success.withValues(alpha: 0.2),
                  foregroundColor: FerxgoColors.success,
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                onPressed: onChat,
                icon: Icon(chatOpen ? Icons.close : Icons.chat_bubble_outline),
                tooltip: chatOpen ? 'Kapat' : 'Mesaj',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveActions extends StatelessWidget {
  const _ActiveActions({
    required this.active,
    required this.busy,
    required this.scroll,
    required this.onArrived,
    required this.onNoShow,
    required this.onComplete,
    required this.onStart,
    required this.onCancelRide,
  });
  final DriverActive active;
  final bool busy;
  final ScrollController scroll;
  final VoidCallback onArrived;
  final VoidCallback onNoShow;
  final VoidCallback onComplete;
  final VoidCallback onStart;
  final VoidCallback onCancelRide;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        // Rota özeti
        _RouteRow(icon: Icons.circle_outlined, color: FerxgoColors.brand, text: active.pickupAddress),
        const SizedBox(height: 6),
        _RouteRow(icon: Icons.place, color: FerxgoColors.danger, text: active.dropoffAddress),
        const SizedBox(height: 16),

        if (!active.started) ...[
          if (!active.arrived) ...[
            // 1) Önce buluşma noktasına varış bildir → yolcunun kodu görünür
            FilledButton.icon(
              onPressed: busy ? null : onArrived,
              icon: const Icon(Icons.emoji_flags),
              label: const Text('Buluşma noktasına vardım'),
              style: FilledButton.styleFrom(
                backgroundColor: FerxgoColors.brand, foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 54),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Vardığında bildir; yolcunun ekranında eşleşme kodu belirir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
          ] else ...[
            // 2) Vardı → yolcudan kodu al, gir, başlat
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: FerxgoColors.inkMuted, borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: FerxgoColors.success, size: 20),
                  SizedBox(width: 10),
                  Expanded(child: Text('Buluşma noktasındasın. Yolcudan 4 haneli kodu iste.',
                    style: TextStyle(color: FerxgoColors.textMid, fontSize: 13))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ANA AKSİYON — eşleşme kodu ile yolculuğu başlat
            FilledButton.icon(
              onPressed: busy ? null : onStart,
              icon: const Icon(Icons.vpn_key),
              label: const Text('Yolculuğu başlat'),
              style: FilledButton.styleFrom(
                backgroundColor: FerxgoColors.success, foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Yolcunun söylediği 4 haneli kodu girerek başlat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
          ],
          const SizedBox(height: 10),

          if (!active.confirmed)
            OutlinedButton.icon(
              onPressed: (busy || !active.noShowButtonReady) ? null : onNoShow,
              icon: const Icon(Icons.person_off, color: FerxgoColors.danger),
              label: Text(
                active.noShowButtonReady
                    ? 'Yolcu gelmedi'
                    : 'Yolcu gelmedi (${active.noShowCountdownSec ?? 0} sn)',
                style: const TextStyle(color: FerxgoColors.danger),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: FerxgoColors.danger),
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
        ] else ...[
          // Yolculuk başladı → sürüyor
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FerxgoColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.navigation, color: FerxgoColors.success, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('Yolculuk sürüyor. İyi yolculuklar!',
                  style: TextStyle(color: FerxgoColors.textMid, fontSize: 13))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : onComplete,
            icon: const Icon(Icons.flag_circle),
            label: const Text('Yolculuğu tamamla'),
            style: FilledButton.styleFrom(
              backgroundColor: FerxgoColors.success, foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ],

        // Kaçış: yolculuk BAŞLAMADAN önce takılan/iptal gereken talebi kapat.
        // Başladıktan sonra iptal yok — yalnızca "Tamamla".
        if (!active.started) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: busy ? null : onCancelRide,
            icon: const Icon(Icons.close, color: FerxgoColors.danger, size: 18),
            label: const Text('Yolculuğu iptal et', style: TextStyle(color: FerxgoColors.danger)),
          ),
        ],
      ],
    );
  }
}

class _DriverChat extends StatelessWidget {
  const _DriverChat({required this.scroll, required this.messages});
  final ScrollController scroll;
  final List<RideMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(20),
        child: Text('Yolcuyla iletişim için mesaj yaz.',
          style: TextStyle(color: FerxgoColors.textLow), textAlign: TextAlign.center),
      ));
    }
    final df = DateFormat('HH:mm');
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final m = messages[i];
        final isMe = m.isDriver;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? FerxgoColors.brand : FerxgoColors.inkMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.body, style: TextStyle(color: isMe ? Colors.black : FerxgoColors.textHigh, fontSize: 14)),
                const SizedBox(height: 2),
                Text(df.format(m.createdAt.toLocal()),
                  style: TextStyle(color: isMe ? Colors.black54 : FerxgoColors.textLow, fontSize: 10)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DriverMessageInput extends StatelessWidget {
  const _DriverMessageInput({required this.controller, required this.sending, required this.onSend});
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + MediaQuery.of(context).viewInsets.bottom),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1, maxLines: 4,
              style: const TextStyle(color: FerxgoColors.textHigh),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Mesaj yaz…',
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: sending ? null : onSend,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
            ),
            child: sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.send, size: 20),
          ),
        ],
      ),
    );
  }
}
