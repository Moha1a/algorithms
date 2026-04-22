import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'role_selection_screen.dart';
import 'support_chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  final AuthService _authService = AuthService();
  bool _saving = false;
  static const Duration _nameChangeCooldown = Duration(days: 14);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: (widget.profile['fullName'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = (widget.profile['uid'] ?? '').toString();
    final phoneNumber = (widget.profile['phoneNumber'] ?? '').toString();
    final role = (widget.profile['role'] ?? '').toString();
    final governorate = (widget.profile['governorate'] ?? '').toString();
    final outletName = (widget.profile['outletName'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: const Text('منفذك - الملف الشخصي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (phoneNumber.isNotEmpty) Text('الهاتف: $phoneNumber'),
                  Text('الدور: ${role == 'outlet' ? 'منفذ' : 'عميل'}'),
                  Text('المحافظة: $governorate'),
                  if (outletName.isNotEmpty) Text('اسم المنفذ: $outletName'),
                  const SizedBox(height: 6),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('ratings')
                        .where('toUserId', isEqualTo: uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? const [];
                      if (docs.isEmpty) {
                        return const Text('معدل التقييم: لا يوجد تقييم بعد');
                      }
                      double total = 0;
                      int count = 0;
                      for (final doc in docs) {
                        final stars = doc.data()['stars'];
                        if (stars is num) {
                          total += stars.toDouble();
                          count += 1;
                        }
                      }
                      if (count == 0) {
                        return const Text('معدل التقييم: لا يوجد تقييم بعد');
                      }
                      final avg = total / count;
                      return Text('معدل التقييم: ⭐ ${avg.toStringAsFixed(1)} ($count تقييم)');
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'الاسم الكامل'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    final next = _nameController.text.trim();
                    if (next.isEmpty) return;
                    setState(() => _saving = true);
                    try {
                      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
                      final userSnap = await userRef.get();
                      final data = userSnap.data() ?? <String, dynamic>{};
                      final changedAtRaw = data['nameUpdatedAt'];

                      DateTime? changedAt;
                      if (changedAtRaw is Timestamp) {
                        changedAt = changedAtRaw.toDate();
                      }

                      if (changedAt != null) {
                        final nextAllowed = changedAt.add(_nameChangeCooldown);
                        final now = DateTime.now();
                        if (now.isBefore(nextAllowed)) {
                          final remaining = nextAllowed.difference(now).inDays + 1;
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('يمكنك تغيير الاسم مرة واحدة كل 14 يومًا. المتبقي تقريبًا $remaining يوم.')),
                          );
                          return;
                        }
                      }

                      await userRef.update({
                        'fullName': next,
                        'nameUpdatedAt': FieldValue.serverTimestamp(),
                      });
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الاسم')));
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('حفظ الاسم'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SupportChatScreen(
                    threadPath: 'support_general/$uid/messages',
                    currentUserId: uid,
                    title: 'الدعم العام',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.support_agent_rounded),
            label: const Text('مراسلة الدعم العام'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('تسجيل الخروج'),
                  content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('نعم'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              await _authService.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }
}