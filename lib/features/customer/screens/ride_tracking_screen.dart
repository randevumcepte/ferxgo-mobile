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
import '../customer_ride_repository.dart';
import '../models/nearby_driver.dart';
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
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {}
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FerxgoColors.inkSoft,
        title: const Text('Talebi iptal et?', style: TextStyle(color: FerxgoColors.textHigh)),
        content: const Text(
          'Sürücü bulma süreci durdurulacak. Onaylıyor musun?',
          style: TextStyle(color: FerxgoColors.textMid),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FerxgoColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('İptal et'),
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

  // ─── 1:1 reddedilince: aynı teklifi TÜM favorilere gönder ─
  Future<void> _resendToAllFavorites() async {
    final snap = ref.read(lastDispatchProvider);
    if (snap == null) { context.go(AppRoutes.customerHome); return; }
    setState(() => _busyAction = true);
    try {
      final res = await ref.read(customerRideRepositoryProvider).createRequest(
        vehicleClassSlug: snap.vehicleClassSlug,
        pickupAddress: snap.pickupAddress,
        pickupPosition: snap.pickupPosition,
        dropoffAddress: snap.dropoffAddress,
        dropoffPosition: snap.dropoffPosition,
        distanceKm: snap.distanceKm,
        durationMinutes: snap.durationMinutes,
        estimatedFare: snap.estimatedFare,
        suggestedFare: snap.estimatedFare,
        customerOfferFare: snap.offerFare ?? snap.estimatedFare,
        dispatchMode: 'auto',
        fallbackDriverIds: const [],
      );
      // Yeni talep auto — tekrar reddedilirse resend teklif etme
      ref.read(lastDispatchProvider.notifier).state = null;
      if (!mounted) return;
      context.go('${AppRoutes.customerRideBase}/${res.publicId}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
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
    if (s.isExpired) {
      // 1:1 (seçili favoriye) gönderilip reddedildiyse → tüm favorilere teklif et
      final snap = ref.read(lastDispatchProvider);
      final canResend = snap != null && snap.wasManual;
      return _Terminal(
        icon: Icons.hourglass_disabled,
        title: canResend ? 'Sürücü kabul etmedi' : 'Sürücü bulunamadı',
        message: canResend
            ? 'Seçtiğin sürücü teklifini kabul etmedi.\nAynı teklifi tüm favori sürücülerine gönderebilirsin.'
            : 'Çevredeki sürücüler talebini cevaplamadı.\nTekrar deneyebilirsin.',
        ctaText: canResend ? 'Tüm favorilerime gönder' : 'Ana ekrana dön',
        onTap: canResend
            ? (_busyAction ? null : _resendToAllFavorites)
            : () => context.go(AppRoutes.customerHome),
        color: FerxgoColors.warning,
        secondaryText: canResend ? 'Ana ekrana dön' : null,
        onSecondary: canResend ? () => context.go(AppRoutes.customerHome) : null,
      );
    }
    if (s.isCancelled || s.isExhausted) {
      return _Terminal(
        icon: Icons.cancel_outlined,
        title: s.isExhausted ? 'Sürücü bulunamadı' : 'Talep iptal edildi',
        message: s.isExhausted
            ? 'Uygun sürücü çıkmadı. Tekrar deneyebilirsin.'
            : 'Talebin iptal edildi.',
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
    return _Accepted(
      status: s,
      mapController: _map,
      focus: _focus,
      messages: _messages,
      msgCtrl: _msgCtrl,
      msgScroll: _msgScroll,
      sendingMsg: _sendingMsg,
      onSend: _send,
      chatOpen: _chatOpen,
      onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
      onConfirm: _busyAction ? null : _confirmArrival,
      onCancel: _busyAction ? null : _cancel,
      busyAction: _busyAction,
      error: _error,
      onErrorClose: () => setState(() => _error = null),
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
    required this.mapController,
    required this.focus,
    required this.messages,
    required this.msgCtrl,
    required this.msgScroll,
    required this.sendingMsg,
    required this.onSend,
    required this.chatOpen,
    required this.onToggleChat,
    required this.onConfirm,
    required this.onCancel,
    required this.busyAction,
    required this.error,
    required this.onErrorClose,
  });

  final RideStatus status;
  final MapController mapController;
  final LatLng focus;
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
    final confirmed = status.customerConfirmedAt != null;

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
            MarkerLayer(markers: [
              Marker(
                point: driver.position,
                width: 60, height: 60,
                child: const Icon(Icons.local_taxi, color: FerxgoColors.brand, size: 36),
              ),
            ]),
          ],
        ),
        // Üst durum şeridi
        Positioned(
          top: 12, left: 12, right: 12,
          child: _StatusStrip(
            text: confirmed
                ? 'Yolculuk başladı'
                : arrived
                    ? 'Sürücü vardı — buluştuğunda "geldim" e bas'
                    : 'Sürücü yola çıktı',
          ),
        ),

        // Alt panel
        DraggableScrollableSheet(
          initialChildSize: chatOpen ? 0.7 : 0.34,
          minChildSize: 0.22,
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
                _DriverHeader(driver: driver, onChat: onToggleChat, chatOpen: chatOpen),
                const Divider(color: FerxgoColors.line, height: 24),

                if (error != null) Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ErrorBanner(message: error!, onClose: onErrorClose),
                ),

                Expanded(
                  child: chatOpen
                      ? _ChatPanel(scroll: msgScroll, messages: messages)
                      : _ActionsPanel(
                          arrived: arrived,
                          confirmed: confirmed,
                          onConfirm: onConfirm,
                          onCancel: onCancel,
                          scroll: sc,
                          busy: busyAction,
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

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FerxgoColors.ink.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FerxgoColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_filled, color: FerxgoColors.brand, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
            style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w700, fontSize: 13),
          )),
        ],
      ),
    );
  }
}

class _DriverHeader extends StatelessWidget {
  const _DriverHeader({required this.driver, required this.onChat, required this.chatOpen});
  final NearbyDriver driver;
  final VoidCallback onChat;
  final bool chatOpen;

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
                Text(driver.fullName,
                  style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 17, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (driver.vehicleClass != null) driver.vehicleClass,
                    if (driver.plate != null) driver.plate,
                  ].whereType<String>().join(' · '),
                  style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onChat,
            icon: Icon(chatOpen ? Icons.close : Icons.chat_bubble_outline),
            tooltip: chatOpen ? 'Kapat' : 'Mesaj',
          ),
        ],
      ),
    );
  }
}

class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel({
    required this.arrived,
    required this.confirmed,
    required this.onConfirm,
    required this.onCancel,
    required this.scroll,
    required this.busy,
  });
  final bool arrived;
  final bool confirmed;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final ScrollController scroll;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        if (arrived && !confirmed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check_circle),
              label: const Text('Sürücüyü gördüm'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            ),
          )
        else if (confirmed)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.check, color: FerxgoColors.success),
                SizedBox(width: 8),
                Text('Buluştun, yolculuk başladı.', style: TextStyle(color: FerxgoColors.textMid)),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: confirmed || busy ? null : onCancel,
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
