import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Ödemeler — FerXGo ödeme modeli.
///
/// Model (Martı sözleşmesiyle doğrulanmış, memory: payment_noshow):
///   • Yolculuk ücreti → NAKİT / BANKA HAVALESİ. Platform ücrete dokunmaz;
///     yolcu ödemeyi doğrudan sürücüye yapar.
///   • Kayıtlı kart → yalnızca İPTAL / NO-SHOW CEZASI için (İyzico ile çekilir,
///     platformda kalır). Yolculuk ücreti bu karttan ASLA çekilmez.
///
/// Kart tokenizasyonu (İyzico 3D Secure) backend'e bağlanınca "Kart Ekle"
/// gerçek akışa geçer. Şimdilik model + yöntem gösterimi + net bilgilendirme.
class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FerxgoColors.inkMuted,
      ));
  }

  void _explainModel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: FerxgoColors.inkSoft,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(color: FerxgoColors.line, borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Ödeme nasıl işler?',
              style: TextStyle(color: FerxgoColors.textHigh, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            _ExplainRow(
              icon: Icons.payments_outlined,
              title: 'Yolculuk ücreti: nakit veya havale',
              body: 'Ücreti doğrudan sürücüne ödersin. Yolculuk ücretine karışmıyor, komisyon almıyoruz.',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(title: const Text('Ödemeler')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            // ── Model özet kartı ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [FerxgoColors.brand.withValues(alpha: 0.16), FerxgoColors.inkSoft],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.payments_rounded, color: FerxgoColors.brand, size: 26),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Yolculuğu nakit veya havale ile ödersin',
                          style: TextStyle(color: FerxgoColors.textHigh, fontSize: 16, fontWeight: FontWeight.w800, height: 1.3)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('FerXGo yolculuk ücretine dokunmaz; ödemeyi doğrudan sürücüne yaparsın.',
                    style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => _explainModel(context),
                    borderRadius: BorderRadius.circular(6),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Ödeme nasıl işler?',
                          style: TextStyle(color: FerxgoColors.brand, fontSize: 13, fontWeight: FontWeight.w700)),
                        Icon(Icons.chevron_right, color: FerxgoColors.brand, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Ödeme yöntemi ─────────────────────────────────────────────
            const _SectionLabel('Yolculuk Ödeme Yöntemi'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: FerxgoColors.inkSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: FerxgoColors.success.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: FerxgoColors.success.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: FerxgoColors.success, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nakit / Banka Havalesi',
                          style: TextStyle(color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('Yolculuk sonunda sürücüye ödenir',
                          style: TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: FerxgoColors.success.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Aktif',
                      style: TextStyle(color: FerxgoColors.success, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Ceza için kayıtlı kart ────────────────────────────────────
            const _SectionLabel('Ceza İçin Kayıtlı Kart'),
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: FerxgoColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FerxgoColors.warning.withValues(alpha: 0.35)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: FerxgoColors.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kart yalnızca iptal / no-show cezası içindir. Yolculuk ücreti bu karttan çekilmez.',
                      style: TextStyle(color: FerxgoColors.textMid, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            // Kart ekleme (İyzico 3D Secure yakında)
            Material(
              color: FerxgoColors.inkSoft,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => _snack(context, 'Kart ekleme (İyzico 3D Secure) yakında bağlanacak.'),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: FerxgoColors.line),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_card, color: FerxgoColors.brand, size: 22),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text('Kart Ekle',
                          style: TextStyle(color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
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
            const SizedBox(height: 16),
            // Kart şeması logoları (güven)
            Center(
              child: Text('Visa · Mastercard · Troy · American Express — İyzico güvencesiyle',
                textAlign: TextAlign.center,
                style: TextStyle(color: FerxgoColors.textLow.withValues(alpha: 0.8), fontSize: 11)),
            ),
          ],
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
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text,
          style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

class _ExplainRow extends StatelessWidget {
  const _ExplainRow({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: FerxgoColors.brand.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: FerxgoColors.brand, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(body, style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12.5, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
