import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/location/location_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../auth/auth_repository.dart';
import '../customer_ride_repository.dart';
import '../models/nearby_driver.dart';

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
      case LocationError(:final reason):
        setState(() => _locationError = reason.userMessage);
    }
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _driversError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingDrivers = false);
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
      body: Stack(
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
                    text: _hasFix
                        ? 'Konumun alındı'
                        : 'Konum aranıyor…',
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

          // Sağ alt: tekrar konum butonu
          Positioned(
            right: 12, bottom: 220,
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

          // Alt sheet: yakındaki sürücüler listesi
          DraggableScrollableSheet(
            initialChildSize: 0.32,
            minChildSize: 0.18,
            maxChildSize: 0.85,
            builder: (ctx, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: FerogoColors.inkSoft,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(
                    top: BorderSide(color: FerogoColors.line),
                    left: BorderSide(color: FerogoColors.line),
                    right: BorderSide(color: FerogoColors.line),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: FerogoColors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              user != null ? 'Selam ${user.name.split(' ').first}' : 'Yakındaki sürücüler',
                              style: const TextStyle(
                                color: FerogoColors.textHigh,
                                fontSize: 20, fontWeight: FontWeight.w800,
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
                              icon: const Icon(Icons.refresh, color: FerogoColors.textMid),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _buildList(controller),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildList(ScrollController c) {
    if (_driversError != null) {
      return ListView(controller: c, padding: const EdgeInsets.all(16), children: [
        ErrorBanner(message: 'Sürücüler yüklenemedi. Tekrar dene.', onClose: () => setState(() => _driversError = null)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _loadDrivers, child: const Text('Yeniden yükle')),
      ]);
    }

    final list = _result?.drivers ?? const <NearbyDriver>[];
    if (_loadingDrivers && list.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: FerogoColors.brand));
    }
    if (list.isEmpty) {
      return ListView(controller: c, padding: const EdgeInsets.all(20), children: const [
        Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(Icons.search_off, color: FerogoColors.textLow, size: 36),
              SizedBox(height: 12),
              Text('Çevrede şu an müsait sürücü bulamadık.',
                style: TextStyle(color: FerogoColors.textMid),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )),
      ]);
    }

    return ListView.separated(
      controller: c,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemBuilder: (_, i) => _DriverTile(
        driver: list[i],
        onTap: () {
          _map.move(list[i].position, 16);
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text('${list[i].fullName} · talep akışı sonraki adımda.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: FerogoColors.inkMuted,
            ));
        },
      ),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemCount: list.length,
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
  const _DriverTile({required this.driver, required this.onTap});
  final NearbyDriver driver;
  final VoidCallback onTap;

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
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
