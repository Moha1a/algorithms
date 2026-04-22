import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'home_shell_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.authService,
    required this.phoneNumber,
    required this.initialVerificationId,
    required this.initialResendToken,
    this.role = 'client',
    this.isRegistration = false,
    this.fullName = '',
    this.governorate = 'البصرة',
    this.password = '',
    this.outletName,
    this.isPasswordResetFlow = false,
  });

  final AuthService authService;
  final String phoneNumber;
  final String initialVerificationId;
  final int? initialResendToken;
  final String role;
  final bool isRegistration;
  final String fullName;
  final String governorate;
  final String password;
  final String? outletName;
  final bool isPasswordResetFlow;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  String _verificationId = '';
  int? _resendToken;
  bool _isLoading = false;
  bool _canResend = false;
  int _secondsLeft = 60;
  Timer? _timer;
  PhoneAuthCredential? _verifiedCredential;
  String? _verifiedUid;
  DateTime? _verifiedAt;
  static const Duration _passwordResetWindow = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _verificationId = widget.initialVerificationId;
    _resendToken = widget.initialResendToken;
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _canResend = false;
      _secondsLeft = 60;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _secondsLeft = 0;
          _canResend = true;
        });
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _verifyCode() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      _showMessage('أدخل رمز OTP صحيح');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );

      if (widget.isPasswordResetFlow) {
        final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
        if (!mounted) return;
        setState(() {
          _verifiedCredential = credential;
          _verifiedUid = userCred.user?.uid;
          _verifiedAt = DateTime.now();
        });
        _showMessage('تم التحقق من الرمز. أدخل كلمة المرور الجديدة');
        return;
      }

      final profile = await widget.authService.loginOrRegisterWithCredential(
        credential: credential,
        role: widget.role,
        phoneNumber: widget.phoneNumber,
        password: widget.password,
        isRegistration: widget.isRegistration,
        fullName: widget.fullName,
        governorate: widget.governorate,
        outletName: widget.outletName,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeShellScreen(profile: profile)),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      _showMessage(widget.authService.mapFirebaseAuthError(e));
    } catch (e) {
      _showMessage('حدث خطأ غير متوقع. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    final verifiedUid = _verifiedUid;
    if (_verifiedCredential == null || verifiedUid == null || verifiedUid.trim().isEmpty) return;
    final verifiedAt = _verifiedAt;
    if (verifiedAt == null || DateTime.now().difference(verifiedAt) > _passwordResetWindow) {
      _showMessage('انتهت مهلة التحقق. يرجى إعادة إرسال رمز التحقق.');
      setState(() {
        _verifiedCredential = null;
        _verifiedUid = null;
        _verifiedAt = null;
      });
      return;
    }
    final pass = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();
    if (pass.length < 6) {
      _showMessage('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }
    if (pass != confirm) {
      _showMessage('تأكيد كلمة المرور غير مطابق');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.authService.resetPasswordForVerifiedUid(uid: verifiedUid, newPassword: pass);
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _showMessage('تم تحديث كلمة المرور بنجاح');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      _showMessage(widget.authService.mapFirebaseAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      await widget.authService.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        forceResendingToken: _resendToken,
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          _showMessage(widget.authService.mapFirebaseAuthError(e));
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          _startCountdown();
          _showMessage('تم إعادة إرسال رمز التحقق');
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!mounted) return;
          setState(() => _verificationId = verificationId);
        },
      );
    } catch (_) {
      _showMessage('تعذر إعادة الإرسال. حاول لاحقًا.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resetModeReady = widget.isPasswordResetFlow && _verifiedCredential != null;

    return Scaffold(
      appBar: AppBar(title: Text(resetModeReady ? 'كلمة مرور جديدة' : 'تأكيد رمز OTP')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (!resetModeReady) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'تم إرسال الرمز إلى: ${widget.phoneNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'أدخل رمز التحقق المرسل إلى هاتفك للمتابعة.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'رمز التحقق (OTP)',
                  hintText: '123456',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _isLoading ? null : _verifyCode,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('تأكيد الرمز'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _canResend
                    ? 'يمكنك الآن إعادة إرسال الرمز.'
                    : 'إعادة الإرسال خلال $_secondsLeft ثانية',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: (_canResend && !_isLoading) ? _resendCode : null,
                child: const Text('إعادة إرسال الرمز'),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'الرجاء إدخال كلمة مرور جديدة قوية ثم تأكيدها.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور الجديدة'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submitNewPassword,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('حفظ كلمة المرور'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}