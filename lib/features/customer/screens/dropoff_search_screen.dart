import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../customer_ride_repository.dart';
import '../models/place.dart';
import '../state/booking_draft.dart';

/// "Nereye gidiyorsun?" — Nominatim proxy ile adres arama (3 karakter sonra
/// 350ms debounce). Seçildiğinde booking draft'a yazıp onay ekranına gider.
class DropoffSearchScreen extends ConsumerStatefulWidget {
  const DropoffSearchScreen({super.key});

  @override
  ConsumerState<DropoffSearchScreen> createState() => _DropoffSearchScreenState();
}

class _DropoffSearchScreenState extends ConsumerState<DropoffSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() { _results = const []; _error = null; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() { _busy = true; _error = null; });
    try {
      final list = await ref.read(customerRideRepositoryProvider).searchPlaces(q);
      if (!mounted) return;
      setState(() => _results = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Arama yapılamadı, ağını kontrol et.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pick(Place p) {
    ref.read(bookingDraftProvider.notifier).setDropoff(p);
    context.go(AppRoutes.customerBookConfirm);
  }

  @override
  Widget build(BuildContext context) {
    final pickup = ref.watch(bookingDraftProvider).pickup;

    return Scaffold(
      backgroundColor: FerogoColors.ink,
      appBar: AppBar(
        backgroundColor: FerogoColors.ink,
        title: const Text('Nereye gidiyorsun?'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.customerHome),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Pickup özet kartı
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FerogoColors.inkSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: FerogoColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: FerogoColors.brand, size: 12),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        pickup?.displayName ?? 'Konumum',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: FerogoColors.textMid, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Arama alanı
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(color: FerogoColors.textHigh),
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Adres, mahalle, AVM…',
                  prefixIcon: const Icon(Icons.search, color: FerogoColors.textLow),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, color: FerogoColors.textLow),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _results = const []);
                          },
                        ),
                ),
              ),
            ),

            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: FerogoColors.brand,
                  backgroundColor: FerogoColors.inkMuted,
                ),
              ),

            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error!,
            style: const TextStyle(color: FerogoColors.danger),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_ctrl.text.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aramaya başla — örn. "Konak Pier"',
            style: TextStyle(color: FerogoColors.textLow),
          ),
        ),
      );
    }
    if (_results.isEmpty && !_busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sonuç yok', style: TextStyle(color: FerogoColors.textLow)),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: FerogoColors.line),
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.place, color: FerogoColors.brand),
        title: Text(_results[i].shortName,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: FerogoColors.textHigh, fontWeight: FontWeight.w600),
        ),
        subtitle: _results[i].secondaryName.isEmpty
            ? null
            : Text(_results[i].secondaryName,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: FerogoColors.textLow, fontSize: 12),
              ),
        onTap: () => _pick(_results[i]),
      ),
    );
  }
}
