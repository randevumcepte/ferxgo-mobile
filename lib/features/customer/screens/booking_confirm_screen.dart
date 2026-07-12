import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/json_num.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/price_stepper.dart';
import '../customer_ride_repository.dart';
import '../models/nearby_driver.dart';
import '../models/vehicle_class.dart';
import '../state/booking_draft.dart';
import '../widgets/driver_status_badge.dart';

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

  /// Favori sürücüler (canlı durumla). Otomatik seçim YOK — yolcu bilerek seçer.
  List<NearbyDriver>? _favorites;
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

    // Vehicle class'lar + FAVORİ sürücüler (canlı durumla). Otomatik seçim yok.
    final repo = ref.read(customerRideRepositoryProvider);
    try {
      final classes = await ref.read(vehicleClassesProvider.future);
      final favorites = await repo.favorites();
      if (!mounted) return;
      setState(() {
        _selectedClass = classes.firstWhere(
          (c) => c.slug == 'easy',
          orElse: () => classes.first,
        );
        _favorites = favorites;
        // _selectedDriverId BİLEREK null — yolcu kendi seçer
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
      final total = asDoubleOrNull(fare['total_fare']);
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

  /// [auto] true → tüm favorilere / yakındakilere (favori-öncelikli otomatik dağıtım).
  /// false → seçilen favoriye BİRE BİR (pazarlık için tek sürücü, fallback yok).
  Future<void> _submit({required bool auto}) async {
    final draft = ref.read(bookingDraftProvider);
    if (!_kvkk) {
      setState(() => _error = 'KVKK onayını işaretlemen gerekiyor.');
      return;
    }
    if (!auto && _selectedDriverId == null) {
      setState(() => _error = 'Bir favori sürücü seç ya da "Tüm favorilerime gönder"i kullan.');
      return;
    }
    if (_selectedClass == null || !draft.hasRoute) return;

    setState(() { _busySubmit = true; _error = null; });
    try {
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
        fallbackDriverIds: const [], // 1:1 saf pazarlık — yayma yok
      );

      // 1:1 reddedilirse tracking'de "Tüm favorilere gönder" için özet sakla
      ref.read(lastDispatchProvider.notifier).state = DispatchSnapshot(
        vehicleClassSlug: _selectedClass!.slug,
        pickupAddress: draft.pickup!.displayName,
        pickupPosition: draft.pickup!.position,
        dropoffAddress: draft.dropoff!.displayName,
        dropoffPosition: draft.dropoff!.position,
        distanceKm: draft.distanceKm!,
        durationMinutes: draft.durationMinutes!,
        estimatedFare: draft.estimatedFare,
        offerFare: _offerFare ?? draft.estimatedFare,
        wasManual: !auto,
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
          onPressed: () => context.go(AppRoutes.customerHome),
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
            const SizedBox(height: 12),

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
            const SizedBox(height: 12),

            // Yolcu teklifi (önerilen çapa hint'te + inDrive pazarlık, ±%40)
            if (draft.estimatedFare != null && _offerFare != null)
              PriceStepper(
                label: 'Yolculuk teklifin',
                value: _offerFare!,
                min: (draft.estimatedFare! * 0.6).roundToDouble(),
                max: (draft.estimatedFare! * 1.4).roundToDouble(),
                step: 10,
                dense: true,
                hint: 'Önerilen ${draft.estimatedFare!.toStringAsFixed(0)} ₺ · sürücü kabul/karşı teklif verebilir',
                onChanged: (v) => setState(() => _offerFare = v),
              )
            else if (_busyFare)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(color: FerxgoColors.brand)),
              ),
            const SizedBox(height: 12),

            // Favori sürücün — canlı durum; sadece müsait olan seçilebilir (birebir pazarlık)
            Row(
              children: [
                const Text('Favori sürücün',
                  style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text('Birini seç → birebir pazarlık',
                  style: TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            if (_favorites == null)
              const SizedBox(height: 70, child: Center(child: CircularProgressIndicator(color: FerxgoColors.brand)))
            else if (_favorites!.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FerxgoColors.inkMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: FerxgoColors.line),
                ),
                child: const Text(
                  'Henüz favori sürücün yok. Teklifini aşağıdan yakındaki müsait sürücülere gönderebilirsin.',
                  style: TextStyle(color: FerxgoColors.textLow, fontSize: 13, height: 1.35),
                ),
              )
            else
              Column(
                children: _favorites!.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FavoriteRadio(
                    driver: d,
                    selected: d.id == _selectedDriverId,
                    onTap: d.isOnline ? () => setState(() => _selectedDriverId = d.id) : null,
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

            ..._buildDispatchButtons(),
          ],
        ),
      ),
    );
  }

  /// Dağıtım butonları — online favori varsa 1:1 + tüm favoriler; yoksa yakındakiler.
  List<Widget> _buildDispatchButtons() {
    final favs = _favorites ?? const <NearbyDriver>[];
    final hasOnlineFav = favs.any((d) => d.isOnline);
    final hasFavorites = favs.isNotEmpty;

    final spinner = _busySubmit
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
        : null;

    if (hasOnlineFav) {
      return [
        // Birebir: seçili favoriye teklif (pazarlık)
        FilledButton.icon(
          onPressed: (_busySubmit || _selectedDriverId == null) ? null : () => _submit(auto: false),
          icon: spinner ?? const Icon(Icons.send),
          label: Text(_selectedDriverId == null ? 'Önce bir favori seç' : 'Teklifi gönder'),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text('Seçtiğin sürücüyle birebir pazarlık',
            style: TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
        ),
        const SizedBox(height: 10),
        // Hepsi: tüm online favorilere yay
        OutlinedButton.icon(
          onPressed: _busySubmit ? null : () => _submit(auto: true),
          icon: const Icon(Icons.groups, size: 18),
          label: const Text('Tüm favorilerime gönder'),
        ),
      ];
    }

    // Online favori yok → yakındaki müsait sürücülere
    return [
      FilledButton.icon(
        onPressed: _busySubmit ? null : () => _submit(auto: true),
        icon: spinner ?? const Text('🔥', style: TextStyle(fontSize: 18)),
        label: const Text('Yakındaki müsait sürücüye gönder'),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(
          hasFavorites ? 'Favori sürücülerin şu an müsait değil' : 'Henüz favori sürücün yok',
          style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11),
        ),
      ),
    ];
  }
}

/// Süreyi okunur biçimde göster: 60 dk'nın altında "~45 dk", üstünde "~1 sa 8 dk".
String _fmtDuration(int minutes) {
  if (minutes < 60) return '~$minutes dk';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '~$h sa' : '~$h sa $m dk';
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
                Text(_fmtDuration(durationMinutes!),
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

/// Favori sürücü seçim satırı — canlı durum rozeti; sadece müsait olan seçilebilir.
class _FavoriteRadio extends StatelessWidget {
  const _FavoriteRadio({required this.driver, required this.selected, required this.onTap});
  final NearbyDriver driver;
  final bool selected;
  final VoidCallback? onTap; // null → müsait değil, seçilemez

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          DriverStatusBadge(driver: driver),
                          if (driver.vehicleClass != null) ...[
                            const SizedBox(width: 8),
                            Flexible(child: Text(driver.vehicleClass!,
                              style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            )),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
