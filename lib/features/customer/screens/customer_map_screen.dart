import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/location/location_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../auth/auth_repository.dart';
import '../customer_ride_repository.dart';
import '../models/nearby_driver.dart';
import '../models/place.dart';
import '../state/booking_draft.dart';

class CustomerMapScreen extends ConsumerStatefulWidget {
  const CustomerMapScreen({super.key});

  @override
  ConsumerState<CustomerMapScreen> createState() => _CustomerMapScreenState();
}

class _CustomerMapScreenState extends ConsumerState<CustomerMapScreen> {
  final MapController _map = MapController();
  LatLng _center = LocationService.defaultCenter;
  bool _hasFix = false;
  bool _loadingDrivers = false;
  String? _locationError;
  String? _driversError;
  NearbyResult? _result;
  bool _womenOnlyFilter = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _resolveLocation();
    await _loadDrivers();
  }

  Future<void> _resolveLocation() async {
    final res = await ref.read(locationServiceProvider).currentPosition();
    if (!mounted) return;
    switch (res) {
      case LocationFix(:final position):
        setState(() {
          _center = position;
          _hasFix = true;
          _locationError = null;
        });
        _map.move(position, 14);
        // Booking draft'a pickup'ı yaz — onay ekranında kullanılacak
        ref.read(bookingDraftProvider.notifier).setPickupFromPosition(position);
      case LocationError(:final reason):
        setState(() => _locationError = reason.userMessage);
    }
  }

  void _startBooking() {
    if (!_hasFix) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Önce konumunu paylaş, sonra rota seçebiliriz.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FerogoColors.inkMuted,
        ));
      return;
    }
    // Pickup'ı garantiye al
    ref.read(bookingDraftProvider.notifier).setPickup(
      Place(position: _center, displayName: 'Mevcut konumum'),
    );
    context.push(AppRoutes.customerBookDropoff);
  }

  Future<void> _loadDrivers() async {
    setState(() { _loadingDrivers = true; _driversError = null; });
    try {
      final res = await ref.read(customerRideRepositoryProvider).nearbyDrivers(
        lat: _center.latitude,
        lng: _center.longitude,
        limit: 6,
      );
      if (!mounted) return;
      setState(() => _result = res);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _driversError = '[${e.statusCode}${e.code != null ? ' ${e.code}' : ''}] ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _driversError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingDrivers = false);
    }
  }

  void _replaceDriver(int id, NearbyDriver updated) {
    final res = _result;
    if (res == null) return;
    setState(() {
      _result = NearbyResult(
        drivers: res.drivers.map((x) => x.id == id ? updated : x).toList(growable: false),
        totalOnline: res.totalOnline,
      );
    });
  }

  /// Favori ekle/çıkar — iyimser güncelle, hata olursa geri al.
  Future<void> _toggleFavorite(NearbyDriver d) async {
    final repo = ref.read(customerRideRepositoryProvider);
    final wasFav = d.isFavorite;
    final nextCount = wasFav
        ? (d.favoriteCount > 0 ? d.favoriteCount - 1 : 0)
        : d.favoriteCount + 1;
    _replaceDriver(d.id, d.copyWith(isFavorite: !wasFav, favoriteCount: nextCount));
    try {
      if (wasFav) {
        await repo.removeFavorite(d.id);
      } else {
        await repo.addFavorite(d.id);
      }
    } catch (_) {
      if (mounted) _replaceDriver(d.id, d); // geri al
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value?.user;

    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: const Text('Ferogo'),
        backgroundColor: FerogoColors.ink,
        actions: [
          IconButton(
            tooltip: 'Geçmiş yolculuklar',
            onPressed: () => context.push(AppRoutes.customerHistory),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Çıkış',
            onPressed: () => ref.read(authRepositoryProvider).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── ÜST YARI: HARITA ─────────────────────────────
          Expanded(
            flex: 1,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 13,
                    minZoom: 9,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ferogo.ferogo_mobile',
                      maxZoom: 19,
                    ),
                    if (_hasFix)
                      MarkerLayer(markers: [
                        Marker(
                          point: _center,
                          width: 36, height: 36,
                          child: const _MeMarker(),
                        ),
                      ]),
                    if (_result != null)
                      MarkerLayer(
                        markers: _result!.drivers.map((d) => Marker(
                          point: d.position,
                          width: 60, height: 60,
                          child: _DriverPinIcon(driver: d),
                        )).toList(growable: false),
                      ),
                  ],
                ),

                // Üst bilgi rozetleri
                Positioned(
                  left: 12, right: 12, top: 12,
                  child: Row(
                    children: [
                      if (_locationError != null)
                        Expanded(child: ErrorBanner(
                          message: _locationError!,
                          onClose: () => setState(() => _locationError = null),
                        ))
                      else
                        _StatusChip(
                          icon: _hasFix ? Icons.my_location : Icons.location_searching,
                          text: _hasFix ? 'Konumun alındı' : 'Konum aranıyor…',
                        ),
                      const Spacer(),
                      if (_result != null)
                        _StatusChip(
                          icon: Icons.local_taxi,
                          text: '${_result!.totalOnline} çevrimiçi',
                        ),
                    ],
                  ),
                ),

                // Sağ alt: tekrar konum butonu (harita yarısının altında)
                Positioned(
                  right: 12, bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'me-btn',
                    backgroundColor: FerogoColors.inkMuted,
                    foregroundColor: FerogoColors.brand,
                    onPressed: () async {
                      await _resolveLocation();
                      await _loadDrivers();
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),

          // ─── ALT YARI: SABİT PANEL (inputlar + sürücü listesi) ─
          Expanded(
            flex: 1,
            child: Container(
              decoration: const BoxDecoration(
                color: FerogoColors.inkSoft,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: FerogoColors.line)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    // Başlık + yenile
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              user != null ? 'Selam ${user.name.split(' ').first}' : 'Hoş geldin',
                              style: const TextStyle(
                                color: FerogoColors.textHigh,
                                fontSize: 18, fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_loadingDrivers)
                            const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: FerogoColors.brand),
                            )
                          else
                            IconButton(
                              onPressed: _loadDrivers,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              icon: const Icon(Icons.refresh, color: FerogoColors.textMid),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // İki input: pickup (readonly) + dropoff (tıklanır)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _AddressInputs(
                        pickupLabel: _hasFix ? 'Mevcut konumum' : 'Konum aranıyor…',
                        onPickupTap: () async {
                          await _resolveLocation();
                          await _loadDrivers();
                        },
                        onDropoffTap: _startBooking,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Sürücü listesi (kalan alan)
                    Expanded(child: _buildList(null)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ScrollController? c) {
    if (_driversError != null) {
      return ListView(controller: c, padding: const EdgeInsets.all(16), children: [
        ErrorBanner(message: _driversError ?? 'Sürücüler yüklenemedi.', onClose: () => setState(() => _driversError = null)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _loadDrivers, child: const Text('Yeniden yükle')),
      ]);
    }

    final all = _result?.drivers ?? const <NearbyDriver>[];
    if (_loadingDrivers && all.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: FerogoColors.brand));
    }

    final list = _womenOnlyFilter ? all.where((d) => d.isFemale).toList() : all;

    return Column(
      children: [
        _WomenFilterBar(
          active: _womenOnlyFilter,
          onToggle: () => setState(() => _womenOnlyFilter = !_womenOnlyFilter),
        ),
        Expanded(
          child: list.isEmpty
              ? ListView(controller: c, padding: const EdgeInsets.all(20), children: [
                  Center(child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const Icon(Icons.search_off, color: FerogoColors.textLow, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          _womenOnlyFilter
                              ? 'Çevrende şu an kadın sürücü yok. Filtreyi kaldırıp dene.'
                              : 'Çevrede şu an müsait sürücü bulamadık.',
                          style: const TextStyle(color: FerogoColors.textMid),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )),
                ])
              : ListView.separated(
                  controller: c,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemBuilder: (_, i) => _DriverTile(
                    driver: list[i],
                    onTap: () {
                      _map.move(list[i].position, 16);
                      _startBooking();
                    },
                    onFavorite: () => _toggleFavorite(list[i]),
                  ),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemCount: list.length,
                ),
        ),
      ],
    );
  }
}

// ─── İki input alanı: pickup (readonly) + dropoff (tıklanır) ──
class _AddressInputs extends StatelessWidget {
  const _AddressInputs({
    required this.pickupLabel,
    required this.onPickupTap,
    required this.onDropoffTap,
  });

  final String pickupLabel;
  final VoidCallback onPickupTap;
  final VoidCallback onDropoffTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FerogoColors.inkMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FerogoColors.line),
      ),
      child: Column(
        children: [
          // PICKUP
          _Row(
            dotColor: FerogoColors.brand,
            placeholder: pickupLabel,
            isEmpty: false,
            trailing: const Icon(Icons.my_location, color: FerogoColors.textLow, size: 18),
            onTap: onPickupTap,
          ),
          const Divider(height: 1, color: FerogoColors.line, indent: 16, endIndent: 16),
          // DROPOFF
          _Row(
            dotColor: FerogoColors.danger,
            placeholder: 'Nereye gidiyorsun?',
            isEmpty: true,
            trailing: const Icon(Icons.arrow_forward, color: FerogoColors.brand, size: 18),
            onTap: onDropoffTap,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.dotColor,
    required this.placeholder,
    required this.isEmpty,
    required this.trailing,
    required this.onTap,
  });

  final Color dotColor;
  final String placeholder;
  final bool isEmpty;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                placeholder,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isEmpty ? FerogoColors.textLow : FerogoColors.textHigh,
                  fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FerogoColors.ink.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FerogoColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: FerogoColors.brand, size: 14),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: FerogoColors.textHigh, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _MeMarker extends StatelessWidget {
  const _MeMarker();
  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: FerogoColors.brand.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
      ),
      Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: FerogoColors.brand,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 2),
        ),
      ),
    ]);
  }
}

class _DriverPinIcon extends StatelessWidget {
  const _DriverPinIcon({required this.driver});
  final NearbyDriver driver;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FerogoColors.brand,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Text(
            '${driver.etaMinutes} dk',
            style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        const Icon(Icons.local_taxi, color: FerogoColors.brand, size: 24),
      ],
    );
  }
}

class _DriverTile extends StatelessWidget {
  const _DriverTile({required this.driver, required this.onTap, this.onFavorite});
  final NearbyDriver driver;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;

  static const Color _pink = Color(0xFFFB7185);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FerogoColors.inkMuted,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              _Avatar(url: driver.avatar, fallback: driver.fullName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(driver.name,
                            style: const TextStyle(color: FerogoColors.textHigh, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.star, color: FerogoColors.brand, size: 14),
                        const SizedBox(width: 2),
                        Text(driver.rating.toStringAsFixed(1),
                          style: const TextStyle(color: FerogoColors.textMid, fontSize: 12),
                        ),
                        if (driver.isFemale) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            text: '👩 Kadın',
                            color: _pink,
                            tooltip: driver.womenOnly ? 'Kadın sürücü · sadece kadın yolcu alır' : 'Kadın sürücü',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (driver.vehicleClass != null) driver.vehicleClass,
                        if (driver.vehicleLabel != null && driver.vehicleLabel!.isNotEmpty) driver.vehicleLabel,
                      ].whereType<String>().join(' · '),
                      style: const TextStyle(color: FerogoColors.textLow, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (driver.favoriteCount > 0) ...[
                      const SizedBox(height: 4),
                      Text('♥ ${driver.favoriteCount} favori',
                        style: const TextStyle(color: _pink, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (onFavorite != null)
                IconButton(
                  onPressed: onFavorite,
                  visualDensity: VisualDensity.compact,
                  tooltip: driver.isFavorite ? 'Favorilerden çıkar' : 'Favori şoför yap',
                  icon: Icon(
                    driver.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: driver.isFavorite ? _pink : FerogoColors.textLow,
                    size: 22,
                  ),
                ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${driver.etaMinutes} dk',
                    style: const TextStyle(color: FerogoColors.brand, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text('${driver.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(color: FerogoColors.textLow, fontSize: 11),
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

/// Küçük renkli rozet (Kadın sürücü vb.)
class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, this.tooltip});
  final String text;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: pill) : pill;
  }
}

/// Kadın sürücü filtre çubuğu (liste başlığı)
class _WomenFilterBar extends StatelessWidget {
  const _WomenFilterBar({required this.active, required this.onToggle});
  final bool active;
  final VoidCallback onToggle;

  static const Color _pink = Color(0xFFFB7185);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _pink.withValues(alpha: active ? 0.28 : 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _pink.withValues(alpha: active ? 0.7 : 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('👩', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text('Kadın sürücü',
                  style: TextStyle(color: _pink, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                if (active) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check, color: _pink, size: 14),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.fallback});
  final String? url;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final initials = fallback.isEmpty
        ? '?'
        : fallback.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0]).join().toUpperCase();

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44, height: 44,
        color: FerogoColors.brand.withValues(alpha: 0.18),
        alignment: Alignment.center,
        child: url != null && url!.isNotEmpty
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                width: 44, height: 44,
                errorBuilder: (_, _, _) => _initials(initials),
              )
            : _initials(initials),
      ),
    );
  }

  Widget _initials(String s) => Text(s,
    style: const TextStyle(color: FerogoColors.brand, fontWeight: FontWeight.w800, fontSize: 14),
  );
}
