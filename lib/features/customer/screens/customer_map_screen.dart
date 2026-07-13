import 'dart:async';

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

  /// Ters coğrafi kodlamayla çözülen mevcut konum adresi
  String? _pickupAddress;

  // ─── Dropoff canlı arama (aynı ekran — mod/sayfa YOK) ─────
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;
  List<Place> _searchResults = const [];
  bool _searchBusy = false;
  bool _resolvingDropoff = false; // Yandex önerisinin koordinatı çözülürken
  String? _searchError;

  /// Kutuda ≥2 karakter varsa liste alanında sürücü yerine sonuçlar gösterilir.
  bool get _showResults => _searchCtrl.text.trim().length >= 2;

  /// Arama aktif (odak VEYA sonuç var). Düzeni buna bağladık: kaydırınca klavye
  /// kapanıp odak düşse bile sonuç dururken küçük-harita/büyük-panel korunur —
  /// harita büyüyüp sonuçlar daralmaz.
  bool get _searchActive => _searchFocus.hasFocus || _showResults;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
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
        _resolveAddress(position);
      case LocationError(:final reason):
        setState(() => _locationError = reason.userMessage);
    }
  }

  /// Konumun okunur adresini çöz + booking draft'ı gerçek adresle güncelle.
  Future<void> _resolveAddress(LatLng position) async {
    final address = await ref.read(locationServiceProvider).reverseGeocode(position);
    if (!mounted || address == null || address.isEmpty) return;
    setState(() => _pickupAddress = address);
    ref.read(bookingDraftProvider.notifier).setPickupFromPosition(position, label: address);
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() { _searchResults = const []; _searchError = null; });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() { _searchBusy = true; _searchError = null; });
    try {
      final list = await ref.read(customerRideRepositoryProvider).searchPlaces(q);
      if (!mounted) return;
      setState(() => _searchResults = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchError = 'Arama yapılamadı, ağını kontrol et.');
    } finally {
      if (mounted) setState(() => _searchBusy = false);
    }
  }

  Future<void> _pickDropoff(Place p) async {
    if (_resolvingDropoff) return;
    FocusScope.of(context).unfocus();

    Place dropoff = p;
    // Yandex önerisi koordinatsız gelir → gerçek konumu çöz.
    if (!p.hasCoords) {
      setState(() { _resolvingDropoff = true; _searchError = null; });
      try {
        final resolved = await ref.read(customerRideRepositoryProvider)
            .resolvePlace(uri: p.uri, text: p.displayName);
        if (!mounted) return;
        if (resolved == null) {
          setState(() { _resolvingDropoff = false; _searchError = 'Bu konumun koordinatı alınamadı, başka bir sonuç dene.'; });
          return;
        }
        // Güzel görünen ismi koru, koordinatı al
        dropoff = Place(position: resolved.position, displayName: p.displayName, hasCoords: true);
      } catch (_) {
        if (mounted) setState(() { _resolvingDropoff = false; _searchError = 'Konum alınamadı, ağını kontrol et.'; });
        return;
      }
      if (mounted) setState(() => _resolvingDropoff = false);
    }

    // Pickup'ı garantiye al (adres varsa onunla)
    ref.read(bookingDraftProvider.notifier).setPickup(
      Place(position: _center, displayName: _pickupAddress ?? 'Mevcut konumum'),
    );
    ref.read(bookingDraftProvider.notifier).setDropoff(dropoff);
    _searchCtrl.clear();
    if (mounted) context.push(AppRoutes.customerBookConfirm);
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
      setState(() => _driversError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _driversError = 'Sürücüler yüklenemedi. Bağlantını kontrol edip tekrar dene.');
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
        title: const Text('FerXGo'),
        backgroundColor: FerxgoColors.ink,
        actions: [
          IconButton(
            tooltip: 'Favori sürücülerim',
            onPressed: () => context.push(AppRoutes.customerFavorites),
            icon: const Icon(Icons.favorite_border),
          ),
          IconButton(
            tooltip: 'Geçmiş yolculuklar',
            onPressed: () => context.push(AppRoutes.customerHistory),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Profil',
            onPressed: () => context.push(AppRoutes.profile),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── ÜST: HARITA (arama aktifken küçülür ama görünür kalır) ─
          Expanded(
            flex: _searchActive ? 2 : 5,
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
                      userAgentPackageName: 'com.ferxgo',
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
                          width: 130, height: 56,
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
                    backgroundColor: FerxgoColors.inkMuted,
                    foregroundColor: FerxgoColors.brand,
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

          // ─── ALT: PANEL (arama aktifken büyür — sonuçlar rahat görünsün) ─
          Expanded(
            flex: _searchActive ? 8 : 5,
            child: Container(
              decoration: const BoxDecoration(
                color: FerxgoColors.inkSoft,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: FerxgoColors.line)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Başlık + yenile — yazarken GİZLENİR ama ağaçta kalır (Offstage)
                    // ki alttaki yazı kutusunun yeri kaymasın, odak/klavye düşmesin.
                    Offstage(
                      offstage: _searchActive,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                user != null ? 'Selam ${user.name.split(' ').first}' : 'Hoş geldin',
                                style: const TextStyle(
                                  color: FerxgoColors.textHigh,
                                  fontSize: 18, fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_loadingDrivers)
                              const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: FerxgoColors.brand),
                              )
                            else
                              IconButton(
                                onPressed: _loadDrivers,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                icon: const Icon(Icons.refresh, color: FerxgoColors.textMid),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Adres girişleri: pickup (sabit) + dropoff (AYNI SAYFADA yazılabilir)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _addressInputs(),
                    ),
                    const SizedBox(height: 10),
                    // Yazıldıysa adres sonuçları; değilse sade yönlendirme (sürücü listesi yok)
                    Expanded(
                      child: _showResults
                          ? Column(
                              children: [
                                if (_searchBusy)
                                  const LinearProgressIndicator(minHeight: 2, color: FerxgoColors.brand, backgroundColor: FerxgoColors.inkMuted),
                                Expanded(child: _buildSearchResults()),
                              ],
                            )
                          : _buildHomeHint(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Kalkış (sabit) + varış (aynı sayfada yazılabilir) girişleri.
  Widget _addressInputs() {
    return Container(
      decoration: BoxDecoration(
        color: FerxgoColors.inkMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _searchFocus.hasFocus ? FerxgoColors.brand : FerxgoColors.line),
      ),
      child: Column(
        children: [
          // PICKUP (dokununca konumu yenile)
          InkWell(
            onTap: () async { await _resolveLocation(); await _loadDrivers(); },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: FerxgoColors.brand, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _pickupAddress ?? (_hasFix ? 'Mevcut konumum' : 'Konum aranıyor…'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.my_location, color: FerxgoColors.textLow, size: 18),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: FerxgoColors.line, indent: 16, endIndent: 16),
          // DROPOFF — aynı sayfada canlı yazılabilir alan
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: FerxgoColors.danger, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    readOnly: !_hasFix,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w600, fontSize: 14),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                      hintText: 'Nereye gidiyorsun?',
                      hintStyle: TextStyle(color: FerxgoColors.textLow, fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_searchCtrl.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      _searchFocus.unfocus();
                      setState(() => _searchResults = const []);
                    },
                    child: const Icon(Icons.close, color: FerxgoColors.textLow, size: 18),
                  )
                else
                  const Icon(Icons.arrow_forward, color: FerxgoColors.brand, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_resolvingDropoff) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: FerxgoColors.brand),
            SizedBox(height: 12),
            Text('Konum alınıyor…', style: TextStyle(color: FerxgoColors.textMid)),
          ],
        ),
      );
    }
    if (_searchError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(_searchError!, style: const TextStyle(color: FerxgoColors.danger), textAlign: TextAlign.center),
      ));
    }
    if (_searchCtrl.text.trim().length < 2) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Aramaya başla — örn. "Konak Pier"', style: TextStyle(color: FerxgoColors.textLow)),
      ));
    }
    if (_searchResults.isEmpty && !_searchBusy) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Sonuç yok', style: TextStyle(color: FerxgoColors.textLow)),
      ));
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: FerxgoColors.line),
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.place, color: FerxgoColors.brand),
        title: Text(_searchResults[i].shortName,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w600),
        ),
        subtitle: _searchResults[i].secondaryName.isEmpty
            ? null
            : Text(_searchResults[i].secondaryName,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12),
              ),
        onTap: () => _pickDropoff(_searchResults[i]),
      ),
    );
  }

  /// Ana ekran alt paneli — sürücü listesi yok. Sade yönlendirme.
  Widget _buildHomeHint() {
    if (_driversError != null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        ErrorBanner(message: _driversError ?? 'Bir sorun oldu.', onClose: () => setState(() => _driversError = null)),
      ]);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_taxi, color: FerxgoColors.textLow, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Nereye gideceğini yaz, teklifini ver.',
              textAlign: TextAlign.center,
              style: TextStyle(color: FerxgoColors.textMid, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Favori sürücün, yakındakiler ya da tümüne teklifini gönderirsin.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12, height: 1.4),
            ),
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
        color: FerxgoColors.ink.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FerxgoColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: FerxgoColors.brand, size: 14),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 12, fontWeight: FontWeight.w600)),
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
          color: FerxgoColors.brand.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
      ),
      Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: FerxgoColors.brand,
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
            color: FerxgoColors.brand,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Text(
            driver.name.isNotEmpty ? '${driver.name} · ${driver.etaMinutes} dk' : '${driver.etaMinutes} dk',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
        const Icon(Icons.local_taxi, color: FerxgoColors.brand, size: 24),
      ],
    );
  }
}

