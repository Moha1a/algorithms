import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_version_service.dart';
import '../theme/app_colors.dart';

class AppVersionGate extends StatefulWidget {
  const AppVersionGate({
    super.key,
    required this.firebaseInitFuture,
    required this.child,
  });

  final Future<void> firebaseInitFuture;
  final Widget child;

  @override
  State<AppVersionGate> createState() => _AppVersionGateState();
}

class _AppVersionGateState extends State<AppVersionGate>
    with WidgetsBindingObserver {
  late Future<AppVersionStatus> _statusFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusFuture = _checkVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<AppVersionStatus> _checkVersion() async {
    await widget.firebaseInitFuture;
    return AppVersionService.instance.checkVersion();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _statusFuture = _checkVersion();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersionStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final status = snapshot.data;
        if (status != null && status.updateRequired) {
          return ForceUpdateScreen(status: status, onRecheck: _refresh);
        }
        return widget.child;
      },
    );
  }
}

class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({
    super.key,
    required this.status,
    required this.onRecheck,
  });

  final AppVersionStatus status;
  final VoidCallback onRecheck;

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _openingStore = false;

  Future<void> _openStore() async {
    if (_openingStore) return;
    setState(() => _openingStore = true);
    try {
      final uri = widget.status.effectiveStoreUri;
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تعذر فتح صفحة التحديث. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingStore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF7EA), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 24,
                        offset: Offset(0, 14)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(Icons.system_update_alt_rounded,
                            color: AppColors.primaryDark, size: 42),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      status.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.25,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      status.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _VersionInfoTile(
                      label: 'نسختك الحالية',
                      value: status.currentLabel,
                      icon: Icons.phone_iphone_rounded,
                    ),
                    const SizedBox(height: 8),
                    _VersionInfoTile(
                      label: 'النسخة المطلوبة',
                      value: status.requiredLabel,
                      icon: Icons.verified_rounded,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _openingStore ? null : _openStore,
                        icon: _openingStore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.open_in_new_rounded),
                        label: const Text('تحديث التطبيق'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: widget.onRecheck,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة الفحص'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionInfoTile extends StatelessWidget {
  const _VersionInfoTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryDark, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
