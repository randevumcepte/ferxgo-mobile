import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../../../core/location/location_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/negotiation.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/price_stepper.dart';
import '../../call/call_overlay.dart';
import '../../safety/panic_button.dart';
import '../customer_ride_repository.dart';
import '../models/nearby_driver.dart';
import '../models/place.dart';
import '../models/ride_status.dart';
import '../state/booking_draft.dart';

/// Talep sonrası ana tracking ekranı.
///  - 2 sn polling /customer/ride-requests/{publicId}
///  - state: pending → kuyrukta beklemekte, currentIndex/total + kalan süre
///           accepted → harita + sürücü pin + chat + vardım onayı
///           expired/cancelled → terminal mesaj + ana ekrana dön
class RideTrackingScreen extends ConsumerStatefulWidget {
  const RideTrackingScreen({super.key, required this.publicId});

  final String publicId;

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen> {
  final MapController _map = MapController();
  Timer? _statusTimer;
  Timer? _messageTimer;

  RideStatus? _status;
  String? _error;
  bool _busyAction = false;
  bool _visualVerifyShown = false; // araç/sürücü doğrulama modalı bir kez açılsın

  // Gerçek yol rotası (OSRM) — sürücü → hedef. Sürücü ~200m hareket edince yenilenir.
  List<LatLng>? _routePoints;
  double? _routeKm;
  int? _routeMin;
  LatLng? _routeAnchor; // rotanın çekildiği sürücü konumu
  bool _routeStartedTarget = false; // rota, başlamış hedefe (dropoff) göre mi
  bool _routeBusy = false;

  // Sohbet
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _msgScroll = ScrollController();
  final List<RideMessage> _messages = [];
  int _lastMessageId = 0;
  bool _sendingMsg = false;
  bool _chatOpen = false;

  // Harita merkezi — pickup ya da sürücü konumu
  LatLng get _focus =>
      _status?.acceptedDriver?.position ??
      _status?.offeredDriver?.position ??
      LocationService.defaultCenter;

  @override
  void initState() {
    super.initState();
    _pollStatus();
    _statusTimer = Timer.periodic(AppConfig.ridePollInterval, (_) => _pollStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _messageTimer?.cancel();
    _msgCtrl.dispose();
    _msgScroll.dispose();
    super.dispose();
  }

  Future<void> _pollStatus() async {
    try {
      final s = await ref.read(customerRideRepositoryProvider).showRequest(
            widget.publicId,
            LocationService.defaultCenter,
          );
      if (!mounted) return;
      setState(() {
        _status = s;
        _error = null;
      });
      // Accepted'a geçince mesaj polling'i de başlat
      if (s.isAccepted && _messageTimer == null) {
        _pollMessages();
        _messageTimer = Timer.periodic(AppConfig.ridePollInterval, (_) => _pollMessages());
      }
      // Yolculuk başladıktan sonra araç/sürücü görsel doğrulaması (bir kez)
      if (s.needsVisualVerify && !_visualVerifyShown) {
        _visualVerifyShown = true;
        _showVisualVerify(s);
      }
      // Gerçek yol rotasını çek/yenile (sürücü hareket edince)
      _maybeRefreshRoute(s);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {}
  }

  /// Sürücü konumu ~200m değişince ya da hedef değişince gerçek yol rotasını yenile.
  void _maybeRefreshRoute(RideStatus s) {
    final driver = s.acceptedDriver;
    if (driver == null || _routeBusy) return;
    final target = s.isStarted ? (s.dropoffPosition ?? s.pickupPosition) : s.pickupPosition;
    if (target == null) return;

    final needsRefresh = _routePoints == null ||
        _routeStartedTarget != s.isStarted ||
        _routeAnchor == null ||
        const Distance().as(LengthUnit.Meter, _routeAnchor!, driver.position) > 200;
    if (!needsRefresh) return;

    _refreshRoute(driver.position, target, s.isStarted);
  }

  Future<void> _refreshRoute(LatLng from, LatLng to, bool startedTarget) async {
    _routeBusy = true;
    try {
      final res = await ref.read(customerRideRepositoryProvider).route(from: from, to: to);
      if (res == null || !mounted) return;
      setState(() {
        _routePoints = res.points;
        _routeKm = res.distanceKm;
        _routeMin = res.durationMin;
        _routeAnchor = from;
        _routeStartedTarget = startedTarget;
      });
    } finally {
      _routeBusy = false;
    }
  }

  /// Yolculuk başladıktan sonra "bindiğim araç/sürücü doğru mu?" doğrulaması.
  Future<void> _showVisualVerify(RideStatus s) async {
    final drv = s.acceptedDriver;
    if (drv == null || !mounted) {
      _visualVerifyShown = false;
      return;
    }

    final match = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: FerxgoColors.inkSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: FerxgoColors.brand, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text('Bindiğin araç bu mu?',
              style: TextStyle(color: FerxgoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w800))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: FerxgoColors.inkMuted,
                    backgroundImage: (drv.avatar != null && drv.avatar!.isNotEmpty) ? NetworkImage(drv.avatar!) : null,
                    child: (drv.avatar == null || drv.avatar!.isEmpty)
                        ? const Icon(Icons.person, color: FerxgoColors.textMid) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(drv.name,
                          style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w800, fontSize: 16)),
                        if (drv.vehicleLabel != null && drv.vehicleLabel!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(drv.vehicleLabel!,
                              style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13)),
                          ),
                        if (drv.plate != null && drv.plate!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: FerxgoColors.brand.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: FerxgoColors.brand),
                            ),
                            child: Text(drv.plate!,
                              style: const TextStyle(color: FerxgoColors.brand, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 15)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (drv.vehiclePhotos.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Araç fotoğrafları', style: TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: drv.vehiclePhotos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        drv.vehiclePhotos[i],
                        width: 124, height: 90, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 124, height: 90, color: FerxgoColors.inkMuted,
                          child: const Icon(Icons.directions_car, color: FerxgoColors.textLow),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text('Araçtaki plaka ve fotoğraflarla karşılaştır. Güvenliğin için önemli.',
                style: TextStyle(color: FerxgoColors.textLow, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: FerxgoColors.success, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Evet, doğru', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hayır, eşleşmiyor — bildir',
                    style: TextStyle(color: FerxgoColors.danger, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (match == null) {
      _visualVerifyShown = false;
      return;
    }
    await _submitVisualVerify(match);
  }

  Future<void> _submitVisualVerify(bool match) async {
    try {
      final res = await ref.read(customerRideRepositoryProvider).visualVerify(widget.publicId, match);
      if (!mounted) return;
      final msg = (res['message'] as String?) ?? (match ? 'İyi yolculuklar!' : 'Bildirimin alındı.');
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: match ? FerxgoColors.success : FerxgoColors.danger,
        ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _visualVerifyShown = false; // hata → tekrar denenebilsin
      });
    }
  }

  Future<void> _pollMessages() async {
    try {
      final list = await ref.read(customerRideRepositoryProvider)
          .messages(widget.publicId, sinceId: _lastMessageId);
      if (list.isEmpty || !mounted) return;
      setState(() {
        _messages.addAll(list);
        _lastMessageId = list.last.id;
      });
      // Sohbet açıksa en alta kaydır
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_msgScroll.hasClients) {
          _msgScroll.animateTo(
            _msgScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _send() async {
    final txt = _msgCtrl.text.trim();
    if (txt.isEmpty || _sendingMsg) return;
    setState(() => _sendingMsg = true);
    try {
      final msg = await ref.read(customerRideRepositoryProvider).sendMessage(widget.publicId, txt);
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

  Future<void> _cancel() async {
    // Sürücü anlaşıldıysa (accepted) iptal cezaya tabi → güzel dille uyar.
    final accepted = _status?.isAccepted ?? false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FerxgoColors.inkSoft,
        title: Row(
          children: [
            Icon(accepted ? Icons.report_gmailerrorred : Icons.help_outline,
              color: accepted ? FerxgoColors.warning : FerxgoColors.textMid, size: 22),
            const SizedBox(width: 8),
            Text(accepted ? 'Yolculuğu iptal et?' : 'Talebi iptal et?',
              style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 17)),
          ],
        ),
        content: accepted
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sürücün seni almak için yola çıktı. Şimdi iptal edersen sürücünün emeği boşa gider.',
                    style: TextStyle(color: FerxgoColors.textMid, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FerxgoColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: FerxgoColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: FerxgoColors.warning, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'Eşleşme sonrası iptal, iptal cezasına tabidir. Ceza, kayıtlı kredi kartından '
                          'otomatik tahsil edilir; çekilemezse borç bakiyene eklenir ve ödenene kadar '
                          'yeni yolculuk oluşturamazsın. Gerçekten gerekmedikçe iptal etmeni önermeyiz.',
                          style: TextStyle(color: FerxgoColors.textMid, fontSize: 12, height: 1.4),
                        )),
                      ],
                    ),
                  ),
                ],
              )
            : const Text(
                'Sürücü bulma süreci durdurulacak. Onaylıyor musun?',
                style: TextStyle(color: FerxgoColors.textMid),
              ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: FerxgoColors.brand,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(accepted ? 'Vazgeçtim, beklerim' : 'Vazgeç',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: FerxgoColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(accepted ? 'Yine de iptal et' : 'Talebi iptal et',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busyAction = true);
    try {
      await ref.read(customerRideRepositoryProvider).cancelRequest(widget.publicId, LocationService.defaultCenter);
      if (!mounted) return;
      context.go(AppRoutes.customerHome);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _confirmArrival() async {
    setState(() => _busyAction = true);
    try {
      await ref.read(customerRideRepositoryProvider).confirmRequest(widget.publicId);
      await _pollStatus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  // ─── Fiyat pazarlığı: sürücü karşı teklif verdi ───────────
  Future<void> _acceptPrice() async {
    setState(() => _busyAction = true);
    try {
      final s = await ref.read(customerRideRepositoryProvider)
          .acceptPrice(widget.publicId, LocationService.defaultCenter);
      if (!mounted) return;
      setState(() => _status = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _counterPrice(Negotiation neg) async {
    final start = neg.driverCounterFare ?? neg.currentPrice ?? neg.suggestedFare ?? 0;
    final min = neg.minFare ?? (start * 0.6).roundToDouble();
    final max = neg.maxFare ?? (start * 1.4).roundToDouble();
    var draft = start.roundToDouble().clamp(min, max);

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
              Text('Sürücü ${(neg.driverCounterFare ?? 0).toStringAsFixed(0)} ₺ istedi',
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
                child: const Text('Teklifi gönder'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;
    setState(() => _busyAction = true);
    try {
      await ref.read(customerRideRepositoryProvider).counterPrice(widget.publicId, result);
      await _pollStatus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  // ─── Auto/havuz: eşleşen sürücüyü onayla/reddet ───────────
  Future<void> _reconfirm(bool accept) async {
    if (!accept) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: FerxgoColors.inkSoft,
          title: const Text('Sürücüyü reddet?', style: TextStyle(color: FerxgoColors.textHigh)),
          content: const Text('Bu sürücüyü onaylamazsan talep iptal edilir.',
              style: TextStyle(color: FerxgoColors.textMid)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: FerxgoColors.danger, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reddet'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busyAction = true);
    try {
      final s = await ref.read(customerRideRepositoryProvider)
          .reconfirm(widget.publicId, accept, LocationService.defaultCenter);
      if (!mounted) return;
      setState(() => _status = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  // ─── Reddedilince/bulunamayınca: adres+ücret HAZIR onay ekranına geri dön.
  // Yolcu baştan adres girmesin — hemen başka sürücü seçsin ya da tekrar yollasın.
  void _backToBooking() {
    final snap = ref.read(lastDispatchProvider);
    if (snap == null) { context.go(AppRoutes.customerHome); return; }
    ref.read(bookingDraftProvider.notifier).restore(
      pickup: Place(position: snap.pickupPosition, displayName: snap.pickupAddress),
      dropoff: Place(position: snap.dropoffPosition, displayName: snap.dropoffAddress),
      distanceKm: snap.distanceKm,
      durationMinutes: snap.durationMinutes,
      fare: snap.estimatedFare,
    );
    context.go(AppRoutes.customerBookConfirm);
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;

    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(
        backgroundColor: FerxgoColors.ink,
        title: const Text('Yolculuk'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go(AppRoutes.customerHome),
        ),
      ),
      body: SafeArea(
        child: s == null
            ? const Center(child: CircularProgressIndicator(color: FerxgoColors.brand))
            : _build(s),
      ),
    );
  }

  Widget _build(RideStatus s) {
    // Sürücü reddetti / bulunamadı → ana sayfaya ATMA. Adres+ücret hazır onay
    // ekranına dön; yolcu hemen başka sürücü seçsin ya da tekrar yollasın.
    if (s.isExpired || s.isExhausted) {
      final canRetry = ref.read(lastDispatchProvider) != null;
      return _Terminal(
        icon: Icons.person_search,
        title: 'Sürücü kabul etmedi',
        message: 'Adresin ve teklifin hazır duruyor.\nBaşka bir sürücü seçebilir ya da teklifini tekrar gönderebilirsin.',
        ctaText: canRetry ? 'Tekrar dene · başka sürücü' : 'Ana ekrana dön',
        onTap: canRetry ? _backToBooking : () => context.go(AppRoutes.customerHome),
        color: FerxgoColors.warning,
        secondaryText: canRetry ? 'Ana ekrana dön' : null,
        onSecondary: canRetry ? () => context.go(AppRoutes.customerHome) : null,
      );
    }
    if (s.isCancelled) {
      return _Terminal(
        icon: Icons.cancel_outlined,
        title: 'Talep iptal edildi',
        message: 'Talebin iptal edildi.',
        ctaText: 'Ana ekrana dön',
        onTap: () => context.go(AppRoutes.customerHome),
        color: FerxgoColors.danger,
      );
    }
    if (s.isAwaitingReconfirm) {
      return _Reconfirm(
        status: s,
        busy: _busyAction,
        onAccept: _busyAction ? null : () => _reconfirm(true),
        onDecline: _busyAction ? null : () => _reconfirm(false),
        error: _error,
        onErrorClose: () => setState(() => _error = null),
      );
    }
    if (s.isSearching) {
      return _Pending(
        status: s,
        onCancel: _busyAction ? null : _cancel,
        onAcceptPrice: _busyAction ? null : _acceptPrice,
        onCounterPrice: _busyAction ? null : () => _counterPrice(s.negotiation!),
        error: _error,
        onErrorClose: () => setState(() => _error = null),
      );
    }
    // Güvenlik: accepted ama sürücü bilgisi henüz gelmediyse arama ekranı göster
    if (s.acceptedDriver == null) {
      return _Pending(
        status: s,
        onCancel: _busyAction ? null : _cancel,
        onAcceptPrice: null,
        onCounterPrice: null,
        error: _error,
        onErrorClose: () => setState(() => _error = null),
      );
    }
    // accepted
    final drv = s.acceptedDriver;
    final driverName = drv == null
        ? 'Sürücü'
        : (drv.fullName.isNotEmpty ? drv.fullName : drv.name);
    final callArg = (publicId: widget.publicId, peerName: driverName);
    return Stack(
      children: [
        _Accepted(
          status: s,
          publicId: widget.publicId,
          mapController: _map,
          focus: _focus,
          routePoints: _routePoints,
          routeKm: _routeKm,
          routeMin: _routeMin,
          messages: _messages,
          msgCtrl: _msgCtrl,
          msgScroll: _msgScroll,
          sendingMsg: _sendingMsg,
          onSend: _send,
          chatOpen: _chatOpen,
          onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
          onConfirm: _busyAction ? null : _confirmArrival,
          onCancel: _busyAction ? null : _cancel,
          onCall: () => startCallFor(ref, callArg),
          busyAction: _busyAction,
          error: _error,
          onErrorClose: () => setState(() => _error = null),
        ),
        // Uygulama-içi sesli arama (gelen çağrı da burada yakalanır)
        CallOverlay(publicId: widget.publicId, peerName: driverName),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  PENDING (arama / kuyruk)
// ─────────────────────────────────────────────────────────────
class _Pending extends StatelessWidget {
  const _Pending({
    required this.status,
    required this.onCancel,
    required this.onAcceptPrice,
    required this.onCounterPrice,
    required this.error,
    required this.onErrorClose,
  });
  final RideStatus status;
  final VoidCallback? onCancel;
  final VoidCallback? onAcceptPrice;
  final VoidCallback? onCounterPrice;
  final String? error;
  final VoidCallback onErrorClose;

  @override
  Widget build(BuildContext context) {
    final neg = status.negotiation;
    final awaitingDecision = status.awaitingCustomerPriceDecision && neg != null;

    final percentLeft = status.totalCandidates == 0
        ? 0.0
        : ((status.currentIndex + 1) / status.totalCandidates).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 84, height: 84,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: awaitingDecision ? null : percentLeft,
                    strokeWidth: 5,
                    backgroundColor: FerxgoColors.inkMuted,
                    color: FerxgoColors.brand,
                  ),
                  if (!awaitingDecision)
                    Text('${status.secondsRemaining}',
                      style: const TextStyle(color: FerxgoColors.brand, fontSize: 22, fontWeight: FontWeight.w800),
                    )
                  else
                    const Icon(Icons.handshake, color: FerxgoColors.brand, size: 30),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            awaitingDecision
                ? 'Sürücü karşı teklif verdi'
                : status.isPoolExpanded
                    ? (status.isFavoriteWave ? 'Favori sürücülerine soruldu' : 'Yakındaki sürücülere soruldu')
                    : status.offeredDriver != null
                        ? 'Teklif gönderildi: ${status.offeredDriver!.name}'
                        : 'Sürücü aranıyor…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            awaitingDecision
                ? 'Kabul et, karşı teklif ver ya da vazgeç.'
                : status.isPoolExpanded
                    ? 'Teklifini kabul eden ilk sürücü seninle eşleştirilecek.'
                    : status.totalCandidates > 0
                        ? 'Aday ${status.currentIndex + 1}/${status.totalCandidates}'
                        : 'Çevredeki sürücülere haber veriliyor.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: FerxgoColors.textLow, fontSize: 13),
          ),

          if (awaitingDecision) ...[
            const SizedBox(height: 20),
            _NegotiationCard(neg: neg),
          ],

          const Spacer(),
          if (error != null) ErrorBanner(message: error!, onClose: onErrorClose),
          const SizedBox(height: 12),

          if (awaitingDecision) ...[
            FilledButton.icon(
              onPressed: onAcceptPrice,
              icon: const Icon(Icons.check_circle),
              label: Text('Kabul et · ${(neg.driverCounterFare ?? 0).toStringAsFixed(0)} ₺'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            ),
            const SizedBox(height: 8),
            if (neg.hasRoundsLeft)
              OutlinedButton.icon(
                onPressed: onCounterPrice,
                icon: const Icon(Icons.swap_vert),
                label: const Text('Karşı teklif ver'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              ),
            const SizedBox(height: 8),
          ],

          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close, color: FerxgoColors.danger),
            label: const Text('Talebi iptal et', style: TextStyle(color: FerxgoColors.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: FerxgoColors.danger),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pazarlık özet kartı: senin teklifin ↔ sürücünün karşı teklifi.
class _NegotiationCard extends StatelessWidget {
  const _NegotiationCard({required this.neg});
  final Negotiation neg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _priceCol(
                  'Senin teklifin',
                  neg.customerOfferFare,
                  FerxgoColors.textMid,
                ),
              ),
              const Icon(Icons.arrow_forward, color: FerxgoColors.textLow, size: 18),
              Expanded(
                child: _priceCol(
                  'Sürücü istiyor',
                  neg.driverCounterFare,
                  FerxgoColors.brand,
                ),
              ),
            ],
          ),
          if (neg.roundsLeft >= 0) ...[
            const SizedBox(height: 10),
            Text('Kalan pazarlık hakkı: ${neg.roundsLeft}',
              style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _priceCol(String label, double? value, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value != null ? '${value.toStringAsFixed(0)} ₺' : '—',
            style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────
//  RECONFIRM (auto/havuz: eşleşen sürücüyü onayla/reddet)
// ─────────────────────────────────────────────────────────────
class _Reconfirm extends StatelessWidget {
  const _Reconfirm({
    required this.status,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.error,
    required this.onErrorClose,
  });
  final RideStatus status;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final String? error;
  final VoidCallback onErrorClose;

  @override
  Widget build(BuildContext context) {
    final driver = status.acceptedDriver;
    final neg = status.negotiation;
    final price = neg?.currentPrice ?? neg?.customerOfferFare;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: FerxgoColors.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.how_to_reg, color: FerxgoColors.success, size: 32),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Sürücü bulundu!',
            textAlign: TextAlign.center,
            style: TextStyle(color: FerxgoColors.textHigh, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            status.isFavoriteWave
                ? 'Favori sürücün teklifini kabul etti. Onaylıyor musun?'
                : 'Bir üye sürücü teklifini kabul etti. Onaylıyor musun?',
            textAlign: TextAlign.center,
            style: const TextStyle(color: FerxgoColors.textLow, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Sürücü kartı
          if (driver != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: FerxgoColors.inkSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: FerxgoColors.brand.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.person, color: FerxgoColors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driver.fullName.isNotEmpty ? driver.fullName : driver.name,
                          style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 16, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.star, color: FerxgoColors.brand, size: 13),
                            const SizedBox(width: 2),
                            Text(driver.rating.toStringAsFixed(1),
                              style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12)),
                            if (driver.vehicleClass != null) ...[
                              const SizedBox(width: 8),
                              Flexible(child: Text(driver.vehicleClass!,
                                style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12),
                                overflow: TextOverflow.ellipsis)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (price != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${price.toStringAsFixed(0)} ₺',
                          style: const TextStyle(color: FerxgoColors.brand, fontSize: 20, fontWeight: FontWeight.w900)),
                        const Text('anlaşılan',
                          style: TextStyle(color: FerxgoColors.textLow, fontSize: 10)),
                      ],
                    ),
                ],
              ),
            ),

          const Spacer(),
          if (error != null) ErrorBanner(message: error!, onClose: onErrorClose),
          const SizedBox(height: 8),

          FilledButton.icon(
            onPressed: onAccept,
            icon: const Icon(Icons.check_circle),
            label: Text(price != null ? 'Onayla · ${price.toStringAsFixed(0)} ₺' : 'Onayla'),
            style: FilledButton.styleFrom(
              backgroundColor: FerxgoColors.success, foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onDecline,
            icon: const Icon(Icons.close, color: FerxgoColors.danger),
            label: const Text('Reddet', style: TextStyle(color: FerxgoColors.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: FerxgoColors.danger),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ACCEPTED (harita + chat + vardım)
// ─────────────────────────────────────────────────────────────
class _Accepted extends StatelessWidget {
  const _Accepted({
    required this.status,
    required this.publicId,
    required this.mapController,
    required this.focus,
    this.routePoints,
    this.routeKm,
    this.routeMin,
    required this.messages,
    required this.msgCtrl,
    required this.msgScroll,
    required this.sendingMsg,
    required this.onSend,
    required this.chatOpen,
    required this.onToggleChat,
    required this.onConfirm,
    required this.onCancel,
    required this.onCall,
    required this.busyAction,
    required this.error,
    required this.onErrorClose,
  });

  final RideStatus status;
  final String publicId;
  final VoidCallback onCall;
  final MapController mapController;
  final LatLng focus;
  final List<LatLng>? routePoints;
  final double? routeKm;
  final int? routeMin;
  final List<RideMessage> messages;
  final TextEditingController msgCtrl;
  final ScrollController msgScroll;
  final bool sendingMsg;
  final VoidCallback onSend;
  final bool chatOpen;
  final VoidCallback onToggleChat;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool busyAction;
  final String? error;
  final VoidCallback onErrorClose;

  @override
  Widget build(BuildContext context) {
    final driver = status.acceptedDriver!;
    final arrived = status.arrivedAt != null;
    final started = status.isStarted; // eşleşme kodu doğrulandı → yolculuk başladı

    // Hedef: başladıysa VARIŞ noktası, değilse BULUŞMA noktası. ETA canlı konumdan.
    final pickup = status.pickupPosition;
    final dropoff = status.dropoffPosition;
    final target = started ? (dropoff ?? pickup) : pickup;
    const dist = Distance();
    int? etaMin;
    double? distKm; // hedefe kalan mesafe
    if (target != null) {
      distKm = dist.as(LengthUnit.Kilometer, driver.position, target);
      final raw = (distKm * 2.2 + 0.5).round();
      etaMin = raw < 1 ? 1 : raw;
    }
    // Gerçek yol rotası geldiyse kuş uçuşu yerine onu kullan (mesafe + süre).
    if (routeKm != null && routeKm! > 0) distKm = routeKm;
    if (routeMin != null && routeMin! > 0) etaMin = routeMin;

    // İlerleme yüzdesi (yolculuk başladıysa): kat edilen / toplam
    double? progress;
    if (started && dropoff != null && distKm != null) {
      final total = (status.tripDistanceKm != null && status.tripDistanceKm! > 0)
          ? status.tripDistanceKm!
          : dist.as(LengthUnit.Kilometer, pickup ?? driver.position, dropoff);
      if (total > 0) {
        final covered = (total - distKm).clamp(0.0, total);
        progress = (covered / total).clamp(0.0, 1.0);
      }
    }

    // Durum şeridi: renk + başlık + alt yazı
    final Color stColor;
    final String stTitle;
    final String stSub;
    final IconData stIcon;
    if (started) {
      stColor = FerxgoColors.success;
      stTitle = 'Yolculuk başladı';
      stSub = 'İyi yolculuklar!';
      stIcon = Icons.navigation;
    } else if (arrived) {
      stColor = FerxgoColors.warning;
      stTitle = 'Sürücü buluşma noktasında';
      stSub = 'Kodu sürücüye göster, yolculuk başlasın';
      stIcon = Icons.emoji_flags;
    } else {
      stColor = FerxgoColors.success;
      stTitle = 'Sürücü yola çıktı';
      stSub = etaMin != null ? '~$etaMin dk sonra yanında' : 'Sana doğru geliyor';
      stIcon = Icons.directions_car_filled;
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: focus,
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
            // Rota çizgisi: GERÇEK yol (OSRM) varsa onu çiz; yoksa düz çizgiye düş.
            if (routePoints != null && routePoints!.length >= 2)
              PolylineLayer(polylines: [
                Polyline(
                  points: routePoints!,
                  strokeWidth: started ? 6 : 4,
                  color: FerxgoColors.brand.withValues(alpha: started ? 0.95 : 0.7),
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.black38,
                ),
              ])
            else if (pickup != null && dropoff != null)
              PolylineLayer(polylines: [
                Polyline(
                  points: [pickup, dropoff],
                  strokeWidth: started ? 5 : 3,
                  color: (started ? FerxgoColors.brand : FerxgoColors.textLow)
                      .withValues(alpha: started ? 0.9 : 0.4),
                  borderStrokeWidth: 1,
                  borderColor: Colors.black26,
                ),
              ]),
            MarkerLayer(markers: [
              if (pickup != null)
                Marker(
                  point: pickup,
                  width: 40, height: 40,
                  child: Icon(started ? Icons.trip_origin : Icons.person_pin_circle,
                    color: started ? FerxgoColors.textMid : FerxgoColors.danger, size: started ? 22 : 34),
                ),
              // Varış noktası
              if (dropoff != null)
                Marker(
                  point: dropoff,
                  width: 40, height: 40,
                  child: const Icon(Icons.place, color: FerxgoColors.danger, size: 34),
                ),
              // Sürücünün canlı konumu — üstünde ismi (web pin'i gibi)
              Marker(
                point: driver.position,
                width: 140, height: 62,
                child: _DriverMapMarker(name: driver.name, etaMin: etaMin),
              ),
            ]),
          ],
        ),
        // Üst şerit: yolculuk başladıysa canlı ilerleme kartı, değilse durum şeridi
        Positioned(
          top: 12, left: 12, right: 12,
          child: started
              ? _ProgressStrip(etaMin: etaMin, remainingKm: distKm, progress: progress)
              : _StatusStrip(color: stColor, title: stTitle, subtitle: stSub, icon: stIcon),
        ),
        // Acil yardım (panik) butonu — durum şeridinin altında sağda
        Positioned(
          top: 86, right: 14,
          child: PanicButton(
            ridePublicId: publicId,
            shareDescription: 'Sürücü: ${driver.name}'
                '${driver.vehicleLabel != null ? ', ${driver.vehicleLabel}' : ''}'
                '${driver.plate != null ? ' (${driver.plate})' : ''}.',
          ),
        ),

        // Alt panel
        DraggableScrollableSheet(
          initialChildSize: chatOpen ? 0.7 : 0.40,
          minChildSize: 0.26,
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
                _DriverHeader(driver: driver, onChat: onToggleChat, chatOpen: chatOpen, onCall: onCall),
                if (!chatOpen) ...[
                  if (status.matchCode != null && !started) ...[
                    const SizedBox(height: 12),
                    _MatchCodeCard(code: status.matchCode!),
                  ],
                  const SizedBox(height: 10),
                  _RideInfoRow(etaMin: etaMin, distKm: distKm, arrived: arrived),
                ],
                const Divider(color: FerxgoColors.line, height: 20),

                if (error != null) Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ErrorBanner(message: error!, onClose: onErrorClose),
                ),

                Expanded(
                  child: chatOpen
                      ? _ChatPanel(scroll: msgScroll, messages: messages)
                      : _ActionsPanel(
                          onCancel: onCancel,
                          scroll: sc,
                          busy: busyAction,
                          started: started,
                        ),
                ),

                if (chatOpen) _MessageInput(
                  controller: msgCtrl,
                  sending: sendingMsg,
                  onSend: onSend,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Eşleşme kodu kartı — yolcuya gösterilir; sürücü buluşmada girince başlar.
class _MatchCodeCard extends StatelessWidget {
  const _MatchCodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [FerxgoColors.brand.withValues(alpha: 0.22), FerxgoColors.inkSoft],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('EŞLEŞME KODU',
                style: TextStyle(color: FerxgoColors.brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              SizedBox(height: 2),
              Text('Sürücüye göster',
                style: TextStyle(color: FerxgoColors.textMid, fontSize: 12)),
            ],
          ),
          const Spacer(),
          // Haneler ayrı kutularda — okunaklı
          Row(
            children: [
              for (final ch in code.split('')) ...[
                Container(
                  width: 38, height: 46,
                  margin: const EdgeInsets.only(left: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: FerxgoColors.ink,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.5)),
                  ),
                  child: Text(ch,
                    style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 24, fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Haritada sürücü konumu — üstünde isim + ETA (web pin'i gibi).
class _DriverMapMarker extends StatelessWidget {
  const _DriverMapMarker({required this.name, this.etaMin});
  final String name;
  final int? etaMin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: FerxgoColors.brand,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Text(
            etaMin != null ? '$name · $etaMin dk' : name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        const Icon(Icons.local_taxi, color: FerxgoColors.brand, size: 30),
      ],
    );
  }
}

/// Sürücü→buluşma ETA + mesafe (kabul ekranı bilgi satırı).
class _RideInfoRow extends StatelessWidget {
  const _RideInfoRow({required this.etaMin, required this.distKm, required this.arrived});
  final int? etaMin;
  final double? distKm;
  final bool arrived;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _cell(
            Icons.schedule,
            arrived ? 'Vardı' : (etaMin != null ? '~$etaMin dk' : '—'),
            arrived ? 'Buluşma' : 'Tahmini varış',
          )),
          const SizedBox(width: 10),
          Expanded(child: _cell(
            Icons.route,
            distKm != null ? '${distKm!.toStringAsFixed(1)} km' : '—',
            'Uzaklık',
          )),
        ],
      ),
    );
  }

  Widget _cell(IconData icon, String value, String label) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: FerxgoColors.inkMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: FerxgoColors.brand, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w800, fontSize: 15)),
                Text(label, style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
              ],
            ),
          ],
        ),
      );
}

/// Yolculuk başladıktan sonra üstte canlı ilerleme kartı:
/// pulsing 🚗 + "X dk kaldı" + kalan km + amber→yeşil gradient ilerleme çubuğu.
class _ProgressStrip extends StatefulWidget {
  const _ProgressStrip({required this.etaMin, required this.remainingKm, required this.progress});
  final int? etaMin;
  final double? remainingKm;
  final double? progress; // 0..1

  @override
  State<_ProgressStrip> createState() => _ProgressStripState();
}

class _ProgressStripState extends State<_ProgressStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eta = widget.etaMin;
    final km = widget.remainingKm;
    final pct = ((widget.progress ?? 0) * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [FerxgoColors.brand.withValues(alpha: 0.22), FerxgoColors.inkSoft.withValues(alpha: 0.96)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.4)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Pulsing araç ikonu
              SizedBox(
                width: 48, height: 48,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) {
                    final t = _pulse.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 30 + 18 * t, height: 30 + 18 * t,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: FerxgoColors.brand.withValues(alpha: (1 - t) * 0.35),
                          ),
                        ),
                        child!,
                      ],
                    );
                  },
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: FerxgoColors.brand.withValues(alpha: 0.20),
                      border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.6), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🚗', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HEDEFE DOĞRU',
                      style: TextStyle(color: FerxgoColors.brand, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2)),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(eta != null ? '$eta' : '—',
                          style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 28, fontWeight: FontWeight.w900, height: 1)),
                        const SizedBox(width: 5),
                        const Text('dk kaldı', style: TextStyle(color: FerxgoColors.textMid, fontSize: 13)),
                        const Spacer(),
                        if (km != null)
                          Text('${km.toStringAsFixed(1)} km',
                            style: const TextStyle(color: FerxgoColors.brand, fontSize: 14, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Gradient ilerleme çubuğu (amber → yeşil)
          Stack(
            children: [
              Container(
                height: 7,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              LayoutBuilder(
                builder: (_, c) => AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  height: 7,
                  width: c.maxWidth * (widget.progress ?? 0).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [FerxgoColors.brand, FerxgoColors.success]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Yolculuğun %$pct tamamlandı',
            style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.color, required this.title, required this.subtitle, required this.icon});
  final Color color;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.82)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                Text(subtitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverHeader extends StatelessWidget {
  const _DriverHeader({required this.driver, required this.onChat, required this.chatOpen, required this.onCall});
  final NearbyDriver driver;
  final VoidCallback onChat;
  final bool chatOpen;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    // Araç: "Marka Model · Yıl · N kişi" (plaka gösterilmez)
    final vehicleParts = <String>[
      if (driver.vehicleLabel != null && driver.vehicleLabel!.isNotEmpty) driver.vehicleLabel!,
      if (driver.vehicleYear != null) '${driver.vehicleYear}',
      if (driver.maxPassengers != null) '${driver.maxPassengers} kişi',
    ];

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
            child: const Icon(Icons.person, color: FerxgoColors.brand, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.fullName.isNotEmpty ? driver.fullName : driver.name,
                  style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 17, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star, color: FerxgoColors.brand, size: 13),
                    const SizedBox(width: 2),
                    Text(driver.rating.toStringAsFixed(1),
                      style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12, fontWeight: FontWeight.w600)),
                    if (driver.trips > 0) ...[
                      const SizedBox(width: 8),
                      Text('${driver.trips} yolculuk',
                        style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
                    ],
                  ],
                ),
                if (vehicleParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(vehicleParts.join(' · '),
                    style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Uygulama-içi sesli arama (WebRTC) + Mesaj
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _RoundBtn(icon: Icons.call, color: FerxgoColors.success, onTap: onCall, tooltip: 'Ara'),
          ),
          _RoundBtn(
            icon: chatOpen ? Icons.close : Icons.chat_bubble_outline,
            color: FerxgoColors.brand,
            onTap: onChat,
            tooltip: chatOpen ? 'Kapat' : 'Mesaj',
          ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.color, required this.onTap, required this.tooltip});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.16),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color, size: 21)),
        ),
      ),
    );
  }
}

class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel({
    required this.onCancel,
    required this.scroll,
    required this.busy,
    required this.started,
  });
  final VoidCallback? onCancel;
  final ScrollController scroll;
  final bool busy;
  final bool started;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        // Yolculuk başladıysa iptal yok — sadece "sürüyor" bilgisi.
        if (started)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.navigation, color: FerxgoColors.success, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Yolculuk sürüyor. İyi yolculuklar!',
                  style: TextStyle(color: FerxgoColors.textMid, fontSize: 13))),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: busy ? null : onCancel,
            icon: const Icon(Icons.close),
            label: const Text('Talebi iptal et'),
            style: OutlinedButton.styleFrom(
              foregroundColor: FerxgoColors.danger,
              side: const BorderSide(color: FerxgoColors.danger),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
      ],
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.scroll, required this.messages});
  final ScrollController scroll;
  final List<RideMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(20),
        child: Text('Sürücüyle iletişim için ilk mesajını yaz.',
          style: TextStyle(color: FerxgoColors.textLow), textAlign: TextAlign.center,
        ),
      ));
    }
    final df = DateFormat('HH:mm');
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final m = messages[i];
        final isMe = m.isCustomer;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: m.isSystem
                  ? FerxgoColors.inkMuted
                  : isMe
                      ? FerxgoColors.brand
                      : FerxgoColors.inkMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.body, style: TextStyle(
                  color: isMe ? Colors.black : FerxgoColors.textHigh,
                  fontSize: 14,
                )),
                const SizedBox(height: 2),
                Text(df.format(m.createdAt.toLocal()),
                  style: TextStyle(
                    color: isMe ? Colors.black54 : FerxgoColors.textLow,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageInput extends StatelessWidget {
  const _MessageInput({required this.controller, required this.sending, required this.onSend});
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

class _Terminal extends StatelessWidget {
  const _Terminal({
    required this.icon,
    required this.title,
    required this.message,
    required this.ctaText,
    required this.onTap,
    required this.color,
    this.secondaryText,
    this.onSecondary,
  });
  final IconData icon;
  final String title;
  final String message;
  final String ctaText;
  final VoidCallback? onTap;
  final Color color;
  final String? secondaryText;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 64),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: FerxgoColors.textMid, height: 1.4)),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: Text(ctaText),
          ),
          if (secondaryText != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onSecondary, child: Text(secondaryText!)),
          ],
        ],
      ),
    );
  }
}
