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

/// Teklif kaynağı sekmeleri (araç sınıfı yerine): Tümü / Favorilerim / Havuz / Kadın.
enum _SourceTab { all, favorites, pool, women }

/// Fiyat teklifi + kaynak seçimi (Tümü/Favori/Havuz/Kadın) + KVKK + gönder.
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

  /// Kaynak sekmesi — varsayılan Tümü (teklif herkese, ilk kabul eden alır).
  _SourceTab _tab = _SourceTab.all;

  /// Favori + yakındaki sürücüler (canlı durumla). Sekmelere göre listelenir.
  List<NearbyDriver>? _favorites;
  List<NearbyDriver>? _nearby;
  int? _selectedDriverId;   // tek sürücü (1:1)
  bool _selectAll = false;  // aktif sekmedeki tüm online sürücülere (havuz)
  VehicleClassRef? _selectedClass; // gizli — tek varsayılan sınıf

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

    // Tek varsayılan araç sınıfı (gizli) + favori + yakındaki sürücüler.
    final repo = ref.read(customerRideRepositoryProvider);
    try {
      final classes = await ref.read(vehicleClassesProvider.future);
      final favorites = await repo.favorites();
      final nearby = await repo.nearbyDrivers(
        lat: draft.pickup!.position.latitude,
        lng: draft.pickup!.position.longitude,
        limit: 10,
      );
      if (!mounted) return;
      setState(() {
        // İlk aktif sınıf sessizce kullanılır (tek tip — Martı gibi)
        _selectedClass = classes.isNotEmpty ? classes.first : null;
        _favorites = favorites;
        _nearby = nearby.drivers;
      });
      await _refreshFare();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Bilgiler yüklenemedi.');
    }
  }

  /// Aktif sekmenin sürücü listesi.
  List<NearbyDriver> _tabDrivers() {
    final favs = _favorites ?? const <NearbyDriver>[];
    final near = _nearby ?? const <NearbyDriver>[];
    switch (_tab) {
      case _SourceTab.all:
        return const [];
      case _SourceTab.favorites:
        return favs;
      case _SourceTab.pool:
        return near;
      case _SourceTab.women:
        // favori + yakın, kadın olanlar, id'ye göre tekilleştir
        final seen = <int>{};
        final out = <NearbyDriver>[];
        for (final d in [...favs, ...near]) {
          if (d.isFemale && seen.add(d.id)) out.add(d);
        }
        return out;
    }
  }

  void _switchTab(_SourceTab t) {
    setState(() {
      _tab = t;
      _selectedDriverId = null;
      _selectAll = false;
    });
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

  /// [mode]: 'one' → seçili sürücüye 1:1 (pazarlık); 'all' → Tümü (auto, favori-öncelikli
  ///         + havuz); 'pool' → aktif sekmedeki seçili sürücü listesi ([driverIds]);
  ///         'nearby' → favori olmayan yakın havuz (tracking escalation'da kullanılır).
  Future<void> _submit(String mode, {List<int>? driverIds}) async {
    final draft = ref.read(bookingDraftProvider);
    if (!_kvkk) {
      setState(() => _error = 'KVKK onayını işaretlemen gerekiyor.');
      return;
    }
    if (mode == 'one' && _selectedDriverId == null) {
      setState(() => _error = 'Bir sürücü seç ya da "Hepsine gönder"i kullan.');
      return;
    }
    if (mode == 'pool' && (driverIds == null || driverIds.isEmpty)) {
      setState(() => _error = 'Bu listede şu an müsait sürücü yok.');
      return;
    }
    if (_selectedClass == null || !draft.hasRoute) return;

    final dispatchMode = switch (mode) {
      'all' => 'auto',
      'nearby' => 'nearby',
      'pool' => 'pool',
      _ => null,
    };

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
        dispatchMode: dispatchMode,
        preferredDriverId: mode == 'one' ? _selectedDriverId : null,
        driverIds: mode == 'pool' ? driverIds : null,
        fallbackDriverIds: const [],
      );

      // Reddedilirse tracking bir sonraki kademeyi teklif etsin diye özet sakla
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
        stage: mode,
        favoriteCount: _favorites?.length ?? 0,
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

            // Yolcu teklifi (öneri çapa + inDrive pazarlık, ±%40)
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
            const SizedBox(height: 14),

            // Kaynak sekmeleri: Tümü (varsayılan) / Favorilerim / Havuz / Kadın
            _SourceTabs(current: _tab, onChanged: _switchTab),
            const SizedBox(height: 10),
            _buildTabContent(),

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

  String _emptyTabHint() => switch (_tab) {
        _SourceTab.favorites => 'Favori sürücün yok ya da şu an müsait değil.',
        _SourceTab.pool => 'Yakında şu an müsait sürücü yok.',
        _SourceTab.women => 'Yakında müsait kadın sürücü yok.',
        _SourceTab.all => '',
      };

  /// Aktif sekmenin içeriği — Tümü'de açıklama, diğerlerinde seçilebilir liste.
  Widget _buildTabContent() {
    if (_tab == _SourceTab.all) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FerxgoColors.brand.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.40)),
        ),
        child: const Row(
          children: [
            Icon(Icons.groups, color: FerxgoColors.brand),
            SizedBox(width: 10),
            Expanded(
              child: Text('Teklifin tüm müsait sürücülere aynı anda gider; ilk kabul eden yolculuğu alır.',
                style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, height: 1.35)),
            ),
          ],
        ),
      );
    }

    if (_favorites == null || _nearby == null) {
      return const SizedBox(height: 70, child: Center(child: CircularProgressIndicator(color: FerxgoColors.brand)));
    }

    final drivers = _tabDrivers();
    final onlineCount = drivers.where((d) => d.isOnline).length;

    if (drivers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FerxgoColors.inkMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FerxgoColors.line),
        ),
        child: Text(_emptyTabHint(),
          style: const TextStyle(color: FerxgoColors.textLow, fontSize: 13, height: 1.35)),
      );
    }

    return Column(
      children: [
        if (onlineCount > 1)
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => setState(() {
                _selectAll = !_selectAll;
                if (_selectAll) _selectedDriverId = null;
              }),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 6, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_selectAll ? Icons.check_box : Icons.check_box_outline_blank,
                      color: _selectAll ? FerxgoColors.brand : FerxgoColors.textLow, size: 18),
                    const SizedBox(width: 4),
                    Text('Hepsini seç',
                      style: TextStyle(
                        color: _selectAll ? FerxgoColors.brand : FerxgoColors.textMid,
                        fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ...drivers.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FavoriteRadio(
                driver: d,
                selected: _selectAll ? d.isOnline : d.id == _selectedDriverId,
                onTap: d.isOnline
                    ? () => setState(() { _selectedDriverId = d.id; _selectAll = false; })
                    : null,
              ),
            )),
      ],
    );
  }

  /// Gönder butonu — sekme + seçime göre.
  List<Widget> _buildDispatchButtons() {
    final spinner = _busySubmit
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
        : null;

    // Tümü → herkese (auto)
    if (_tab == _SourceTab.all) {
      return [
        FilledButton.icon(
          onPressed: _busySubmit ? null : () => _submit('all'),
          icon: spinner ?? const Text('🔥', style: TextStyle(fontSize: 18)),
          label: const Text('Tümüne gönder'),
        ),
        const SizedBox(height: 6),
        const Center(child: Text('Tüm müsait sürücülere gider, ilk kabul eden alır.',
          style: TextStyle(color: FerxgoColors.textLow, fontSize: 11))),
      ];
    }

    final drivers = _tabDrivers();
    final onlineIds = drivers.where((d) => d.isOnline).map((d) => d.id).toList();

    if (onlineIds.isEmpty) {
      return [
        const FilledButton(onPressed: null, child: Text('Müsait sürücü yok')),
        const SizedBox(height: 6),
        Center(child: Text(_emptyTabHint(),
          style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11))),
      ];
    }

    if (_selectAll) {
      return [
        FilledButton.icon(
          onPressed: _busySubmit ? null : () => _submit('pool', driverIds: onlineIds),
          icon: spinner ?? const Icon(Icons.groups),
          label: Text('Hepsine gönder (${onlineIds.length})'),
        ),
        const SizedBox(height: 6),
        const Center(child: Text('Seçilenlere aynı anda gider, ilk kabul eden alır.',
          style: TextStyle(color: FerxgoColors.textLow, fontSize: 11))),
      ];
    }

    return [
      FilledButton.icon(
        onPressed: (_busySubmit || _selectedDriverId == null) ? null : () => _submit('one'),
        icon: spinner ?? const Icon(Icons.send),
        label: Text(_selectedDriverId == null ? 'Önce bir sürücü seç' : 'Teklifi gönder'),
      ),
      const SizedBox(height: 6),
      const Center(child: Text('Seçtiğin sürücüyle birebir pazarlık',
        style: TextStyle(color: FerxgoColors.textLow, fontSize: 11))),
    ];
  }
}

/// Kaynak sekme çubuğu: Tümü / Favorilerim / Havuz / Kadın.
class _SourceTabs extends StatelessWidget {
  const _SourceTabs({required this.current, required this.onChanged});
  final _SourceTab current;
  final ValueChanged<_SourceTab> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_SourceTab.all, 'Tümü', Icons.groups),
      (_SourceTab.favorites, 'Favorilerim', Icons.favorite),
      (_SourceTab.pool, 'Havuz', Icons.hub),
      (_SourceTab.women, 'Kadın', Icons.face_3),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (tab, label, icon) = items[i];
          final sel = tab == current;
          return InkWell(
            onTap: () => onChanged(tab),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: sel ? FerxgoColors.brand : FerxgoColors.inkMuted,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? FerxgoColors.brand : FerxgoColors.line),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: sel ? Colors.black : FerxgoColors.textMid),
                  const SizedBox(width: 6),
                  Text(label,
                    style: TextStyle(
                      color: sel ? Colors.black : FerxgoColors.textHigh,
                      fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
          );
        },
      ),
    );
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
                          if (driver.vehicleLabel != null && driver.vehicleLabel!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(child: Text(driver.vehicleLabel!,
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
