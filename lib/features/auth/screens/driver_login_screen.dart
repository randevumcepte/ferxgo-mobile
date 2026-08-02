import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/ferxgo_logo.dart';
import '../../app_mode/app_mode.dart';
import '../auth_repository.dart';
import 'driver_forgot_password_screen.dart';

class DriverLoginScreen extends ConsumerStatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  ConsumerState<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends ConsumerState<DriverLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _formKey   = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).driverLogin(
        login: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      // Router otomatik /driver/home'a atar.
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Beklenmedik bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Web sitesindeki sürücü başvuru ("Sürücü Ol") sayfasını tarayıcıda açar.
  Future<void> _openDriverSignup() async {
    final uri = Uri.parse('https://ferxgo.com/surucu-olun');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Sayfa açılamadı: ferxgo.com/surucu-olun'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FerxgoColors.inkMuted,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FerxgoColors.ink,
        leading: IconButton(
          onPressed: () async {
            await ref.read(appModeControllerProvider.notifier).clear();
          },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                Row(
                  children: [
                    const FerxgoLogo(size: 22),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FerxgoColors.brand.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'SÜRÜCÜ',
                        style: TextStyle(
                          color: FerxgoColors.brand,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Hoş geldin',
                  style: TextStyle(
                    color: FerxgoColors.textHigh, fontSize: 28, fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'FerXGo sürücü hesabınla giriş yap.',
                  style: TextStyle(color: FerxgoColors.textLow, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  style: const TextStyle(color: FerxgoColors.textHigh),
                  decoration: const InputDecoration(
                    hintText: 'E-posta veya telefon',
                    prefixIcon: Icon(Icons.person_outline, color: FerxgoColors.textLow),
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'E-posta veya telefon gerekli';
                    final isEmail = s.contains('@');
                    final digits = s.replaceAll(RegExp(r'\D'), '');
                    if (isEmail) {
                      if (!s.contains('.')) return 'Geçerli bir e-posta gir';
                    } else if (digits.length < 10) {
                      return 'Geçerli bir e-posta veya telefon gir';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  style: const TextStyle(color: FerxgoColors.textHigh),
                  decoration: InputDecoration(
                    hintText: 'şifre',
                    prefixIcon: const Icon(Icons.lock_outline, color: FerxgoColors.textLow),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: FerxgoColors.textLow,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Şifre gerekli';
                    return null;
                  },
                  onFieldSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const DriverForgotPasswordScreen()),
                            ),
                    style: TextButton.styleFrom(
                      foregroundColor: FerxgoColors.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    ),
                    child: const Text('Şifremi unuttum'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_error != null) ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                      : const Text('Giriş yap'),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _openDriverSignup,
                    style: TextButton.styleFrom(
                      foregroundColor: FerxgoColors.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: const Text.rich(
                      TextSpan(
                        style: TextStyle(color: FerxgoColors.textLow, fontSize: 13),
                        children: [
                          TextSpan(text: 'Henüz hesabın yok mu? '),
                          TextSpan(
                            text: 'Sürücü olarak başvur',
                            style: TextStyle(color: FerxgoColors.brand, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
