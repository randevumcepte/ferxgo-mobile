import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_repository.dart';
import '../driver/driver_repository.dart';

/// Profil / hesabım — her iki rol için.
/// Düzen Martı profilini örnek alır (üst kart + hızlı butonlar + menü), stil
/// FerXGo koyu temasına sadıktır. Hazır olmayan kalemler tıklanır + "Yakında".
/// Sürücü kadın ise "sadece kadın yolcu" tercihi Güvenlik bölümünde.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _version = '';
  bool? _isFemale;
  bool _womenOnly = false;
  bool _womenBusy = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadDriverPrefs();
  }

  Future<void> _loadVersion() async {
    final pkg = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = '${pkg.version}+${pkg.buildNumber}');
  }

  Future<void> _loadDriverPrefs() async {
    final user = ref.read(authControllerProvider).value?.user;
    if (user == null || !user.isDriver) return;
    try {
      final s = await ref.read(driverRepositoryProvider).state();
      if (!mounted) return;
      setState(() {
        _isFemale = s.driver.isFemale;
        _womenOnly = s.driver.womenOnly;
      });
    } catch (_) {}
  }

  Future<void> _toggleWomenOnly(bool v) async {
    setState(() => _womenBusy = true);
    try {
      final result = await ref.read(driverRepositoryProvider).setWomenOnly(v);
      if (mounted) setState(() => _womenOnly = result);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _womenBusy = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FerxgoColors.inkSoft,
        title: const Text('Çıkış yap?', style: TextStyle(color: FerxgoColors.textHigh)),
        content: const Text('Oturumun bu cihazda kapatılacak.',
            style: TextStyle(color: FerxgoColors.textMid)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FerxgoColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış yap'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authRepositoryProvider).logout();
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _soon([String? message]) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message ?? 'Yakında — sonraki sürümde geliyor.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FerxgoColors.inkMuted,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value?.user;
    final isDriver = user?.isDriver == true;

    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign_outlined),
            tooltip: 'Duyurular',
            onPressed: () => _soon('Duyurular yakında.'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // ── Kullanıcı kartı ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: FerxgoColors.inkSoft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: FerxgoColors.line),
              ),
              child: Row(
                children: [
                  // Avatar + doğrulama rozeti
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          color: FerxgoColors.brand.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.person, color: FerxgoColors.brand, size: 30),
                      ),
                      Positioned(
                        right: -2, bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: FerxgoColors.inkSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified, color: FerxgoColors.success, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.name ?? '—',
                          style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // "Hesabım ›" — hesap detay/düzenleme (yakında)
                        InkWell(
                          onTap: () => _soon('Hesap detayları yakında.'),
                          borderRadius: BorderRadius.circular(6),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Hesabım',
                                style: TextStyle(color: FerxgoColors.brand, fontSize: 14, fontWeight: FontWeight.w700)),
                              Icon(Icons.chevron_right, color: FerxgoColors.brand, size: 18),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Puan + rol
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: FerxgoColors.brand, size: 20),
                          const SizedBox(width: 3),
                          Text(
                            (user?.rating ?? 5.0).toStringAsFixed(1),
                            style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: FerxgoColors.brand.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(isDriver ? 'Sürücü' : 'Yolcu',
                          style: const TextStyle(color: FerxgoColors.brand, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Hızlı butonlar: Destek · Ödeme · Yolculuklar ──────────────
            Row(
              children: [
                _QuickAction(
                  icon: Icons.help_outline,
                  label: 'Destek',
                  onTap: () => _openUrl('https://ferxgo.com/iletisim'),
                ),
                const SizedBox(width: 12),
                _QuickAction(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Ödeme',
                  onTap: () => _soon('Cüzdan ve ödeme yakında.'),
                ),
                const SizedBox(width: 12),
                _QuickAction(
                  icon: Icons.receipt_long_outlined,
                  label: 'Yolculuklar',
                  onTap: isDriver
                      ? () => _soon('Sürücü yolculuk geçmişi yakında.')
                      : () => context.push(AppRoutes.customerHistory),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Menü ──────────────────────────────────────────────────────
            _SectionLabel('Hesabım'),
            _LinkTile(
              icon: Icons.local_offer_outlined,
              label: 'Kampanyalar',
              subtitle: 'Kupon kodu ekle',
              soon: true,
              onTap: () => _soon('Kampanyalar ve kuponlar yakında.'),
            ),

            // Güvenlik tercihleri — kadın sürücüde canlı toggle
            if (_isFemale == true)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: FerxgoColors.inkSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: FerxgoColors.line),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: FerxgoColors.brand,
                  value: _womenOnly,
                  onChanged: _womenBusy ? null : _toggleWomenOnly,
                  secondary: const Icon(Icons.shield_outlined, color: FerxgoColors.textMid, size: 20),
                  title: const Text('Sadece kadın yolcu al',
                    style: TextStyle(color: FerxgoColors.textHigh, fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Yalnızca kadın yolculardan talep alırsın.',
                    style: TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
                ),
              )
            else
              _LinkTile(
                icon: Icons.shield_outlined,
                label: 'Güvenlik Tercihleri',
                soon: true,
                onTap: () => _soon('Güvenlik tercihleri yakında.'),
              ),

            // Favori sürücüler (yolcu)
            if (!isDriver)
              _LinkTile(
                icon: Icons.favorite_outline,
                label: 'Favori Sürücülerim',
                onTap: () => context.push(AppRoutes.customerFavorites),
              ),

            _LinkTile(
              icon: Icons.settings_outlined,
              label: 'Ayarlar',
              soon: true,
              onTap: () => _soon('Ayarlar yakında.'),
            ),
            const SizedBox(height: 20),

            // ── Yasal ─────────────────────────────────────────────────────
            _SectionLabel('Yasal'),
            _LinkTile(icon: Icons.privacy_tip_outlined, label: 'KVKK Aydınlatma Metni',
              onTap: () => _openUrl('https://ferxgo.com/kvkk')),
            _LinkTile(icon: Icons.description_outlined, label: 'Kullanım Şartları',
              onTap: () => _openUrl('https://ferxgo.com/kullanim-sartlari')),
            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: FerxgoColors.danger),
              label: const Text('Çıkış yap', style: TextStyle(color: FerxgoColors.danger)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: FerxgoColors.danger),
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('FerXGo · $_version',
                style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Üstteki hızlı erişim kutucuğu (Destek / Ödeme / Yolculuklar).
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FerxgoColors.line),
            ),
            child: Column(
              children: [
                Icon(icon, color: FerxgoColors.brand, size: 24),
                const SizedBox(height: 8),
                Text(label,
                  style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
          style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.soon = false,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool soon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: FerxgoColors.line),
            ),
            child: Row(
              children: [
                Icon(icon, color: FerxgoColors.textMid, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                        style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 14)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                          style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                if (soon)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: FerxgoColors.brand.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('YAKINDA',
                      style: TextStyle(color: FerxgoColors.brand, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                const Icon(Icons.chevron_right, color: FerxgoColors.textLow, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
