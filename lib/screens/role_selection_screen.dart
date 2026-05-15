import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'auth_screen.dart';
import 'home_shell_screen.dart';

enum UserRole { client, outlet }

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  static const routeName = '/';

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final AuthService _authService = AuthService();
  String? _loadingTrialRole;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF4E3), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              const _WelcomeHero(),
              const SizedBox(height: 18),
              _RoleCard(
                title: 'أنا زبون',
                subtitle: 'أنشئ طلبك وشاهد عروض المنافذ بوضوح، ثم اختر العرض الأنسب لك قبل التأكيد.',
                icon: Icons.person_rounded,
                color: AppColors.primaryDark,
                trialLoading: _loadingTrialRole == 'client',
                onTap: () => _goToAuth(UserRole.client),
                onTrialTap: () => _loginAsTrial('client'),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                title: 'أنا صاحب منفذ',
                subtitle: 'استعرض الطلبات القريبة، قدّم عرضك، وتابع التنفيذ من مكان واحد.',
                icon: Icons.storefront_rounded,
                color: AppColors.success,
                trialLoading: _loadingTrialRole == 'outlet',
                onTap: () => _goToAuth(UserRole.outlet),
                onTrialTap: () => _loginAsTrial('outlet'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goToAuth(UserRole role) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AuthScreen(),
        settings: RouteSettings(arguments: role),
      ),
    );
  }

  Future<void> _loginAsTrial(String role) async {
    if (_loadingTrialRole != null) return;
    setState(() => _loadingTrialRole = role);
    try {
      final profile = await _authService.loginAsTestAccount(role: role);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeShellScreen(profile: profile)),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح حساب التجربة حالياً: $error')),
      );
    } finally {
      if (mounted) setState(() => _loadingTrialRole = null);
    }
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 22, offset: Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 238,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFEAF0F7)),
                boxShadow: const [
                  BoxShadow(color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/images/monfathak_logo.png',
                  height: 82,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'قارن عروض المنافذ واختر بثقة',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.textMuted, height: 1.4, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          const Text(
            'بدلاً من قبول أول عمولة، خلّي أكثر من منفذ يتنافس على طلبك وشاهد الفرق قبل الاختيار.',
            style: TextStyle(fontSize: 16, height: 1.55, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(icon: Icons.lock_rounded, label: 'آمن'),
              _HeroPill(icon: Icons.savings_rounded, label: 'وفر حتى 50%'),
              _HeroPill(icon: Icons.compare_arrows_rounded, label: 'قارن بين العروض'),
              _HeroPill(icon: Icons.payments_rounded, label: 'عمولات أقل'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.primaryDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.trialLoading,
    required this.onTap,
    required this.onTrialTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool trialLoading;
  final VoidCallback onTap;
  final VoidCallback onTrialTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 8)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: color, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: AppColors.textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: trialLoading ? null : onTrialTap,
                  icon: trialLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_circle_outline_rounded),
                  label: Text(trialLoading ? 'جاري فتح التجربة...' : 'تسجيل تجربة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
