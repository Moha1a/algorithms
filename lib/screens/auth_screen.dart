import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/input_digit_utils.dart';
import '../services/iraqi_phone_utils.dart';
import '../theme/app_colors.dart';
import 'admin_dashboard_screen.dart';
import 'app_review_access_screen.dart';
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
  static const _termsVersion = '2026-05-13';

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _outletNameController = TextEditingController();

  final AuthService _authService = AuthService();
  bool _isLogin = false;
  bool _isLoading = false;
  bool _isNavigating = false;
  bool _acceptedTerms = false;
  bool _passwordVisible = false;
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
    final registrationTerms = _termsForRole(roleValue);

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
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/monfathak_logo.png',
                      width: 190,
                      height: 76,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                              inputFormatters: const [PhoneNumberInputFormatter()],
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'رقم الهاتف',
                                hintText: '07xxxxxxxxx أو 7xxxxxxxxx',
                              ),
                              validator: (v) {
                                if (_isLogin && AuthService.isAppReviewPhoneInput(v ?? '')) return null;
                                return IraqiPhoneUtils.validate(v ?? '');
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_passwordVisible,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          suffixIcon: IconButton(
                            tooltip: _passwordVisible ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
                            icon: Icon(
                              _passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            ),
                            onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'يرجى إدخال كلمة المرور';
                          if (v.trim().length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                          return null;
                        },
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 16),
                        _buildTermsCard(
                          roleLabel: roleLabel,
                          terms: registrationTerms,
                        ),
                        CheckboxListTile(
                          value: _acceptedTerms,
                          onChanged: _isLoading
                              ? null
                              : (value) => setState(() => _acceptedTerms = value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'أوافق على الشروط والأحكام',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'لا يمكن إكمال التسجيل قبل الموافقة عليها.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      ],
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
    debugPrint('[LOGIN FLOW] button pressed');
    final isAppReviewAccess = AuthService.isAppReviewCredentials(
      phoneNumber: _phoneController.text,
      password: _passwordController.text,
    );
    if (isAppReviewAccess) {
      _safeNavigate(() {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AppReviewAccessScreen(
              phoneNumber: _phoneController.text,
              password: _passwordController.text,
            ),
          ),
        );
      });
      return;
    }

    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    if (!_isLogin && !_acceptedTerms) {
      _showMessage('يرجى الموافقة على الشروط والأحكام لإكمال التسجيل.');
      return;
    }
    debugPrint('[LOGIN FLOW] input validated');
    debugPrint('[LOGIN FLOW] try start');

    if (kIsWeb) {
      _showMessage('تسجيل OTP المدمج متاح على Android/iOS فقط في هذا الإصدار.');
      return;
    }

    final normalizedPhone = IraqiPhoneUtils.normalize(_phoneController.text);
    debugPrint('[LOGIN INPUT] rawPhone=${_phoneController.text} countryCode=+964 normalizedPhone=$normalizedPhone role=$selectedRole');
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

    try {
      if (_isLogin) {
        await _authService.assertLoginPasswordBeforeOtp(
          phoneNumber: normalizedPhone,
          password: _passwordController.text,
          role: selectedRole,
        );
      }
      debugPrint('otp_start_after_password_success role=$selectedRole');
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
              acceptedTerms: _acceptedTerms,
              termsVersion: _termsVersion,
              acceptedTermsItems: _termsForRole(selectedRole),
            );
            if (!mounted) return;
            final isOutletRegistrationPending = !_isLogin &&
                selectedRole == 'outlet' &&
                (profile['approvalStatus'] ?? '').toString() == 'pending';
            if (isOutletRegistrationPending) {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              debugPrint('[LOGIN FLOW] navigation start');
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => OutletApprovalPendingScreen(phoneNumber: normalizedPhone),
                ),
                (_) => false,
              );
              return;
            }
            debugPrint('[LOGIN FLOW] navigation start');
            _openPostAuthScreen(profile);
          } on FirebaseAuthException catch (e) {
            debugPrint('PHONE_AUTH_EXCEPTION_CAUGHT');
            flowHandled = false;
            debugPrint('[LOGIN FLOW] error code: ${e.code}');
            debugPrint('[LOGIN FLOW] controlled failure');
            _showMessage(_authService.mapFirebaseAuthError(e));
            _showDebugErrorDialog(e.toString());
          } catch (e, stackTrace) {
            flowHandled = false;
            debugPrint('LOGIN_CATCH_ERROR: $e');
            debugPrint('$stackTrace');
            debugPrint('[LOGIN FLOW] controlled failure');
            _showMessage('حدث خطأ أثناء تسجيل الدخول. حاول مرة أخرى.');
            _showDebugErrorDialog(e.toString());
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
        verificationFailed: (e) {
          flowHandled = true;
          debugPrint('PHONE_AUTH_VERIFY_FAILED');
          debugPrint('[LOGIN FLOW] error code: ${e.code}');
          debugPrint('[LOGIN FLOW] controlled failure');
          _showMessage(_authService.mapFirebaseAuthError(e));
          _showDebugErrorDialog(e.toString());
          if (mounted) setState(() => _isLoading = false);
        },
        codeSent: (verificationId, resendToken) {
          debugPrint('PHONE_AUTH_CODE_SENT');
          if (flowHandled) return;
          flowHandled = true;
          if (!mounted) return;
          setState(() => _isLoading = false);
          debugPrint('[LOGIN FLOW] navigation start');
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
                  acceptedTerms: _acceptedTerms,
                  termsVersion: _termsVersion,
                  acceptedTermsItems: _termsForRole(selectedRole),
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
      debugPrint('PHONE_AUTH_EXCEPTION_CAUGHT');
      debugPrint('[LOGIN FLOW] error code: ${e.code}');
      debugPrint('[LOGIN FLOW] controlled failure');
      _showMessage(_authService.mapFirebaseAuthError(e));
      _showDebugErrorDialog(e.toString());
      if (mounted) setState(() => _isLoading = false);
    } on FirebaseException catch (e) {
      debugPrint('PHONE_AUTH_EXCEPTION_CAUGHT');
      debugPrint('[LOGIN FLOW] error code: ${e.code}');
      debugPrint('[LOGIN FLOW] controlled failure');
      _showMessage('حدث خطأ في الخدمة. حاول مرة أخرى.');
      _showDebugErrorDialog(e.toString());
      if (mounted) setState(() => _isLoading = false);
    } on PlatformException catch (e) {
      debugPrint('PHONE_AUTH_EXCEPTION_CAUGHT');
      debugPrint('[LOGIN FLOW] error code: ${e.code}');
      debugPrint('[LOGIN FLOW] controlled failure');
      _showMessage('حدث خطأ بالنظام. حاول مرة أخرى.');
      _showDebugErrorDialog(e.toString());
      if (mounted) setState(() => _isLoading = false);
    } on FormatException catch (e) {
      debugPrint('LOGIN_CATCH_ERROR: $e');
      debugPrint('[LOGIN FLOW] controlled failure');
      _showMessage('البيانات غير صالحة. حاول مرة أخرى.');
      _showDebugErrorDialog(e.toString());
      if (mounted) setState(() => _isLoading = false);
    } catch (e, stackTrace) {
      debugPrint('LOGIN_CATCH_ERROR: $e');
      debugPrint('$stackTrace');
      debugPrint('[LOGIN FLOW] controlled failure');
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
          inputFormatters: const [PhoneNumberInputFormatter()],
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
          debugPrint('PHONE_AUTH_VERIFY_FAILED');
          _showMessage(_authService.mapFirebaseAuthError(e));
          if (mounted) setState(() => _isLoading = false);
        },
        codeSent: (verificationId, resendToken) {
          debugPrint('PHONE_AUTH_CODE_SENT');
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

  List<String> _termsForRole(String role) {
    if (role == 'outlet') {
      return const [
        'عمولة السحب لا تتجاوز 0.006 دينار لكل دينار واحد.',
        'الالتزام بالموقع والتحقق قبل تأكيد العملية.',
        'استلام وتسليم الأموال يكون داخل المنفذ حصراً.',
        'منفذك هو الذي يتحمل استقطاعات البنك أو الشركة.',
        'المنفذ مؤمن بشكل كامل بنظام مراقبة أمن.',
      ];
    }

    return const [
      'عمولة السحب لا تتجاوز 0.006 دينار لكل دينار واحد.',
      'الالتزام بالموقع والتحقق من اسم المنفذ قبل تأكيد العملية.',
      'استلام وتسليم الأموال يكون داخل المنفذ حصراً.',
    ];
  }

  Widget _buildTermsCard({
    required String roleLabel,
    required List<String> terms,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الشروط والأحكام الخاصة بـ $roleLabel',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 10),
          for (final term in terms) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsetsDirectional.only(top: 2),
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    term,
                    style: const TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
