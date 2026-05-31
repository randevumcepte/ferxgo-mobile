import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/ferogo_logo.dart';
import '../auth_repository.dart';

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
        email: _emailCtrl.text.trim(),
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
                Row(
                  children: [
                    const FerogoLogo(size: 22),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FerogoColors.brand.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'SÜRÜCÜ',
                        style: TextStyle(
                          color: FerogoColors.brand,
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
                    color: FerogoColors.textHigh, fontSize: 28, fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ferogo sürücü hesabınla giriş yap.',
                  style: TextStyle(color: FerogoColors.textLow, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  style: const TextStyle(color: FerogoColors.textHigh),
                  decoration: const InputDecoration(
                    hintText: 'e-posta',
                    prefixIcon: Icon(Icons.alternate_email, color: FerogoColors.textLow),
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'E-posta gerekli';
                    if (!s.contains('@') || !s.contains('.')) return 'Geçerli bir e-posta gir';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  style: const TextStyle(color: FerogoColors.textHigh),
                  decoration: InputDecoration(
                    hintText: 'şifre',
                    prefixIcon: const Icon(Icons.lock_outline, color: FerogoColors.textLow),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: FerogoColors.textLow,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Şifre gerekli';
                    return null;
                  },
                  onFieldSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 14),
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
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(color: FerogoColors.textLow, fontSize: 13),
                      children: [
                        const TextSpan(text: 'Henüz hesabın yok mu? '),
                        TextSpan(
                          text: 'Sürücü olarak başvur',
                          style: const TextStyle(color: FerogoColors.brand, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
