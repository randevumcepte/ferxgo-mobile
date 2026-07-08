import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../auth_repository.dart';

class CustomerOtpScreen extends ConsumerStatefulWidget {
  const CustomerOtpScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<CustomerOtpScreen> createState() => _CustomerOtpScreenState();
}

class _CustomerOtpScreenState extends ConsumerState<CustomerOtpScreen> {
  final _codeCtrl = TextEditingController();
  final _focus    = FocusNode();
  bool _busy = false;
  String? _error;

  // Kod tekrar gönderim sayacı (60 sn cooldown)
  Timer? _ticker;
  int _resendIn = 60;
  bool get _canResend => _resendIn <= 0;

  @override
  void initState() {
    super.initState();
    _startCooldown();

    // İlk açılışta debug kodu otomatik doldur (production'da query param gelmez)
    final dev = GoRouter.of(context).routerDelegate
        .currentConfiguration.uri.queryParameters['dev'];
    if (dev != null && dev.length == 6) {
      _codeCtrl.text = dev;
    }
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _resendIn = 60);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 0) { t.cancel(); return; }
      setState(() => _resendIn -= 1);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_codeCtrl.text.length != 6) {
      setState(() => _error = '6 haneli kodu eksiksiz gir.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).verifyCustomerOtp(
        phone: widget.phone,
        code: _codeCtrl.text,
      );
      // Auth state set ediliyor → router otomatik home'a atar
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Beklenmedik bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (!_canResend || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).sendCustomerOtp(widget.phone);
      _startCooldown();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pretty = _prettyPhone(widget.phone);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FerxgoColors.ink,
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.customerPhone),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Kodu gir',
                style: TextStyle(
                  color: FerxgoColors.textHigh, fontSize: 28, fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: const TextStyle(color: FerxgoColors.textLow, fontSize: 14, height: 1.4),
                  children: [
                    const TextSpan(text: 'Sana SMS gönderdik: '),
                    TextSpan(
                      text: pretty,
                      style: const TextStyle(color: FerxgoColors.textHigh, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _OtpField(
                controller: _codeCtrl,
                focusNode: _focus,
                onChanged: (v) {
                  if (v.length == 6 && !_busy) _verify();
                },
              ),
              const SizedBox(height: 14),
              if (_error != null) ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: _canResend ? _resend : null,
                  child: Text(
                    _canResend ? 'Kodu yeniden gönder' : 'Kodu yeniden gönder ($_resendIn sn)',
                    style: TextStyle(
                      color: _canResend ? FerxgoColors.brand : FerxgoColors.textLow,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _verify,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                    : const Text('Doğrula ve devam et'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _prettyPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 12 && digits.startsWith('90')) {
      final rest = digits.substring(2);
      return '+90 ${rest.substring(0,3)} ${rest.substring(3,6)} ${rest.substring(6,8)} ${rest.substring(8)}';
    }
    return raw;
  }
}

class _OtpField extends StatelessWidget {
  const _OtpField({required this.controller, required this.focusNode, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      onChanged: onChanged,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: FerxgoColors.textHigh,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 14,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: const InputDecoration(
        counterText: '',
        hintText: '••••••',
        hintStyle: TextStyle(color: FerxgoColors.textLow, letterSpacing: 14),
      ),
    );
  }
}
