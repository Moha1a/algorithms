import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/iraqi_phone_utils.dart';
import '../theme/app_colors.dart';
import 'admin_dashboard_screen.dart';
import 'home_shell_screen.dart';
import 'otp_verification_screen.dart';
import 'role_selection_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  static const routeName = '/auth';

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _adminEmail = 'Amma1212@gmail.com';
  static const _adminPassword = 'ALskQPwo0099@&';

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _outletNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();

  final AuthService _authService = AuthService();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isNavigating = false;
  final String _selectedGovernorate = 'البصرة';

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _outletNameController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ModalRoute.of(context)?.settings.arguments as UserRole?;
    final roleLabel = role == UserRole.outlet ? 'منفذ' : 'عميل';
    final roleValue = role == UserRole.outlet ? 'outlet' : 'client';
    final needOutletName = !_isLogin && role == UserRole.outlet;

    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'تسجيل الدخول برقم الهاتف' : 'إنشاء حساب برقم الهاتف')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF4E0), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'نوع الحساب المختار: $roleLabel',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    children: [
                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _fullNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                          validator: (v) {
                            if (_isLogin) return null;
                            if (v == null || v.trim().isEmpty) return 'يرجى إدخال الاسم الكامل';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: _selectedGovernorate,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'المحافظة',
                            suffixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (needOutletName) ...[
                        TextFormField(
                          controller: _outletNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'اسم المنفذ'),
                          validator: (v) {
                            if (!needOutletName) return null;
                            if (v == null || v.trim().isEmpty) return 'يرجى إدخال اسم المنفذ';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                              color: const Color(0xFFFCFCFF),
                            ),
                            child: const Text(
                              '+964',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'رقم الهاتف',
                                hintText: '07xxxxxxxxx أو 7xxxxxxxxx',
                              ),
                              validator: (v) => IraqiPhoneUtils.validate(v ?? ''),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'كلمة المرور'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'يرجى إدخال كلمة المرور';
                          if (v.trim().length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _isLoading ? null : () => _submit(roleValue),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: _isLoading
                              ? const SizedBox.shrink()
                              : const Icon(Icons.login_rounded, color: Colors.white),
                          label: _isLoading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_isLogin ? 'متابعة' : 'إرسال رمز التحقق'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : () => _enterTestAccount('client'),
                              child: const Text('دخول تجريبي كعميل'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : () => _enterTestAccount('outlet'),
                              child: const Text('دخول تجريبي كمنفذ'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _isLoading ? null : () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? 'ما عندك حساب؟ إنشاء حساب جديد' : 'عندك حساب؟ تسجيل الدخول',
                    style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700),
                  ),
                ),

                TextButton(
                  onPressed: _isLoading ? null : _openForgotPasswordFlow,
                  child: const Text(
                    'نسيت كلمة المرور؟',
                    style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w700),
                  ),
                ),
                ExpansionTile(
                  title: const Text('دخول المشرف (النظام الحالي)'),
                  children: [
                    TextField(
                      controller: _adminEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _adminPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'كلمة المرور'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _isLoading ? null : _loginAdmin,
                      child: const Text('تسجيل دخول المشرف'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(String selectedRole) async {
    if (!_formKey.currentState!.validate()) return;

    if (kIsWeb) {
      _showMessage('تسجيل OTP المدمج متاح على Android/iOS فقط في هذا الإصدار.');
      return;
    }

    final normalizedPhone = IraqiPhoneUtils.normalize(_phoneController.text);
    setState(() => _isLoading = true);
    var flowHandled = false;

    try {
      if (_isLogin) {
        await _authService.assertLoginPasswordBeforeOtp(
          phoneNumber: normalizedPhone,
          password: _passwordController.text,
          role: selectedRole,
        );
      }
      await _authService.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        verificationCompleted: (credential) async {
          if (flowHandled) return;
          flowHandled = true;
          try {
            final profile = await _authService.loginOrRegisterWithCredential(
              credential: credential,
              role: selectedRole,
              phoneNumber: normalizedPhone,
              isRegistration: !_isLogin,
              fullName: _fullNameController.text,
              governorate: _selectedGovernorate,
              outletName: _outletNameController.text,
              password: _passwordController.text,
            );
            if (!mounted) return;
            _openPostAuthScreen(profile);
          } on FirebaseAuthException catch (e) {
            flowHandled = false;
            _showMessage(_authService.mapFirebaseAuthError(e));
          }
        },
        verificationFailed: (e) {
          flowHandled = true;
          _showMessage(_authService.mapFirebaseAuthError(e));
          if (mounted) setState(() => _isLoading = false);
        },
        codeSent: (verificationId, resendToken) {
          if (flowHandled) return;
          flowHandled = true;
          if (!mounted) return;
          setState(() => _isLoading = false);
          _safeNavigate(() {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OtpVerificationScreen(
                  authService: _authService,
                  phoneNumber: normalizedPhone,
                  initialVerificationId: verificationId,
                  initialResendToken: resendToken,
                  role: selectedRole,
                  isRegistration: !_isLogin,
                  fullName: _fullNameController.text,
                  governorate: _selectedGovernorate,
                  outletName: _outletNameController.text,
                  password: _passwordController.text,
                ),
              ),
            );
          });
        },
        codeAutoRetrievalTimeout: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } catch (e) {
      _showMessage(_authService.mapFirebaseAuthError(e));
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _openForgotPasswordFlow() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('استعادة كلمة المرور'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            hintText: '07xxxxxxxxx أو 7xxxxxxxxx',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('متابعة')),
        ],
      ),
    );

    if (ok != true) return;
    final err = IraqiPhoneUtils.validate(controller.text);
    if (err != null) {
      _showMessage(err);
      return;
    }
    if (kIsWeb) {
      _showMessage('استعادة كلمة المرور عبر OTP مدعومة على Android/iOS فقط في هذا الإصدار.');
      return;
    }

    final normalized = IraqiPhoneUtils.normalize(controller.text);
    setState(() => _isLoading = true);
    var flowHandled = false;
    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: normalized,
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          flowHandled = true;
          _showMessage(_authService.mapFirebaseAuthError(e));
          if (mounted) setState(() => _isLoading = false);
        },
        codeSent: (verificationId, resendToken) {
          if (flowHandled) return;
          flowHandled = true;
          if (!mounted) return;
          setState(() => _isLoading = false);
          _safeNavigate(() {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OtpVerificationScreen(
                  authService: _authService,
                  phoneNumber: normalized,
                  initialVerificationId: verificationId,
                  initialResendToken: resendToken,
                  isPasswordResetFlow: true,
                ),
              ),
            );
          });
        },
        codeAutoRetrievalTimeout: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } catch (e) {
      _showMessage(_authService.mapFirebaseAuthError(e));
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enterTestAccount(String role) async {
    setState(() => _isLoading = true);
    try {
      final profile = await _authService.loginAsTestAccount(role: role);
      if (!mounted) return;
      _openPostAuthScreen(profile);
    } on FirebaseAuthException catch (e) {
      _showMessage(_authService.mapFirebaseAuthError(e));
    } catch (e) {
      _showMessage('تعذر الدخول التجريبي. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openPostAuthScreen(Map<String, dynamic> profile) {
    _safeNavigate(() {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeShellScreen(profile: profile),
        ),
      );
    });
  }

  void _loginAdmin() {
    final isAdminLogin = _adminEmailController.text.trim().toLowerCase() == _adminEmail.toLowerCase() &&
        _adminPasswordController.text == _adminPassword;
    if (!isAdminLogin) {
      _showMessage('بيانات المشرف غير صحيحة');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
    );
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _safeNavigate(VoidCallback action) {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isNavigating = false;
        return;
      }
      action();
      _isNavigating = false;
    });
  }
}
