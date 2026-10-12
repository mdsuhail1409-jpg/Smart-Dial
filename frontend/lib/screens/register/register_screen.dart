import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widgets/smart_widgets.dart';
import '../../services/auth_service.dart';

/// Register Screen — Matches Figma Screen 2B (Authentication / Register)
/// Live connection to Render Cloud Backend.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String _selectedCountryCode = '+91';

  // Live Backend status indicator
  String _backendStatus = 'Checking...';
  Color _backendStatusColor = AppColors.amber;

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  Future<void> _checkBackend() async {
    final result = await ApiClient.health();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _backendStatus = 'Render Online';
        _backendStatusColor = AppColors.green;
      } else {
        _backendStatus = 'Connecting...';
        _backendStatusColor = AppColors.amber;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final phoneRaw = _phoneController.text.trim();
    final fullPhone = phoneRaw.startsWith('+')
        ? phoneRaw
        : '$_selectedCountryCode${phoneRaw.replaceAll(RegExp(r'\D'), '')}';

    final emailInput = _emailController.text.trim();
    final String email = emailInput.isNotEmpty
        ? emailInput
        : '${fullPhone.replaceAll(RegExp(r'\D'), '')}@smartdial.com';

    // Step 1: Send SMS OTP to verify phone number possession
    final otpRes = await AuthService.sendOtp(fullPhone);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!otpRes.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(otpRes.error ?? 'Could not send verification code'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final devCode = otpRes.data?['dev_code'] as String? ?? '';
    _showOtpVerificationSheet(fullPhone: fullPhone, email: email, devCode: devCode);
  }

  void _showOtpVerificationSheet({
    required String fullPhone,
    required String email,
    required String devCode,
  }) {
    final otpController = TextEditingController(text: devCode);
    bool isVerifying = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF131D33),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined,
                              color: AppColors.cyan, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'SIM Ownership Verification',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Code dispatched to $fullPhone',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (devCode.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.green.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: AppColors.green, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Verification Code: $devCode',
                                style: const TextStyle(
                                  color: AppColors.green,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Text(
                      'Enter 6-digit Code',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(
                        fontSize: 22,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.cyan, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: isVerifying
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(context);
                                setSheetState(() => isVerifying = true);
                                final code = otpController.text.trim();
                                final verifyRes = await AuthService.verifyOtp(
                                    fullPhone, code);

                                if (!verifyRes.isSuccess) {
                                  setSheetState(() => isVerifying = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(verifyRes.error ??
                                          'Invalid verification code'),
                                      backgroundColor: AppColors.red,
                                    ),
                                  );
                                  return;
                                }

                                // Code verified! Finalize user registration on Render
                                final error = await AuthService.register(
                                  name: _nameController.text.trim(),
                                  email: email,
                                  phone: fullPhone,
                                  password: _passwordController.text,
                                );

                                nav.pop();

                                if (error != null) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(error),
                                      backgroundColor: AppColors.red,
                                    ),
                                  );
                                  return;
                                }

                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'SIM verified & account registered successfully!'),
                                    backgroundColor: AppColors.green,
                                  ),
                                );
                                nav.pushReplacementNamed('/login');
                              },
                        child: isVerifying
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Verify & Complete Registration',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
        ),
        title: const Text(
          'SmartDial Account',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: _checkBackend,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _backendStatusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _backendStatusColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: _backendStatusColor),
                  const SizedBox(width: 5),
                  Text(
                    _backendStatus,
                    style: TextStyle(
                      color: _backendStatusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CONNECTED BY DESIGN',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                const Text(
                  'Register Phone',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'One account. Smarter connections. Bind your number to start calling in sync.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Full Name
                const Text(
                  'Full Name',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.person_outline,
                          size: 18, color: AppColors.textMuted),
                      hintText: 'Enter your full name',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Full name is required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Email Address
                const Text(
                  'Email Address',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.email_outlined,
                          size: 18, color: AppColors.textMuted),
                      hintText: 'youremail@gmail.com',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                    ),
                    validator: (v) {
                      if (v != null && v.trim().isNotEmpty && !v.contains('@')) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Phone number
                const Text(
                  'Phone number',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Text(
                              _selectedCountryCode == '+91' ? '🇮🇳' : '🇺🇸',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 4),
                            DropdownButton<String>(
                              value: _selectedCountryCode,
                              underline: const SizedBox(),
                              dropdownColor: AppColors.surfaceElevated,
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  color: AppColors.textSecondary, size: 18),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              items: const [
                                DropdownMenuItem(value: '+91', child: Text('+91')),
                                DropdownMenuItem(value: '+1', child: Text('+1')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedCountryCode = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: AppColors.border),
                      const SizedBox(width: 8),
                      const Icon(Icons.phone_android_outlined,
                          size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '98765 43210',
                            hintStyle: TextStyle(color: AppColors.textMuted),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Phone number is required';
                            }
                            if (v.trim().length < 7) {
                              return 'Enter a valid phone number';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                const Text(
                  'Password',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.key_outlined,
                          size: 18, color: AppColors.textMuted),
                      hintText: 'Create a password (min 8 characters)',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),

                const SimVerifiedCard(),
                const SizedBox(height: 24),

                // Continue Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                      shadowColor: AppColors.primary.withValues(alpha: 0.5),
                    ),
                    onPressed: _isLoading ? null : _register,
                    child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Registering on Render Cloud...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.arrow_forward, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                    child: RichText(
                      text: const TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                        children: [
                          TextSpan(
                            text: 'Sign In',
                            style: TextStyle(
                              color: AppColors.cyan,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 14, color: AppColors.textMuted),
                      SizedBox(width: 6),
                      Text(
                        'Secure SIM binding. Live on Render Cloud.',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
