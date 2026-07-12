import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../customer_ride_repository.dart';
import '../models/nearby_driver.dart';
import '../widgets/driver_status_badge.dart';

/// Favori sürücülerim — canlı durum (müsait/yolculukta/çevrimdışı) + favoriden çıkar.
/// Yolculuk için ana ekrandan varış seçip teklif gönderilir (bu ekran görüntüleme + yönetim).
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  bool _loading = true;
  String? _error;
  List<NearbyDriver> _drivers = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await ref.read(customerRideRepositoryProvider).favorites();
      if (!mounted) return;
      setState(() => _drivers = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Favoriler yüklenemedi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(NearbyDriver d) async {
    // İyimser: listeden hemen çıkar
    setState(() => _drivers = _drivers.where((x) => x.id != d.id).toList());
    try {
      await ref.read(customerRideRepositoryProvider).removeFavorite(d.id);
    } catch (_) {
      _load(); // geri al
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(title: const Text('Favori Sürücülerim')),
      body: SafeArea(
        child: RefreshIndicator(
          color: FerxgoColors.brand,
          backgroundColor: FerxgoColors.inkSoft,
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _drivers.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: FerxgoColors.brand));
    }
    if (_error != null && _drivers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Yeniden yükle')),
        ],
      );
    }
    if (_drivers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
        children: const [
          Icon(Icons.favorite_border, color: FerxgoColors.textLow, size: 56),
          SizedBox(height: 16),
          Text('Henüz favori sürücün yok',
            textAlign: TextAlign.center,
            style: TextStyle(color: FerxgoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text('Bir yolculuk sırasında beğendiğin sürücüyü kalbe dokunarak favorine ekle. '
              'Sonraki yolculuklarda önce onlara teklif gönderebilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, height: 1.4),
          ),
        ],
      );
    }

    final online = _drivers.where((d) => d.isOnline).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('$online / ${_drivers.length} favori sürücün şu an müsait',
          style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13),
        ),
        const SizedBox(height: 12),
        ..._drivers.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FavoriteTile(driver: d, onRemove: () => _remove(d)),
            )),
        const SizedBox(height: 8),
        const Center(
          child: Text('Yolculuk için ana ekrandan varış yeri seç,\nsonra favorine teklif gönder.',
            textAlign: TextAlign.center,
            style: TextStyle(color: FerxgoColors.textLow, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.driver, required this.onRemove});
  final NearbyDriver driver;
  final VoidCallback onRemove;

  static const Color _pink = Color(0xFFFB7185);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FerxgoColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: FerxgoColors.brand.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(driver.fullName.isNotEmpty ? driver.fullName : driver.name),
              style: const TextStyle(color: FerxgoColors.brand, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(driver.name,
                        style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.star, color: FerxgoColors.brand, size: 13),
                    const SizedBox(width: 2),
                    Text(driver.rating.toStringAsFixed(1),
                      style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                DriverStatusBadge(driver: driver),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Favorilerden çıkar',
            icon: const Icon(Icons.favorite, color: _pink, size: 22),
          ),
        ],
      ),
    );
  }

  String _initials(String s) => s.isEmpty
      ? '?'
      : s.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0]).join().toUpperCase();
}
