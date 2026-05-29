import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_constants.dart';
import '../../providers/providers.dart';

// ─── Shared form field widget ─────────────────────────────────────────────────

class _AppField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType keyboard;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final Widget? prefix;
  final int maxLines;

  const _AppField({
    required this.label,
    this.hint,
    required this.controller,
    this.obscure = false,
    this.keyboard = TextInputType.text,
    this.validator,
    this.suffix,
    this.prefix,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelLarge),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          maxLines: maxLines,
          validator: validator,
          style: AppTextStyles.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
            prefixIcon: prefix,
          ),
        ),
      ],
    );
  }
}

// ─── Register Screen ──────────────────────────────────────────────────────────

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Store phone for OTP screen, navigate to account type first
    context.go('/account-type', extra: _phoneCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back
                IconButton(
                  onPressed: () => context.go('/onboarding'),
                  icon: const Icon(Icons.arrow_back_ios_new),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 24),

                Text('Create account', style: AppTextStyles.displayMedium),
                const SizedBox(height: 6),
                Text('Join thousands of verified users',
                    style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textSecondary)),
                const SizedBox(height: 36),

                _AppField(
                  label: 'Full name',
                  hint: 'Amaka Johnson',
                  controller: _nameCtrl,
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? 'Enter your full name'
                      : null,
                ),
                const SizedBox(height: 20),

                _AppField(
                  label: 'Phone number',
                  hint: '08012345678',
                  controller: _phoneCtrl,
                  keyboard: TextInputType.phone,
                  validator: (v) {
                    final clean = (v ?? '').replaceAll(' ', '');
                    if (clean.length < 10) return 'Enter a valid phone number';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                _AppField(
                  label: 'Password',
                  hint: 'Min. 8 chars, 1 uppercase, 1 number',
                  controller: _passwordCtrl,
                  obscure: !_showPassword,
                  validator: (v) {
                    if ((v?.length ?? 0) < 8) return 'Password must be at least 8 characters';
                    if (!v!.contains(RegExp(r'[A-Z]'))) return 'Include at least one uppercase letter';
                    if (!v.contains(RegExp(r'[0-9]'))) return 'Include at least one number';
                    return null;
                  },
                  suffix: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                const SizedBox(height: 12),

                // Error
                if (auth.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: AppRadius.cardRadius,
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(auth.error!,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.error)),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : _submit,
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Continue'),
                ),
                const SizedBox(height: 24),

                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    child: RichText(
                      text: TextSpan(
                        style: AppTextStyles.bodyMedium,
                        children: [
                          TextSpan(
                              text: 'Already have an account? ',
                              style: TextStyle(color: AppColors.textSecondary)),
                          TextSpan(
                              text: 'Login',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
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
    );
  }
}

// ─── Account Type Screen ──────────────────────────────────────────────────────

class AccountTypeScreen extends ConsumerStatefulWidget {
  final String phone;
  const AccountTypeScreen({super.key, required this.phone});

  @override
  ConsumerState<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends ConsumerState<AccountTypeScreen> {
  String _selected = 'client';

  final _types = [
    _TypeOption(
      role: 'client',
      emoji: '🙋',
      title: 'Client',
      subtitle: 'Post tasks and hire verified agents',
      color: AppColors.primary,
    ),
    _TypeOption(
      role: 'agent',
      emoji: '⚡',
      title: 'Errand Agent',
      subtitle: 'Earn money completing tasks near you',
      color: AppColors.secondary,
    ),
    _TypeOption(
      role: 'business',
      emoji: '🏢',
      title: 'Business',
      subtitle: 'Manage office errands at scale',
      color: Color(0xFF7C3AED),
    ),
  ];

  Future<void> _confirm() async {
    // We stored name+password in register screen state — for simplicity,
    // navigate to OTP and pass phone + role
    context.go('/otp', extra: widget.phone);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.go('/register'),
                icon: const Icon(Icons.arrow_back_ios_new),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),
              Text('How will you\nuse the app?', style: AppTextStyles.displayMedium),
              const SizedBox(height: 8),
              Text('You can change this later',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 36),

              ..._types.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _TypeCard(
                      option: t,
                      selected: _selected == t.role,
                      onTap: () => setState(() => _selected = t.role),
                    ),
                  )),

              const Spacer(),
              ElevatedButton(
                onPressed: _confirm,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeOption {
  final String role, emoji, title, subtitle;
  final Color color;
  const _TypeOption({
    required this.role,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}

class _TypeCard extends StatelessWidget {
  final _TypeOption option;
  final bool selected;
  final VoidCallback onTap;
  const _TypeCard({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected
              ? option.color.withOpacity(0.06)
              : AppColors.surfaceVariant,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: selected ? option.color : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(option.emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.title, style: AppTextStyles.h3),
                  const SizedBox(height: 2),
                  Text(option.subtitle,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: option.color, size: 22),
          ],
        ),
      ),
    );
  }
}

// ─── OTP Screen ───────────────────────────────────────────────────────────────

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpCtrl = TextEditingController();
  int _secondsLeft = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    setState(() {
      _secondsLeft = 60;
      _canResend = false;
    });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        setState(() => _canResend = true);
        return false;
      }
      return true;
    });
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) return;
    final ok = await ref
        .read(authProvider.notifier)
        .verifyPhone(widget.phone, code);
    if (!mounted) return;
    if (ok) {
      final user = ref.read(authProvider).user;
      context.go(user?.isAgent == true ? '/agent/home' : '/client/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final maskedPhone = widget.phone.length > 6
        ? '${widget.phone.substring(0, 6)}****${widget.phone.substring(widget.phone.length - 2)}'
        : widget.phone;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.go('/register'),
                icon: const Icon(Icons.arrow_back_ios_new),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),
              Text('Verify your\nphone', style: AppTextStyles.displayMedium),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: AppColors.textSecondary),
                  children: [
                    const TextSpan(text: 'Enter the 6-digit code sent to '),
                    TextSpan(
                        text: maskedPhone,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // OTP input
              TextFormField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: AppTextStyles.displayMedium.copyWith(
                  letterSpacing: 16,
                  color: AppColors.primary,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '------',
                  hintStyle: AppTextStyles.displayMedium.copyWith(
                    color: AppColors.textDisabled,
                    letterSpacing: 16,
                  ),
                ),
                onChanged: (v) {
                  if (v.length == 6) _verify();
                },
              ),
              const SizedBox(height: 24),

              // Error
              if (auth.error != null)
                Text(
                  auth.error!,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                ),

              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: auth.isLoading ? null : _verify,
                child: auth.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Verify'),
              ),
              const SizedBox(height: 20),

              // Resend
              Center(
                child: _canResend
                    ? TextButton(
                        onPressed: () async {
                          await apiService.resendOtp(widget.phone);
                          _startTimer();
                        },
                        child: Text('Resend code',
                            style: AppTextStyles.labelLarge
                                .copyWith(color: AppColors.primary)),
                      )
                    : Text(
                        'Resend code in $_secondsLeft seconds',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Login Screen ─────────────────────────────────────────────────────────────

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authProvider.notifier).login(
          _identifierCtrl.text.trim(),
          _passwordCtrl.text,
        );
    if (ok && mounted) {
      final user = ref.read(authProvider).user;
      context.go(user?.isAgent == true ? '/agent/home' : '/client/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => context.go('/onboarding'),
                  icon: const Icon(Icons.arrow_back_ios_new),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 24),
                Text('Welcome back', style: AppTextStyles.displayMedium),
                const SizedBox(height: 6),
                Text('Login to your account',
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 36),

                _AppField(
                  label: 'Phone or email',
                  hint: '08012345678 or email@example.com',
                  controller: _identifierCtrl,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Enter phone or email'
                      : null,
                ),
                const SizedBox(height: 20),

                _AppField(
                  label: 'Password',
                  controller: _passwordCtrl,
                  obscure: !_showPassword,
                  validator: (v) =>
                      (v?.isEmpty ?? true) ? 'Enter password' : null,
                  suffix: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    child: Text('Forgot password?',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: AppColors.primary)),
                  ),
                ),

                if (auth.error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: AppRadius.cardRadius,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(auth.error!,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.error)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : _login,
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Login'),
                ),
                const SizedBox(height: 24),

                Center(
                  child: TextButton(
                    onPressed: () => context.go('/register'),
                    child: RichText(
                      text: TextSpan(
                        style: AppTextStyles.bodyMedium,
                        children: [
                          TextSpan(
                              text: 'Don\'t have an account? ',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                          TextSpan(
                              text: 'Sign up',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
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
    );
  }
}
