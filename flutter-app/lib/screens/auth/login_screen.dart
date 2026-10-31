import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final mobile = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;
  String? validationError;

  @override
  void dispose() {
    mobile.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final error = validationError ?? app.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
                    decoration: BoxDecoration(
                      color: ExcelBrand.surface,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: ExcelBrand.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0D0B8F48),
                          blurRadius: 28,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 190,
                            height: 108,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Image.asset(
                              'assets/branding/excel-herbal-logo.webp',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Employee Workspace',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Secure access to your authorised Excel Herbal ERP workspace.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: ExcelBrand.muted),
                        ),
                        if (AppConfig.isUat) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'UAT BUILD',
                                style: TextStyle(
                                  color: Color(0xFF9A5B00),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .6,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        TextField(
                          controller: mobile,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => _clearValidationError(),
                          decoration: const InputDecoration(
                            labelText: 'Mobile number',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: password,
                          obscureText: obscure,
                          onChanged: (_) => _clearValidationError(),
                          onSubmitted: (_) => _login(app.loading),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => obscure = !obscure),
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 20,
                                  color: ExcelBrand.danger,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    error,
                                    style: const TextStyle(
                                      color: Color(0xFF8C2D2D),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: app.loading ? null : () => _login(false),
                          child: app.loading
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('SIGN IN'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Live Natural, Live Herbal',
                    style: TextStyle(
                      color: ExcelBrand.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _clearValidationError() {
    if (validationError != null) {
      setState(() => validationError = null);
    }
  }

  void _login(bool loading) {
    if (loading) return;
    final mobileValue = mobile.text.trim();
    if (mobileValue.isEmpty) {
      setState(() => validationError = 'Enter your mobile number.');
      return;
    }
    if (password.text.isEmpty) {
      setState(() => validationError = 'Enter your password.');
      return;
    }
    if (validationError != null) {
      setState(() => validationError = null);
    }
    ref.read(appStateProvider.notifier).login(mobileValue, password.text);
  }
}
