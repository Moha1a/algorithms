import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/iraqi_phone_utils.dart';
import '../theme/app_colors.dart';
import 'admin_dashboard_screen.dart';
import 'home_shell_screen.dart';
import 'otp_verification_screen.dart';
import 'outlet_approval_pending_screen.dart';
import 'role_selection_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  static const routeName = '/auth';

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _adminPhone = '+9647733832043';
  static const _adminPassword = 'ALskQPwo0099@&';
  static const bool appPreviewSafeMode =
      bool.fromEnvironment('APP_PREVIEW_SAFE_MODE', defaultValue: false);

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _outletNameController = TextEditingController();

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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(String selectedRole) async {
    debugPrint('LOGIN_BUTTON_PRESSED');
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    debugPrint('LOGIN_INPUT_VALIDATED');
    debugPrint('LOGIN_TRY_START');

    if (kIsWeb) {
      _showMessage('تسجيل OTP المدمج متاح على Android/iOS فقط في هذا الإصدار.');
      return;
    }

    final normalizedPhone = IraqiPhoneUtils.normalize(_phoneController.text);
    final isAdminOutletLogin = _isLogin &&
        selectedRole == 'outlet' &&
        normalizedPhone == _adminPhone &&
        _passwordController.text == _adminPassword;
    if (isAdminOutletLogin) {
      _safeNavigate(() {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      });
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    var flowHandled = false;

    if (appPreviewSafeMode) {
      debugPrint('APP_PREVIEW_SAFE_MODE_ENABLED');
      debugPrint('PHONE_AUTH_SKIPPED_IN_PREVIEW');
      debugPrint('LOGIN_PREVIEW_SAFE_PATH_START');
      try {
        if (!_isLogin) {
          throw FirebaseAuthException(
            code: 'preview-phone-auth-disabled',
            message: 'إنشاء حساب عبر OTP غير متاح في وضع المعاينة.',
          );
        }
        final profile = await _authService.loginWithPhonePasswordPreview(
          role: selectedRole,
          phoneNumber: normalizedPhone,
          password: _passwordController.text,
        );
        if (!mounted) return;
        debugPrint('LOGIN_PREVIEW_SAFE_PATH_SUCCESS');
        debugPrint('NAVIGATION_START');
        _openPostAuthScreen(profile);
      } on FirebaseAuthException catch (e) {
        debugPrint('LOGIN_PREVIEW_SAFE_PATH_FAILED: ${e.code}');
        debugPrint('LOGIN_CATCH_ERROR: ${e.code}');
        debugPrint('LOGIN_FAILED_CONTROLLED');
        _showMessage(_authService.mapFirebaseAuthError(e));
        _showDebugErrorDialog(e.toString());
        if (e.code == 'missing-user-doc' || e.code == 'user-profile-load-failed') {
          _safeNavigate(() {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
              (_) => false,
            );
          });
        }
      } catch (e, stackTrace) {
        debugPrint('LOGIN_PREVIEW_SAFE_PATH_FAILED: $e');
        debugPrint('$stackTrace');
        debugPrint('LOGIN_CATCH_ERROR: $e');
        debugPrint('LOGIN_FAILED_CONTROLLED');
        _showMessage('حدث خطأ أثناء تسجيل الدخول. حاول مرة أخرى.');
        _showDebugErrorDialog(e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

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
            final isOutletRegistrationPending = !_isLogin &&
                selectedRole == 'outlet' &&
                (profile['approvalStatus'] ?? '').toString() == 'pending';
            if (isOutletRegistrationPending) {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              debugPrint('NAVIGATION_START');
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => OutletApprovalPendingScreen(phoneNumber: normalizedPhone),
                ),
                (_) => false,
              );
              return;
            }
            debugPrint('NAVIGATION_START');
            _openPostAuthScreen(profile);
          } on FirebaseAuthException catch (e) {
            flowHandled = false;
            debugPrint('LOGIN_CATCH_ERROR: ${e.code}');
            debugPrint('LOGIN_FAILED_CONTROLLED');
            _showMessage(_authService.mapFirebaseAuthError(e));
            _showDebugErrorDialog(e.toString());
          } catch (e, stackTrace) {
            flowHandled = false;
            debugPrint('LOGIN_CATCH_ERROR: $e');
            debugPrint('$stackTrace');
            debugPrint('LOGIN_FAILED_CONTROLLED');
            _showMessage('حدث خطأ أثناء تسجيل الدخول. حاول مرة أخرى.');
            _showDebugErrorDialog(e.toString());
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
        verificationFailed: (e) {
          flowHandled = true;
          debugPrint('LOGIN_CATCH_ERROR: ${e.code}');
          debugPrint('LOGIN_FAILED_CONTROLLED');
          _showMessage(_authService.mapFirebaseAuthError(e));
          _showDebugErrorDialog(e.toString());
          if (mounted) setState(() => _isLoading = false);
        },
        codeSent: (verificationId, resendToken) {
          if (flowHandled) return;
          flowHandled = true;
          if (!mounted) return;
          setState(() => _isLoading = false);
          debugPrint('NAVIGATION_START');
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
    } on FirebaseAuthException catch (e) {
      debugPrint('LOGIN_CATCH_ERROR: ${e.code}');
      debugPrint('LOGIN_FAILED_CONTROLLED');
      _showMessage(_authService.mapFirebaseAuthError(e));
      _showDebugErrorDialog(e.toString());
      if (mounted) setState(() => _isLoading = false);
    } on FirebaseException catch (e) {
      debugPrint('LOGIN_CATCH_ERROR: ${e.code}');
      debugPrint('LOGIN_FAILED_CONTROLLED');
      _showMessage('حدث خطأ في الخدمة. حاول مرة أخرى.');
      _showDebugErrorDialog(e.toString());
      if (mounted) setState(() => _isLoading = false);
    } on PlatformException catch (e) {
      debugPrint('LOGIN_CATCH_ERROR: ${e.code}');
      debugPrint('LOGIN_FAILED_CONTROLLED');
      _showMessage('حدث خطأ بالنظام. حاول مرة أخرى.');
      _showDebugErrorDialog(e.toString());
      if (mounted) setState(() => _isLoading = false);
    } on FormatException catch (e) {
      debugPrint('LOGIN_CATCH_ERROR: $e');
      debugPrint('LOGIN_FAILED_CONTROLLED');
      _showMessage('البيانات غير صالحة. حاول مرة أخرى.');
      _showDebugErrorDialog(e.toString());
      if (mounted) setState(() => _isLoading = false);
    } catch (e, stackTrace) {
      debugPrint('LOGIN_CATCH_ERROR: $e');
      debugPrint('$stackTrace');
      debugPrint('LOGIN_FAILED_CONTROLLED');
      _showMessage('حدث خطأ أثناء تسجيل الدخول. حاول مرة أخرى.');
      _showDebugErrorDialog(e.toString());
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
    if (mounted) setState(() => _isLoading = true);
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

  void _openPostAuthScreen(Map<String, dynamic> profile) {
    _safeNavigate(() {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeShellScreen(profile: profile),
        ),
      );
    });
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showDebugErrorDialog(String details) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('خطأ أثناء تسجيل الدخول'),
        content: SingleChildScrollView(
          child: Text(
            details,
            textDirection: TextDirection.ltr,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
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