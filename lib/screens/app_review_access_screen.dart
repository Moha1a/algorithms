import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'admin_dashboard_screen.dart';
import 'home_shell_screen.dart';

class AppReviewAccessScreen extends StatefulWidget {
  const AppReviewAccessScreen({
    super.key,
    required this.phoneNumber,
    required this.password,
  });

  final String phoneNumber;
  final String password;

  @override
  State<AppReviewAccessScreen> createState() => _AppReviewAccessScreenState();
}

class _AppReviewAccessScreenState extends State<AppReviewAccessScreen> {
  final AuthService _authService = AuthService();
  String? _loadingRole;

  Future<void> _openRole(String role) async {
    if (_loadingRole != null) return;
    setState(() => _loadingRole = role);
    try {
      final profile = await _authService.loginAsAppReviewAccount(
        role: role,
        phoneNumber: widget.phoneNumber,
        password: widget.password,
      );
      if (!mounted) return;

      final screen = role == 'admin'
          ? const AdminDashboardScreen()
          : HomeShellScreen(profile: profile);

      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح واجهة المراجعة: $error')),
      );
    } finally {
      if (mounted) setState(() => _loadingRole = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF4E0), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/monfathak_logo.png',
                      height: 74,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: AppColors.shadow, blurRadius: 20, offset: Offset(0, 10)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.verified_user_rounded, size: 44, color: AppColors.primary),
                    const SizedBox(height: 12),
                    const Text(
                      'وضع مراجعة Apple',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اختر الواجهة التي تريد مراجعتها. هذا المسار مخصص لحساب Apple Review فقط ويفتح الواجهات بدون OTP.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ReviewRoleButton(
                      title: 'الدخول كعميل',
                      subtitle: 'إنشاء الطلبات، متابعة الطلبات، الإشعارات والحساب.',
                      icon: Icons.person_rounded,
                      color: AppColors.primary,
                      loading: _loadingRole == 'client',
                      disabled: _loadingRole != null && _loadingRole != 'client',
                      onTap: () => _openRole('client'),
                    ),
                    const SizedBox(height: 12),
                    _ReviewRoleButton(
                      title: 'الدخول كمنفذ',
                      subtitle: 'طلبات العملاء والمنافذ، اقتراح العروض، القبول والمتابعة.',
                      icon: Icons.storefront_rounded,
                      color: AppColors.success,
                      loading: _loadingRole == 'outlet',
                      disabled: _loadingRole != null && _loadingRole != 'outlet',
                      onTap: () => _openRole('outlet'),
                    ),
                    const SizedBox(height: 12),
                    _ReviewRoleButton(
                      title: 'الدخول كأدمن',
                      subtitle: 'إدارة المستخدمين، الطلبات، الموافقات ورسائل الدعم.',
                      icon: Icons.admin_panel_settings_rounded,
                      color: AppColors.info,
                      loading: _loadingRole == 'admin',
                      disabled: _loadingRole != null && _loadingRole != 'admin',
                      onTap: () => _openRole('admin'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewRoleButton extends StatelessWidget {
  const _ReviewRoleButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled || loading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: disabled ? const Color(0xFFF4F6F8) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(15),
                        child: CircularProgressIndicator(strokeWidth: 2.3, color: color),
                      )
                    : Icon(icon, color: color, size: 29),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
