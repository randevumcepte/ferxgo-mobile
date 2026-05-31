import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../auth_repository.dart';

class CustomerPhoneScreen extends ConsumerStatefulWidget {
  const CustomerPhoneScreen({super.key});

  @override
  ConsumerState<CustomerPhoneScreen> createState() => _CustomerPhoneScreenState();
}

class _CustomerPhoneScreenState extends ConsumerState<CustomerPhoneScreen> {
  final _phoneCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _normalize(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    // 10 hane (5xx...) → 90 prefix ekle. 11 hane (0 ile başlıyorsa) 0'ı at.
    if (digits.length == 10) return '+90$digits';
    if (digits.length == 11 && digits.startsWith('0')) return '+90${digits.substring(1)}';
    if (digits.length == 12 && digits.startsWith('90')) return '+$digits';
    return input.startsWith('+') ? input : '+$digits';
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = _normalize(_phoneCtrl.text.trim());

    setState(() { _busy = true; _error = null; });
    try {
      final res  = await ref.read(authRepositoryProvider).sendCustomerOtp(phone);
      final devCode = res['dev_code'] as String?;
      if (!mounted) return;
      // Sonraki ekrana git, telefon ve dev_code'u taşı (debug için).
      context.go('${AppRoutes.customerOtp}?phone=${Uri.encodeQueryComponent(phone)}'
          '${devCode != null ? '&dev=$devCode' : ''}');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Beklenmedik bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FerogoColors.ink,
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.modeSelect),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Telefon numaran',
                  style: TextStyle(
                    color: FerogoColors.textHigh, fontSize: 28, fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sana SMS ile 6 haneli doğrulama kodu göndereceğiz.',
                  style: TextStyle(color: FerogoColors.textLow, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofocus: true,
                  style: const TextStyle(color: FerogoColors.textHigh, fontSize: 18, letterSpacing: 0.5),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()+-]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: const InputDecoration(
                    prefixText: '+90 ',
                    prefixStyle: TextStyle(color: FerogoColors.textMid, fontSize: 18),
                    hintText: '5xx xxx xx xx',
                  ),
                  validator: (v) {
                    final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (d.length < 10) return 'Geçerli bir cep numarası gir.';
                    return null;
                  },
                  onFieldSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 14),
                if (_error != null) ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                      : const Text('Kodu gönder'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Devam ederek KVKK Aydınlatma Metni ve Kullanım Şartları\'nı kabul ediyorsun.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FerogoColors.textLow, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
