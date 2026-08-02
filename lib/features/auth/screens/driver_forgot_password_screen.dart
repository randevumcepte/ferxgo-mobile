import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../auth_repository.dart';

/// Sürücü "Şifremi unuttum" — SMS ile sıfırlama.
/// Adım 1: kayıtlı telefonu gir → SMS kodu gönderilir.
/// Adım 2: kodu + yeni şifreyi gir → şifre güncellenir, login'e dönülür.
class DriverForgotPasswordScreen extends ConsumerStatefulWidget {
  const DriverForgotPasswordScreen({super.key});

  @override
  ConsumerState<DriverForgotPasswordScreen> createState() => _DriverForgotPasswordScreenState();
}

class _DriverForgotPasswordScreenState extends ConsumerState<DriverForgotPasswordScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();

  /// 1 = telefon gir, 2 = kod + yeni şifre gir
  int _step = 1;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Geçerli bir telefon numarası gir.');
      return;
    }
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      final res = await ref.read(authRepositoryProvider).driverForgotPassword(phone);
      if (!mounted) return;
      setState(() {
        _step = 2;
        _info = (res['message'] as String?) ?? 'Doğrulama kodu gönderildi.';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Beklenmedik bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeCtrl.text.trim();
    final pass = _passCtrl.text;
    if (code.length != 6) {
      setState(() => _error = '6 haneli kodu eksiksiz gir.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Yeni şifre en az 6 karakter olmalı.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final res = await ref.read(authRepositoryProvider).driverResetPassword(
        phone: _phoneCtrl.text.trim(),
        code: code,
        newPassword: pass,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text((res['message'] as String?) ?? 'Şifren güncellendi.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FerxgoColors.inkMuted,
        ));
      Navigator.of(context).pop();
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
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(
        backgroundColor: FerxgoColors.ink,
        title: const Text('Şifremi unuttum'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _step == 1 ? 'Telefonunu gir' : 'Kodu ve yeni şifreni gir',
                style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _step == 1
                    ? 'Sürücü hesabına kayıtlı telefonuna SMS ile 6 haneli doğrulama kodu göndereceğiz.'
                    : 'Telefonuna gelen 6 haneli kodu ve belirlemek istediğin yeni şifreyi gir.',
                style: const TextStyle(color: FerxgoColors.textLow, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),

              if (_step == 1) ...[
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: FerxgoColors.textHigh),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  decoration: const InputDecoration(
                    hintText: '5xx xxx xx xx',
                    prefixIcon: Icon(Icons.phone_outlined, color: FerxgoColors.textLow),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(color: FerxgoColors.textHigh, letterSpacing: 8, fontSize: 20),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '––––––',
                    prefixIcon: Icon(Icons.sms_outlined, color: FerxgoColors.textLow),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: FerxgoColors.textHigh),
                  decoration: InputDecoration(
                    hintText: 'Yeni şifre (en az 6 karakter)',
                    prefixIcon: const Icon(Icons.lock_outline, color: FerxgoColors.textLow),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: FerxgoColors.textLow,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : _sendCode,
                    style: TextButton.styleFrom(foregroundColor: FerxgoColors.brand),
                    child: const Text('Kodu yeniden gönder'),
                  ),
                ),
              ],

              const SizedBox(height: 8),
              if (_info != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: FerxgoColors.brand.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.35)),
                  ),
                  child: Text(_info!, style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13)),
                ),
              if (_error != null) ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),

              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : (_step == 1 ? _sendCode : _resetPassword),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                    : Text(_step == 1 ? 'Kodu gönder' : 'Şifreyi güncelle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
