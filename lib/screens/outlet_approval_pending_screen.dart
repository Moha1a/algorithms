import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'auth_screen.dart';
import 'role_selection_screen.dart';

class OutletApprovalPendingScreen extends StatelessWidget {
  const OutletApprovalPendingScreen({
    super.key,
    required this.phoneNumber,
  });

  final String phoneNumber;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حالة طلب المنفذ')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('phoneNumber', isEqualTo: phoneNumber)
                .where('role', isEqualTo: 'outlet')
                .limit(1)
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.docs.isNotEmpty == true
                  ? snapshot.data!.docs.first.data()
                  : <String, dynamic>{};
              final status = (data['approvalStatus'] ?? 'pending').toString();

              final isApproved = status == 'approved';
              final isRejected = status == 'rejected';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                      boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6))],
                    ),
                    child: Column(
                      children: [
                        Icon(
                          isApproved
                              ? Icons.verified_rounded
                              : isRejected
                                  ? Icons.cancel_rounded
                                  : Icons.hourglass_top_rounded,
                          size: 44,
                          color: isApproved
                              ? AppColors.success
                              : isRejected
                                  ? AppColors.danger
                                  : AppColors.info,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isApproved
                              ? 'تم قبول طلبك ✅'
                              : isRejected
                                  ? 'تم رفض طلبك'
                                  : 'تم تقديم طلبك بنجاح',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isApproved
                              ? 'يمكنك الآن تسجيل الدخول كمنفذ.'
                              : isRejected
                                  ? 'يرجى التواصل مع الإدارة للمراجعة.'
                                  : 'طلبك قيد المراجعة من الإدارة، سيتم إشعارك عند القبول.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textMuted, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isApproved)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const AuthScreen(),
                            settings: const RouteSettings(arguments: UserRole.outlet),
                          ),
                          (_) => false,
                        );
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('الانتقال لتسجيل الدخول'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                          (_) => false,
                        );
                      },
                      icon: const Icon(Icons.home_rounded),
                      label: const Text('العودة للرئيسية'),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}