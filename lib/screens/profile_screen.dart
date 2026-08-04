import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'outlet_hours_setup_screen.dart';
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
  late final TextEditingController _outletNameController;
  late final TextEditingController _regionController;
  late final TextEditingController _governorateController;
  final AuthService _authService = AuthService();
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: (widget.profile['fullName'] ?? '').toString(),
    );
    _outletNameController = TextEditingController(
      text: (widget.profile['outletName'] ?? '').toString(),
    );
    _regionController = TextEditingController(
      text: (widget.profile['region'] ?? widget.profile['outletRegion'] ?? '')
          .toString(),
    );
    _governorateController = TextEditingController(
      text: (widget.profile['governorate'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _outletNameController.dispose();
    _regionController.dispose();
    _governorateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = (widget.profile['uid'] ?? '').toString();
    final phoneNumber = (widget.profile['phoneNumber'] ?? '').toString();
    final role = (widget.profile['role'] ?? '').toString();
    final governorate = (widget.profile['governorate'] ?? '').toString();
    final outletName = (widget.profile['outletName'] ?? '').toString();
    final outletRegion =
        (widget.profile['region'] ?? widget.profile['outletRegion'] ?? '')
            .toString();

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
                  if (role == 'outlet' && outletRegion.isNotEmpty)
                    Text('المنطقة: $outletRegion'),
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
                      return Text(
                          'معدل التقييم: ⭐ ${avg.toStringAsFixed(1)} ($count تقييم)');
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : () => _openEditProfileSheet(uid, role),
            icon: const Icon(Icons.edit_rounded),
            label: Text(_saving ? 'جاري الحفظ...' : 'تعديل الملف الشخصي'),
          ),
          if (role == 'outlet') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OutletHoursSetupScreen(
                      profile: Map<String, dynamic>.from(widget.profile),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.schedule_rounded),
              label: const Text('تعديل أوقات العمل'),
            ),
          ],
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
            onPressed: _deleting
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('تسجيل الخروج'),
                        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('إلغاء'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('نعم'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    await _authService.logout();
                    if (!mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const RoleSelectionScreen()),
                      (route) => false,
                    );
                  },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('تسجيل الخروج'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
            onPressed: _deleting ? null : _confirmAndDeleteAccount,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever_rounded),
            label:
                Text(_deleting ? 'جاري حذف الحساب...' : 'حذف الحساب نهائياً'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditProfileSheet(String uid, String role) async {
    final formKey = GlobalKey<FormState>();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'تعديل الملف الشخصي',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'يرجى إدخال الاسم';
                    }
                    return null;
                  },
                ),
                if (role == 'outlet') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _outletNameController,
                    decoration: const InputDecoration(labelText: 'اسم المنفذ'),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'يرجى إدخال اسم المنفذ';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _governorateController,
                    decoration: const InputDecoration(labelText: 'المحافظة'),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'يرجى إدخال المحافظة';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _regionController,
                    decoration: const InputDecoration(labelText: 'المنطقة'),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'يرجى إدخال المنطقة';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('حفظ التعديلات'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final updates = <String, dynamic>{
        'fullName': _nameController.text.trim(),
        'nameUpdatedAt': FieldValue.serverTimestamp(),
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      };
      widget.profile['fullName'] = _nameController.text.trim();
      if (role == 'outlet') {
        final outletName = _outletNameController.text.trim();
        final governorate = _governorateController.text.trim();
        final region = _regionController.text.trim();
        updates['outletName'] = outletName;
        updates['governorate'] = governorate;
        updates['region'] = region;
        updates['outletRegion'] = region;
        widget.profile['outletName'] = outletName;
        widget.profile['governorate'] = governorate;
        widget.profile['region'] = region;
        widget.profile['outletRegion'] = region;
      }

      await userRef.update(updates);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الملف الشخصي')),
      );
      setState(() {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAndDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الحساب نهائياً'),
        content: const Text(
          'سيتم حذف حسابك من التطبيق وإزالة بيانات الدخول والتنبيهات المرتبطة به. لا يمكن التراجع عن هذه العملية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف الحساب'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (mounted) setState(() => _deleting = true);
    try {
      await _authService.deleteCurrentAccount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الحساب بنجاح.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authService.mapFirebaseAuthError(error))),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }
}
