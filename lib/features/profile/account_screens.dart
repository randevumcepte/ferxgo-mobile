import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/app_colors.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Hesabım — Martı hesap düzeninin FerXGo koyu temasındaki karşılığı.
///
/// Hub (AccountScreen) → alt ekranlar:
///   • Kişisel Bilgiler   (PersonalInfoScreen)
///   • Hesap Doğrulama    (AccountVerificationScreen)
///   • Kaydedilen Yerler  (SavedPlacesScreen)
///   • Fatura Adresi      (BillingAddressScreen)
///   • Diğer / Hesabı Sil (AccountOtherScreen)
///
/// NOT: Sunucu tarafında mobil profil-güncelleme / adres / hesap-silme
/// endpoint'leri henüz yok. Ekranlar gerçek okunan veriyi (ad/telefon/e-posta)
/// gösterir; düzenleme/kaydetme UI'ı çalışır, kalıcı kayıt bir sonraki adımda
/// backend'e bağlanacak. O yerlerde net "yakında bağlanacak" bilgisi verilir.
/// ─────────────────────────────────────────────────────────────────────────

// ── Ortak parçalar ─────────────────────────────────────────────────────────

/// Standart koyu tema Scaffold + AppBar (geri butonlu).
class _AccountScaffold extends StatelessWidget {
  const _AccountScaffold({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: child),
    );
  }
}

/// Avatar + doğrulama rozeti (profil kartındaki ile aynı stil).
class _Avatar extends StatelessWidget {
  const _Avatar({this.size = 88});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: FerxgoColors.brand.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.person, color: FerxgoColors.brand, size: size * 0.5),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(color: FerxgoColors.ink, shape: BoxShape.circle),
            child: Icon(Icons.verified, color: FerxgoColors.success, size: size * 0.28),
          ),
        ),
      ],
    );
  }
}

/// Tıklanır satır (ikon + başlık + opsiyonel alt yazı/rozet + chevron).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? FerxgoColors.danger : FerxgoColors.textHigh;
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
                Icon(icon, color: danger ? FerxgoColors.danger : FerxgoColors.textMid, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right, color: FerxgoColors.textLow, size: 20),
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
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Text(text,
          style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: FerxgoColors.inkMuted,
    ));
}

// ═══════════════════════════════════════════════════════════════════════════
// 1) HESABIM — HUB
// ═══════════════════════════════════════════════════════════════════════════

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;

    return _AccountScaffold(
      title: 'Hesabım',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          // Üst kimlik
          Center(child: _Avatar(size: 92)),
          const SizedBox(height: 12),
          Center(
            child: Text(user?.name ?? '—',
              style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: FerxgoColors.brand, size: 20),
                const SizedBox(width: 4),
                Text((user?.rating ?? 5.0).toStringAsFixed(1),
                  style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _Tile(
            icon: Icons.person_outline,
            label: 'Kişisel Bilgiler',
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PersonalInfoScreen())),
          ),
          _Tile(
            icon: Icons.verified_user_outlined,
            label: 'Hesap Doğrulama',
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AccountVerificationScreen())),
          ),
          _Tile(
            icon: Icons.star_border_rounded,
            label: 'Kaydedilen Yerler',
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SavedPlacesScreen())),
          ),
          _Tile(
            icon: Icons.receipt_long_outlined,
            label: 'Fatura Adresi',
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BillingAddressScreen())),
          ),
          _Tile(
            icon: Icons.more_horiz,
            label: 'Diğer',
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AccountOtherScreen())),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 2) KİŞİSEL BİLGİLER
// ═══════════════════════════════════════════════════════════════════════════

class PersonalInfoScreen extends ConsumerStatefulWidget {
  const PersonalInfoScreen({super.key});
  @override
  ConsumerState<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends ConsumerState<PersonalInfoScreen> {
  // Sunucu kaydı gelene kadar yerel gösterim override'ı.
  String? _nameOverride;
  String? _emailOverride;

  Future<void> _edit({
    required String title,
    required String initial,
    required String hint,
    TextInputType keyboard = TextInputType.text,
    required void Function(String) onSave,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FerxgoColors.inkSoft,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: FerxgoColors.line, borderRadius: BorderRadius.circular(2)),
            ),
            Text(title, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: keyboard,
              style: const TextStyle(color: FerxgoColors.textHigh),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: FerxgoColors.textLow),
                filled: true,
                fillColor: FerxgoColors.ink,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: FerxgoColors.brand,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      onSave(result);
      if (mounted) _snack(context, 'Kaydedildi. (Sunucuya kalıcı kayıt yakında bağlanacak.)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthUser? user = ref.watch(authControllerProvider).value?.user;
    final name  = _nameOverride ?? user?.name ?? '';
    final phone = user?.phone ?? '—';
    final email = _emailOverride ?? user?.email ?? '';

    return _AccountScaffold(
      title: 'Kişisel Bilgiler',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Center(child: _Avatar(size: 84)),
          const SizedBox(height: 14),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Sürücülerle eşleştiğinde tanınman için bir fotoğraf yükle.',
                textAlign: TextAlign.center,
                style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, height: 1.4)),
            ),
          ),
          const SizedBox(height: 24),

          _ValueRow(
            icon: Icons.badge_outlined,
            label: 'Ad Soyad',
            value: name.isEmpty ? 'Ekle' : name,
            onTap: () => _edit(
              title: 'Ad Soyad',
              initial: name,
              hint: 'Ad Soyad',
              onSave: (v) => setState(() => _nameOverride = v),
            ),
          ),
          _ValueRow(
            icon: Icons.phone_iphone,
            label: 'Telefon Numarası',
            value: phone,
            // Telefon giriş kimliği — buradan değiştirilemez.
            locked: true,
            onTap: () => _snack(context, 'Telefon numarası giriş kimliğindir, buradan değiştirilemez.'),
          ),
          _ValueRow(
            icon: Icons.mail_outline,
            label: 'E-posta',
            value: email.isEmpty ? 'Ekle' : email,
            onTap: () => _edit(
              title: 'E-posta',
              initial: email,
              hint: 'ornek@eposta.com',
              keyboard: TextInputType.emailAddress,
              onSave: (v) => setState(() => _emailOverride = v),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kişisel bilgi satırı — üstte küçük etiket, altta değer.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.locked = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool locked;
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: FerxgoColors.line),
            ),
            child: Row(
              children: [
                Icon(icon, color: FerxgoColors.textMid, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
                      const SizedBox(height: 3),
                      Text(value, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(locked ? Icons.lock_outline : Icons.chevron_right,
                  color: FerxgoColors.textLow, size: locked ? 16 : 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3) HESAP DOĞRULAMA
// ═══════════════════════════════════════════════════════════════════════════

class AccountVerificationScreen extends ConsumerWidget {
  const AccountVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;
    final isDriver = user?.isDriver == true;

    return _AccountScaffold(
      title: 'Hesap Doğrulama',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const Text(
            'FerXGo\'yu güvenli şekilde kullanabilmek için doğrulama adımlarını tamamla. '
            'Durumu aşağıdan takip edebilirsin.',
            style: TextStyle(color: FerxgoColors.textMid, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 20),

          // Telefon — OTP ile giriş yaptığı için doğrulanmış say.
          _VerifyRow(
            icon: Icons.phone_iphone,
            label: 'Telefon Doğrulama',
            subtitle: 'SMS ile doğrulandı.',
            verified: true,
          ),
          _VerifyRow(
            icon: Icons.badge_outlined,
            label: 'Kimlik Doğrulama',
            subtitle: 'Kimliğini doğrulayarak güven rozeti kazan.',
            verified: false,
            onTap: () => _snack(context, 'Kimlik doğrulama yakında.'),
          ),
          if (isDriver)
            _VerifyRow(
              icon: Icons.directions_car_outlined,
              label: 'Ehliyet & Araç Doğrulama',
              subtitle: 'Sürücü olarak yolculuk almak için zorunludur.',
              verified: false,
              onTap: () => _snack(context, 'Ehliyet/araç doğrulama sürücü panelinden yapılır.'),
            ),
        ],
      ),
    );
  }
}

class _VerifyRow extends StatelessWidget {
  const _VerifyRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.verified,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool verified;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: verified ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: FerxgoColors.line),
            ),
            child: Row(
              children: [
                Icon(icon, color: FerxgoColors.textMid, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(subtitle, style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12, height: 1.3)),
                    ],
                  ),
                ),
                if (verified)
                  const Icon(Icons.verified, color: FerxgoColors.success, size: 24)
                else
                  const Icon(Icons.chevron_right, color: FerxgoColors.textLow, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 4) KAYDEDİLEN YERLER
// ═══════════════════════════════════════════════════════════════════════════

class SavedPlacesScreen extends StatelessWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _AccountScaffold(
      title: 'Kaydedilen Yerler',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          _SectionLabel('Favoriler'),
          _Tile(
            icon: Icons.home_outlined,
            label: 'Ev Adresi Ekle',
            onTap: () => _snack(context, 'Adres kaydetme yakında bağlanacak.'),
          ),
          _Tile(
            icon: Icons.work_outline,
            label: 'İş Adresi Ekle',
            onTap: () => _snack(context, 'Adres kaydetme yakında bağlanacak.'),
          ),
          const SizedBox(height: 16),
          _SectionLabel('Diğer Kaydedilen Yerler'),
          _Tile(
            icon: Icons.add_location_alt_outlined,
            label: 'Kayıtlı Adres Ekle',
            onTap: () => _snack(context, 'Adres kaydetme yakında bağlanacak.'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 5) FATURA ADRESİ
// ═══════════════════════════════════════════════════════════════════════════

class BillingAddressScreen extends StatefulWidget {
  const BillingAddressScreen({super.key});
  @override
  State<BillingAddressScreen> createState() => _BillingAddressScreenState();
}

class _BillingAddressScreenState extends State<BillingAddressScreen> {
  final String _il = 'İzmir'; // hizmet ili sabit
  String? _ilce;
  String? _mahalle;
  final _acikAdres = TextEditingController();

  bool get _valid => _ilce != null && _acikAdres.text.trim().isNotEmpty;

  // İzmir ilçeleri (fatura için yeterli liste).
  static const _ilceler = [
    'Konak', 'Karşıyaka', 'Bornova', 'Buca', 'Çiğli', 'Gaziemir', 'Balçova',
    'Narlıdere', 'Bayraklı', 'Karabağlar', 'Menemen', 'Torbalı', 'Menderes',
    'Urla', 'Çeşme', 'Aliağa', 'Bergama', 'Ödemiş', 'Tire', 'Kemalpaşa',
  ];

  Future<void> _pickIlce() async {
    final picked = await _pickFromList('İlçe', _ilceler);
    if (picked != null) setState(() { _ilce = picked; _mahalle = null; });
  }

  Future<String?> _pickFromList(String title, List<String> items) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: FerxgoColors.inkSoft,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: FerxgoColors.line, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: items.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(items[i], style: const TextStyle(color: FerxgoColors.textHigh)),
                  onTap: () => Navigator.pop(ctx, items[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _acikAdres.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AccountScaffold(
      title: 'Fatura Adresi',
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              children: [
                _FieldBox(label: 'İl', value: _il, onTap: () =>
                  _snack(context, 'Şu an yalnızca İzmir\'e hizmet veriyoruz.')),
                _FieldBox(label: 'İlçe', value: _ilce, onTap: _pickIlce),
                _FieldBox(
                  label: 'Mahalle',
                  value: _mahalle,
                  onTap: _ilce == null
                      ? () => _snack(context, 'Önce ilçe seç.')
                      : () => _snack(context, 'Mahalle listesi yakında bağlanacak.'),
                ),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    color: FerxgoColors.inkSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: FerxgoColors.line),
                  ),
                  child: TextField(
                    controller: _acikAdres,
                    maxLines: 4,
                    style: const TextStyle(color: FerxgoColors.textHigh),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Açık Adres',
                      hintStyle: TextStyle(color: FerxgoColors.textLow),
                      contentPadding: EdgeInsets.all(16),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: FerxgoColors.brand,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: FerxgoColors.inkMuted,
                  disabledForegroundColor: FerxgoColors.textLow,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _valid
                    ? () => _snack(context, 'Fatura adresi kaydedildi. (Sunucuya kalıcı kayıt yakında.)')
                    : null,
                child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.label, required this.value, required this.onTap});
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FerxgoColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(filled ? value! : label,
                    style: TextStyle(
                      color: filled ? FerxgoColors.textHigh : FerxgoColors.textLow,
                      fontSize: 15,
                      fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                    )),
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

// ═══════════════════════════════════════════════════════════════════════════
// 6) DİĞER — HESABI SİL
// ═══════════════════════════════════════════════════════════════════════════

class AccountOtherScreen extends ConsumerWidget {
  const AccountOtherScreen({super.key});

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FerxgoColors.inkSoft,
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: FerxgoColors.danger, size: 22),
            SizedBox(width: 8),
            Text('Hesabı sil?', style: TextStyle(color: FerxgoColors.textHigh, fontSize: 17)),
          ],
        ),
        content: const Text(
          'Hesabın ve tüm bilgilerin kalıcı olarak silinecek. Bu işlem geri alınamaz. '
          'Devam etmek istediğine emin misin?',
          style: TextStyle(color: FerxgoColors.textMid, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Vazgeç',
                    style: TextStyle(color: FerxgoColors.brand, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: FerxgoColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Hesabı sil', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      _snack(context, 'Hesap silme talebin alındı. (Sunucu işlemi yakında bağlanacak.)');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AccountScaffold(
      title: 'Diğer',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          _Tile(
            icon: Icons.delete_outline,
            label: 'Hesabı Sil',
            danger: true,
            onTap: () => _deleteAccount(context, ref),
          ),
        ],
      ),
    );
  }
}
