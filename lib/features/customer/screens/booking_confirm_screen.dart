import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/price_stepper.dart';
import '../customer_ride_repository.dart';
import '../models/nearby_driver.dart';
import '../models/vehicle_class.dart';
import '../state/booking_draft.dart';

/// Vehicle class + fiyat + sürücü seçimi + KVKK + "Talep gönder".
/// Dropoff seçildikten sonra açılır.
class BookingConfirmScreen extends ConsumerStatefulWidget {
  const BookingConfirmScreen({super.key});

  @override
  ConsumerState<BookingConfirmScreen> createState() => _BookingConfirmScreenState();
}

class _BookingConfirmScreenState extends ConsumerState<BookingConfirmScreen> {
  bool _busyFare = false;
  bool _busySubmit = false;
  String? _error;
  bool _kvkk = false;

  NearbyResult? _nearby;
  int? _selectedDriverId;
  VehicleClassRef? _selectedClass;

  /// Yolcunun teklif ettiği ücret (inDrive tarzı). Fiyat hesaplanınca öneriyle
  /// başlatılır, ±%40 band içinde −/+ ile ayarlanır.
  double? _offerFare;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final draft = ref.read(bookingDraftProvider);
    if (draft.pickup == null || draft.dropoff == null) {
      // Eksik veri → adım sıfır
      if (mounted) context.go(AppRoutes.customerHome);
      return;
    }

    // Pickup→dropoff yaklaşık mesafe (haversine) + 2.4x dakika
    final km = _haversineKm(draft.pickup!.position, draft.dropoff!.position);
    final mins = math.max(1, (km * 2.4 + 0.8).round());
    ref.read(bookingDraftProvider.notifier).setRoute(distanceKm: km, durationMinutes: mins);

    // Vehicle class'lar + yakındaki sürücüler paralel
    final repo = ref.read(customerRideRepositoryProvider);
    try {
      final classes = await ref.read(vehicleClassesProvider.future);
      final nearby = await repo.nearbyDrivers(
        lat: draft.pickup!.position.latitude,
        lng: draft.pickup!.position.longitude,
        limit: 6,
      );
      if (!mounted) return;
      setState(() {
        _selectedClass = classes.firstWhere(
          (c) => c.slug == 'easy',
          orElse: () => classes.first,
        );
        _nearby = nearby;
        _selectedDriverId = nearby.drivers.isNotEmpty ? nearby.drivers.first.id : null;
      });
      await _refreshFare();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Bilgiler yüklenemedi.');
    }
  }

  Future<void> _refreshFare() async {
    final draft = ref.read(bookingDraftProvider);
    final vc = _selectedClass;
    if (vc == null || draft.distanceKm == null || draft.durationMinutes == null) return;

    setState(() => _busyFare = true);
    try {
      final fare = await ref.read(customerRideRepositoryProvider).calculateFare(
        vehicleClassId: vc.id,
        distanceKm: draft.distanceKm!,
        durationMinutes: draft.durationMinutes!,
      );
      // FareCalculator → 'total_fare' anahtarı (subtotal + extras_total)
      final total = (fare['total_fare'] as num?)?.toDouble();
      ref.read(bookingDraftProvider.notifier).setRoute(
        distanceKm: draft.distanceKm!,
        durationMinutes: draft.durationMinutes!,
        fare: total,
      );
      // Teklif önerilen ücretle başlasın (araç sınıfı değişince yeniden hizala)
      if (total != null && mounted) {
        setState(() => _offerFare = total.roundToDouble());
      }
    } catch (_) {
      // fare opsiyonel — sessizce geç
    } finally {
      if (mounted) setState(() => _busyFare = false);
    }
  }

  /// [auto] true → "Hadi Gidelim": sürücü seçmeden favori-öncelikli otomatik dağıtım.
  /// false → manuel: seçilen sürücüye (preferred) + fallback'ler.
  Future<void> _submit({required bool auto}) async {
    final draft = ref.read(bookingDraftProvider);
    if (!_kvkk) {
      setState(() => _error = 'KVKK onayını işaretlemen gerekiyor.');
      return;
    }
    if (!auto && _selectedDriverId == null) {
      setState(() => _error = 'Bir sürücü seç ya da "Hadi Gidelim" ile otomatik gönder.');
      return;
    }
    if (_selectedClass == null || !draft.hasRoute) return;

    setState(() { _busySubmit = true; _error = null; });
    try {
      final fallback = auto
          ? const <int>[]
          : (_nearby?.drivers ?? const <NearbyDriver>[])
              .map((d) => d.id)
              .where((id) => id != _selectedDriverId)
              .take(5)
              .toList();

      final res = await ref.read(customerRideRepositoryProvider).createRequest(
        vehicleClassSlug: _selectedClass!.slug,
        pickupAddress: draft.pickup!.displayName,
        pickupPosition: draft.pickup!.position,
        dropoffAddress: draft.dropoff!.displayName,
        dropoffPosition: draft.dropoff!.position,
        distanceKm: draft.distanceKm!,
        durationMinutes: draft.durationMinutes!,
        estimatedFare: draft.estimatedFare,
        suggestedFare: draft.estimatedFare,
        customerOfferFare: _offerFare ?? draft.estimatedFare,
        dispatchMode: auto ? 'auto' : null,
        preferredDriverId: auto ? null : _selectedDriverId,
        fallbackDriverIds: fallback,
      );

      if (!mounted) return;
      ref.read(bookingDraftProvider.notifier).reset();
      context.go('${AppRoutes.customerRideBase}/${res.publicId}');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Talep gönderilemedi.');
    } finally {
      if (mounted) setState(() => _busySubmit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final classesAsync = ref.watch(vehicleClassesProvider);

    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(
        backgroundColor: FerxgoColors.ink,
        title: const Text('Talebi onayla'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.customerBookDropoff),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Rota kartı
            _RouteCard(
              pickup: draft.pickup?.displayName ?? '—',
              dropoff: draft.dropoff?.displayName ?? '—',
              distanceKm: draft.distanceKm,
              durationMinutes: draft.durationMinutes,
            ),
            const SizedBox(height: 18),

            // Vehicle class chip'leri
            const Text('Araç sınıfı',
              style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            classesAsync.when(
              loading: () => const SizedBox(height: 56, child: Center(child: CircularProgressIndicator(color: FerxgoColors.brand))),
              error: (_, _) => const Text('Araç sınıfları yüklenemedi', style: TextStyle(color: FerxgoColors.danger)),
              data: (classes) => Wrap(
                spacing: 8, runSpacing: 8,
                children: classes.map((c) {
                  final selected = c.id == _selectedClass?.id;
                  return _ClassChip(
                    label: c.name,
                    selected: selected,
                    onTap: () async {
                      setState(() => _selectedClass = c);
                      await _refreshFare();
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),

            // Önerilen ücret (çapa)
            _FareBlock(
              fare: draft.estimatedFare,
              loading: _busyFare,
            ),
            const SizedBox(height: 12),

            // Yolcu teklifi (inDrive tarzı pazarlık) — öneri ±%40
            if (draft.estimatedFare != null && _offerFare != null)
              PriceStepper(
                label: 'Yolculuk teklifin',
                value: _offerFare!,
                min: (draft.estimatedFare! * 0.6).roundToDouble(),
                max: (draft.estimatedFare! * 1.4).roundToDouble(),
                step: 10,
                hint: 'Sürücü kabul edebilir ya da karşı teklif verebilir.',
                onChanged: (v) => setState(() => _offerFare = v),
              ),
            const SizedBox(height: 18),

            // Sürücü seçimi (opsiyonel — "Hadi Gidelim" için gerekmez)
            const Text('Sürücü seç (opsiyonel)',
              style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_nearby == null)
              const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: FerxgoColors.brand)))
            else if (_nearby!.drivers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Çevrede şu an müsait sürücü yok.', style: TextStyle(color: FerxgoColors.textLow)),
              )
            else
              Column(
                children: _nearby!.drivers.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DriverRadio(
                    driver: d,
                    selected: d.id == _selectedDriverId,
                    onTap: () => setState(() => _selectedDriverId = d.id),
                  ),
                )).toList(),
              ),

            const SizedBox(height: 12),

            // KVKK
            InkWell(
              onTap: () => setState(() => _kvkk = !_kvkk),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Checkbox(
                      value: _kvkk,
                      onChanged: (v) => setState(() => _kvkk = v ?? false),
                      activeColor: FerxgoColors.brand,
                      checkColor: Colors.black,
                    ),
                    const Expanded(
                      child: Text(
                        'KVKK Aydınlatma Metni ve Kullanım Şartları\'nı okudum, kabul ediyorum.',
                        style: TextStyle(color: FerxgoColors.textMid, fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            if (_error != null) ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
            const SizedBox(height: 12),

            // Birincil: Hadi Gidelim (favori-öncelikli otomatik dağıtım)
            FilledButton.icon(
              onPressed: _busySubmit ? null : () => _submit(auto: true),
              icon: _busySubmit
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                  : const Text('🔥', style: TextStyle(fontSize: 18)),
              label: const Text('Hadi Gidelim'),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Favori sürücülerin öncelikli; yoksa en yakın müsait sürücü',
                textAlign: TextAlign.center,
                style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11),
              ),
            ),
            const SizedBox(height: 10),

            // İkincil: seçili sürücüye gönder (manuel)
            OutlinedButton.icon(
              onPressed: (_busySubmit || _selectedDriverId == null) ? null : () => _submit(auto: false),
              icon: const Icon(Icons.person_pin, size: 18),
              label: const Text('Sadece seçili sürücüye gönder'),
            ),
          ],
        ),
      ),
    );
  }
}

double _haversineKm(LatLng a, LatLng b) {
  const r = 6371.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
  final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
  final lat1 = a.latitude * math.pi / 180.0;
  final lat2 = b.latitude * math.pi / 180.0;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2)
      + math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.durationMinutes,
  });
  final String pickup;
  final String dropoff;
  final double? distanceKm;
  final int? durationMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FerxgoColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(Icons.circle_outlined, FerxgoColors.brand, pickup),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: SizedBox(height: 14, child: VerticalDivider(color: FerxgoColors.line, width: 1, thickness: 1)),
          ),
          _row(Icons.place, FerxgoColors.danger, dropoff),
          if (distanceKm != null && durationMinutes != null) ...[
            const SizedBox(height: 10),
            const Divider(color: FerxgoColors.line, height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.route, color: FerxgoColors.textLow, size: 14),
                const SizedBox(width: 4),
                Text('${distanceKm!.toStringAsFixed(1)} km',
                  style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.timer_outlined, color: FerxgoColors.textLow, size: 14),
                const SizedBox(width: 4),
                Text('~$durationMinutes dk',
                  style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, Color color, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: color, size: 14)),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
            style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 13, height: 1.35),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          )),
        ],
      );
}

class _ClassChip extends StatelessWidget {
  const _ClassChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? FerxgoColors.brand : FerxgoColors.inkMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? FerxgoColors.brand : FerxgoColors.line),
        ),
        child: Text(label,
          style: TextStyle(
            color: selected ? Colors.black : FerxgoColors.textHigh,
            fontWeight: FontWeight.w700, fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _FareBlock extends StatelessWidget {
  const _FareBlock({required this.fare, required this.loading});
  final double? fare;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FerxgoColors.brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments, color: FerxgoColors.brand),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Önerilen ücret',
              style: TextStyle(color: FerxgoColors.textMid, fontSize: 13),
            ),
          ),
          if (loading)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: FerxgoColors.brand))
          else
            Text(
              fare != null ? '${fare!.toStringAsFixed(0)} ₺' : '—',
              style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 20, fontWeight: FontWeight.w800),
            ),
        ],
      ),
    );
  }
}

class _DriverRadio extends StatelessWidget {
  const _DriverRadio({required this.driver, required this.selected, required this.onTap});
  final NearbyDriver driver;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FerxgoColors.brand.withValues(alpha: 0.12) : FerxgoColors.inkSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? FerxgoColors.brand : FerxgoColors.line,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? FerxgoColors.brand : FerxgoColors.textLow,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(driver.name,
                          style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        )),
                        const SizedBox(width: 6),
                        const Icon(Icons.star, color: FerxgoColors.brand, size: 13),
                        const SizedBox(width: 2),
                        Text(driver.rating.toStringAsFixed(1),
                          style: const TextStyle(color: FerxgoColors.textMid, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (driver.vehicleClass != null) driver.vehicleClass,
                        if (driver.vehicleLabel != null && driver.vehicleLabel!.isNotEmpty) driver.vehicleLabel,
                      ].whereType<String>().join(' · '),
                      style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${driver.etaMinutes} dk',
                    style: const TextStyle(color: FerxgoColors.brand, fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  Text('${driver.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
