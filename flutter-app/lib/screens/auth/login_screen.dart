import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';

/// Purpose-built V8 sign-in. UI only; the original authenticated API stays
/// the sole authority for credentials, sessions, roles and branch access.
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
      backgroundColor: ExcelBrand.canvas,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final spacious = constraints.maxWidth >= 920;
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(spacious ? 26 : 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1150),
                child: spacious
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(flex: 6, child: _IntroductionPanel()),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 5,
                            child: _signInPanel(context, app.loading, error),
                          ),
                        ],
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _signInPanel(context, app.loading, error),
                      ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _signInPanel(BuildContext context, bool loading, String? error) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('v8-command-login'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(27, 30, 27, 27),
      decoration: BoxDecoration(
        color: ExcelBrand.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ExcelBrand.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B28345C),
            blurRadius: 32,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ExcelBrand.primarySoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.eco_outlined,
                  color: ExcelBrand.primaryDark, size: 25),
            ),
            const SizedBox(width: 11),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EXCEL HERBAL', maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ExcelBrand.ink,
                    fontSize: 14, fontWeight: FontWeight.w900)),
                SizedBox(height: 2),
                Text('ERP V8  /  COMMAND CENTER',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ExcelBrand.muted,
                    fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: .45)),
              ],
            )),
          ]),
          const SizedBox(height: 28),
          Text('Welcome back',
            style: text.headlineMedium?.copyWith(
              color: ExcelBrand.ink,
              fontWeight: FontWeight.w900,
              letterSpacing: -.5)),
          const SizedBox(height: 7),
          Text('Sign in to your secure Excel Herbal workspace.',
            style: text.bodyMedium?.copyWith(
              color: ExcelBrand.muted, height: 1.5)),
          if (AppConfig.isUat) ...[
            const SizedBox(height: 13),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E2),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text('UAT BUILD',
                  style: TextStyle(
                    color: Color(0xFF925400), fontSize: 10,
                    fontWeight: FontWeight.w800, letterSpacing: .65)),
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text('MOBILE NUMBER',
            style: text.labelSmall?.copyWith(
              color: ExcelBrand.sidebarText,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
            )),
          const SizedBox(height: 7),
          TextField(
            controller: mobile,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            onChanged: (_) => _clearValidationError(),
            decoration: const InputDecoration(
              hintText: 'Enter registered mobile number',
              labelText: 'Mobile number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 18),
          Text('PASSWORD',
            style: text.labelSmall?.copyWith(
              color: ExcelBrand.sidebarText,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
            )),
          const SizedBox(height: 7),
          TextField(
            controller: password,
            obscureText: obscure,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onChanged: (_) => _clearValidationError(),
            onSubmitted: (_) => _login(loading),
            decoration: InputDecoration(
              hintText: 'Enter password',
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                      size: 20, color: ExcelBrand.danger),
                    const SizedBox(width: 9),
                    Expanded(child: Text(
                      error,
                      style: const TextStyle(
                        color: Color(0xFF902C3A),
                        fontWeight: FontWeight.w600,
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              key: const ValueKey('v8-command-signin'),
              onPressed: loading ? null : () => _login(false),
              icon: loading
                  ? const SizedBox.square(
                      dimension: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_forward_rounded),
              label: const Text('Sign in to workspace'),
            ),
          ),
          const SizedBox(height: 17),
          Text('Only authorised employees can access company records.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: ExcelBrand.muted)),
        ],
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

class _IntroductionPanel extends StatelessWidget {
  const _IntroductionPanel();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('v8-command-login-intro'),
      constraints: const BoxConstraints(minHeight: 570),
      padding: const EdgeInsets.all(43),
      decoration: BoxDecoration(
        color: const Color(0xFF252645),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58, height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF3C3C66),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.eco_outlined,
              color: Color(0xFFC8C1FF), size: 32),
          ),
          const SizedBox(height: 66),
          const Text('YOUR BUSINESS. ONE PLACE.',
            style: TextStyle(
              color: Color(0xFFC6BFFF),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.35,
            )),
          const SizedBox(height: 18),
          Text('Work beautifully.\nStay in control.',
            style: text.displaySmall?.copyWith(
              color: Colors.white, fontWeight: FontWeight.w900,
              height: 1.1, letterSpacing: -.8)),
          const SizedBox(height: 21),
          Text(
            'A cleaner way to manage daily work, stock, approvals and your own records.',
            style: text.bodyLarge?.copyWith(
              color: const Color(0xFFDCDEF0), height: 1.55)),
          const SizedBox(height: 64),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: const Color(0xFF333556),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF44456A)),
            ),
            child: const Row(children: [
              Icon(Icons.verified_user_outlined,
                color: Color(0xFFC8C1FF), size: 22),
              SizedBox(width: 12),
              Expanded(child: Text(
                'Role-based access. Your branch. Your workflow.',
                style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, height: 1.35))),
            ]),
          ),
          const SizedBox(height: 32),
          const Text('LIVE NATURAL. LIVE HERBAL.',
            style: TextStyle(
              color: Color(0xFFBCC3DF),
              fontWeight: FontWeight.w800,
              fontSize: 10, letterSpacing: 1.1)),
        ],
      ),
    );
  }
}
