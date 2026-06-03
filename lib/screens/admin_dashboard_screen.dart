import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_version_service.dart';
import '../services/input_digit_utils.dart';
import '../services/push_sender_service.dart';
import 'support_chat_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('منفذك - لوحة الإدارة'),
          actions: [
            IconButton(
              tooltip: 'إرسال إشعار جماعي',
              onPressed: () => _openBroadcastDialog(context),
              icon: const Icon(Icons.campaign_rounded),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'المنافذ'),
              Tab(text: 'العملاء'),
              Tab(text: 'الطلبات'),
              Tab(text: 'المحادثات'),
              Tab(text: 'نسخ التطبيق'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _UsersAdminTab(role: 'outlet'),
            _UsersAdminTab(role: 'client'),
            _TripsAdminTab(),
            _ChatsAdminTab(),
            _VersionPolicyAdminTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _openBroadcastDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    bool asInAppMessage = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('إرسال إشعار/رسالة جماعية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'العنوان')),
              TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'المحتوى')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('حفظ كرسالة جماعية داخل الإشعارات'),
                value: asInAppMessage,
                onChanged: (v) => setModalState(() => asInAppMessage = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) return;

    final users = await FirebaseFirestore.instance.collection('users').get();
    for (final doc in users.docs) {
      final uid = (doc.data()['uid'] ?? doc.id).toString();
      if (uid.isEmpty) continue;
      debugPrint('[AdminNotify] broadcast push to uid=$uid');
      await PushSenderService.instance.sendPush(
        recipientUid: uid,
        title: title,
        body: body,
        type: 'admin_broadcast',
        actorId: 'admin',
      );
      if (asInAppMessage) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUserId': uid,
          'type': 'admin_broadcast',
          'title': title,
          'body': body,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }
}

class _UsersAdminTab extends StatefulWidget {
  const _UsersAdminTab({required this.role});
  final String role;

  @override
  State<_UsersAdminTab> createState() => _UsersAdminTabState();
}

class _UsersAdminTabState extends State<_UsersAdminTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('users').where('role', isEqualTo: widget.role).snapshots();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو البريد'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs.where((d) {
                if (_q.isEmpty) return true;
                final u = d.data();
                final n = (u['fullName'] ?? '').toString().toLowerCase();
                final e = (u['email'] ?? '').toString().toLowerCase();
                return n.contains(_q) || e.contains(_q);
              }).toList();
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final u = docs[i].data();
                  final uid = (u['uid'] ?? docs[i].id).toString();
                  final approvalStatus = (u['approvalStatus'] ?? '').toString();
                  final isOutletRole = widget.role == 'outlet';
                  final statusLabel = approvalStatus == 'approved'
                      ? 'مقبول'
                      : approvalStatus == 'rejected'
                          ? 'مرفوض'
                          : approvalStatus == 'pending'
                              ? 'بانتظار الموافقة'
                              : '';
                  return Card(
                    child: ListTile(
                      title: Text((u['fullName'] ?? uid).toString()),
                      subtitle: Text(
                        '${(u['email'] ?? '').toString()}\n'
                        'التقييم: ${(u['ratingAverage'] ?? 0).toString()}'
                        '${statusLabel.isEmpty ? '' : '\nالحالة: $statusLabel'}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'chat') {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SupportChatScreen(
                                  threadPath: 'support_general/$uid/messages',
                                  currentUserId: 'admin',
                                  title: 'محادثة ${widget.role == 'outlet' ? 'المنفذ' : 'العميل'}',
                                ),
                              ),
                            );
                          } else if (v == 'notify') {
                            final titleCtrl = TextEditingController(text: 'رسالة من الإدارة');
                            final bodyCtrl = TextEditingController(text: 'يرجى مراجعة حسابك من خلال التطبيق.');
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('إرسال إشعار للمستخدم'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'العنوان')),
                                    TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'المحتوى')),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              debugPrint('[AdminNotify] single push to uid=$uid');
                              await PushSenderService.instance.sendPush(
                                recipientUid: uid,
                                title: titleCtrl.text.trim(),
                                body: bodyCtrl.text.trim(),
                                type: 'admin_single',
                                actorId: 'admin',
                              );
                              await FirebaseFirestore.instance.collection('notifications').add({
                                'toUserId': uid,
                                'type': 'admin_single',
                                'title': titleCtrl.text.trim(),
                                'body': bodyCtrl.text.trim(),
                                'isRead': false,
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                            }
                          } else if (v == 'remove') {
                            await FirebaseFirestore.instance.collection('users').doc(uid).set({
                              'isBlocked': true,
                            }, SetOptions(merge: true));
                          } else if (v == 'approve_outlet') {
                            await FirebaseFirestore.instance.collection('users').doc(uid).set({
                              'approvalStatus': 'approved',
                              'approvalDecisionAt': FieldValue.serverTimestamp(),
                              'approvedBy': 'admin',
                            }, SetOptions(merge: true));
                            await PushSenderService.instance.sendPush(
                              recipientUid: uid,
                              title: 'تم قبول طلبك ✅',
                              body: 'تمت الموافقة على حساب المنفذ الخاص بك ويمكنك تسجيل الدخول الآن.',
                              type: 'outlet_approval_accepted',
                              actorId: 'admin',
                            );
                            await FirebaseFirestore.instance.collection('notifications').add({
                              'toUserId': uid,
                              'type': 'outlet_approval_accepted',
                              'title': 'تم قبول طلبك ✅',
                              'body': 'تمت الموافقة على حساب المنفذ الخاص بك ويمكنك تسجيل الدخول الآن.',
                              'isRead': false,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          } else if (v == 'reject_outlet') {
                            await FirebaseFirestore.instance.collection('users').doc(uid).set({
                              'approvalStatus': 'rejected',
                              'approvalDecisionAt': FieldValue.serverTimestamp(),
                              'approvedBy': 'admin',
                            }, SetOptions(merge: true));
                            await PushSenderService.instance.sendPush(
                              recipientUid: uid,
                              title: 'تم رفض طلب المنفذ',
                              body: 'يرجى التواصل مع الإدارة لمعرفة التفاصيل.',
                              type: 'outlet_approval_rejected',
                              actorId: 'admin',
                            );
                            await FirebaseFirestore.instance.collection('notifications').add({
                              'toUserId': uid,
                              'type': 'outlet_approval_rejected',
                              'title': 'تم رفض طلب المنفذ',
                              'body': 'يرجى التواصل مع الإدارة لمعرفة التفاصيل.',
                              'isRead': false,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'chat', child: Text('مراسلة')),
                          const PopupMenuItem(value: 'notify', child: Text('إرسال إشعار')),
                          if (isOutletRole && approvalStatus == 'pending')
                            const PopupMenuItem(value: 'approve_outlet', child: Text('قبول طلب المنفذ')),
                          if (isOutletRole && approvalStatus == 'pending')
                            const PopupMenuItem(value: 'reject_outlet', child: Text('رفض طلب المنفذ')),
                          const PopupMenuItem(value: 'remove', child: Text('حظر المستخدم')),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TripsAdminTab extends StatefulWidget {
  const _TripsAdminTab();

  @override
  State<_TripsAdminTab> createState() => _TripsAdminTabState();
}

class _TripsAdminTabState extends State<_TripsAdminTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('bookings').snapshots();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث برقم الطلب أو النوع أو الحالة'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs.where((d) {
                if (_q.isEmpty) return true;
                final data = d.data();
                return (data['bookingId'] ?? d.id).toString().toLowerCase().contains(_q) ||
                    (data['type'] ?? '').toString().toLowerCase().contains(_q) ||
                    (data['status'] ?? '').toString().toLowerCase().contains(_q);
              }).toList();
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final id = docs[i].id;
                  return Card(
                    child: ListTile(
                      title: Text('طلب ${(d['bookingId'] ?? id).toString()}'),
                      subtitle: Text('الحالة: ${(d['status'] ?? '').toString()} • النوع: ${(d['type'] ?? '').toString()}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'cancel') {
                            await FirebaseFirestore.instance.collection('bookings').doc(id).update({'status': 'cancelled'});
                          }
                          if (v == 'chat_client') {
                            final cid = (d['clientId'] ?? '').toString();
                            if (cid.isEmpty) return;
                            if (!context.mounted) return;
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SupportChatScreen(
                                threadPath: 'support_general/$cid/messages',
                                currentUserId: 'admin',
                                title: 'مراسلة العميل',
                              ),
                            ));
                          }
                          if (v == 'chat_outlet') {
                            final oid = (d['outletId'] ?? '').toString();
                            if (oid.isEmpty) return;
                            if (!context.mounted) return;
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SupportChatScreen(
                                threadPath: 'support_general/$oid/messages',
                                currentUserId: 'admin',
                                title: 'مراسلة المنفذ',
                              ),
                            ));
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'cancel', child: Text('إلغاء الطلب')),
                          PopupMenuItem(value: 'chat_client', child: Text('مراسلة العميل')),
                          PopupMenuItem(value: 'chat_outlet', child: Text('مراسلة المنفذ')),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChatsAdminTab extends StatefulWidget {
  const _ChatsAdminTab();

  @override
  State<_ChatsAdminTab> createState() => _ChatsAdminTabState();
}

class _ChatsAdminTabState extends State<_ChatsAdminTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('admin_inbox').orderBy('updatedAt', descending: true).snapshots();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث في المحادثات'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final now = DateTime.now();
              final docs = (snapshot.data?.docs ?? const []).where((d) {
                if (_q.isEmpty) return true;
                return (d.data()['title'] ?? '').toString().toLowerCase().contains(_q) ||
                    (d.data()['lastMessage'] ?? '').toString().toLowerCase().contains(_q);
              }).toList();

              final active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final previous = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              for (final d in docs) {
                final ts = d.data()['updatedAt'];
                final at = ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                final diff = now.difference(at).inMinutes;
                if (diff <= 10) {
                  active.add(d);
                } else {
                  previous.add(d);
                }
              }

              if (docs.isEmpty) {
                return const Center(child: Text('لا توجد محادثات.'));
              }

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Text('المحادثات النشطة', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...active.map((d) => _chatTile(context, d)),
                  const SizedBox(height: 12),
                  const Text('المحادثات السابقة', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...previous.map((d) => _chatTile(context, d)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chatTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final threadPath = (d['threadPath'] ?? '').toString();
    final title = (d['title'] ?? 'محادثة').toString();
    final lastMessage = (d['lastMessage'] ?? '').toString();
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(lastMessage.isEmpty ? 'بدون رسائل بعد' : lastMessage),
        onTap: threadPath.isEmpty
            ? null
            : () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SupportChatScreen(
                    threadPath: threadPath,
                    currentUserId: 'admin',
                    title: title,
                  ),
                ));
              },
      ),
    );
  }
}

class _VersionPolicyAdminTab extends StatefulWidget {
  const _VersionPolicyAdminTab();

  @override
  State<_VersionPolicyAdminTab> createState() => _VersionPolicyAdminTabState();
}

class _VersionPolicyAdminTabState extends State<_VersionPolicyAdminTab> {
  final _iosMinVersionCtrl = TextEditingController();
  final _iosMinBuildCtrl = TextEditingController();
  final _androidMinVersionCtrl = TextEditingController();
  final _androidMinBuildCtrl = TextEditingController();
  final _iosStoreUrlCtrl = TextEditingController();
  final _androidStoreUrlCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  String _currentVersion = '';
  int _currentBuild = 0;

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  @override
  void dispose() {
    _iosMinVersionCtrl.dispose();
    _iosMinBuildCtrl.dispose();
    _androidMinVersionCtrl.dispose();
    _androidMinBuildCtrl.dispose();
    _iosStoreUrlCtrl.dispose();
    _androidStoreUrlCtrl.dispose();
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPolicy() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version.trim();
      _currentBuild = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
      final doc = await FirebaseFirestore.instance.doc(AppVersionService.policyPath).get();
      final data = doc.data() ?? <String, dynamic>{};
      _enabled = data['enabled'] != false;
      _iosMinVersionCtrl.text = (data['iosMinVersion'] ?? '').toString();
      _iosMinBuildCtrl.text = _intText(data['iosMinBuild']);
      _androidMinVersionCtrl.text = (data['androidMinVersion'] ?? '').toString();
      _androidMinBuildCtrl.text = _intText(data['androidMinBuild']);
      _iosStoreUrlCtrl.text = (data['iosStoreUrl'] ?? '').toString();
      _androidStoreUrlCtrl.text = (data['androidStoreUrl'] ?? '').toString();
      _titleCtrl.text = (data['title'] ?? 'تحديث ضروري للتطبيق').toString();
      _messageCtrl.text = (data['message'] ?? 'حتى تستمر باستخدام منفذك بأمان، يرجى تحديث التطبيق إلى آخر نسخة متوفرة.').toString();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل سياسة النسخة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePolicy() async {
    final iosMinVersion = _normalizeVersionText(_iosMinVersionCtrl.text);
    final androidMinVersion = _normalizeVersionText(_androidMinVersionCtrl.text);
    final iosMinBuild = int.tryParse(InputDigitUtils.digitsOnly(_iosMinBuildCtrl.text)) ?? 0;
    final androidMinBuild = int.tryParse(InputDigitUtils.digitsOnly(_androidMinBuildCtrl.text)) ?? 0;

    if (_enabled && iosMinVersion.isEmpty && iosMinBuild <= 0 && androidMinVersion.isEmpty && androidMinBuild <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد أقل نسخة أو أقل رقم بناء قبل تفعيل الحظر.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.doc(AppVersionService.policyPath).set({
        'enabled': _enabled,
        'iosMinVersion': iosMinVersion,
        'iosMinBuild': iosMinBuild,
        'androidMinVersion': androidMinVersion,
        'androidMinBuild': androidMinBuild,
        'iosStoreUrl': _iosStoreUrlCtrl.text.trim(),
        'androidStoreUrl': _androidStoreUrlCtrl.text.trim(),
        'title': _titleCtrl.text.trim().isEmpty ? 'تحديث ضروري للتطبيق' : _titleCtrl.text.trim(),
        'message': _messageCtrl.text.trim().isEmpty
            ? 'حتى تستمر باستخدام منفذك بأمان، يرجى تحديث التطبيق إلى آخر نسخة متوفرة.'
            : _messageCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? 'admin',
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ سياسة النسخة بنجاح.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ سياسة النسخة: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _fillCurrentVersionAsMinimum() {
    _iosMinVersionCtrl.text = _currentVersion.isEmpty ? '1.0.2' : _currentVersion;
    _iosMinBuildCtrl.text = _currentBuild <= 0 ? '22' : _currentBuild.toString();
    _androidMinVersionCtrl.text = _currentVersion.isEmpty ? '1.0.2' : _currentVersion;
    _androidMinBuildCtrl.text = _currentBuild <= 0 ? '22' : _currentBuild.toString();
    setState(() {});
  }

  String _normalizeVersionText(String value) {
    return InputDigitUtils.normalizeArabicDigits(value)
        .trim()
        .replaceAll('،', '.')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'\s+'), '');
  }

  String _intText(Object? value) {
    if (value == null) return '';
    final number = value is num ? value.toInt() : int.tryParse(value.toString()) ?? 0;
    return number <= 0 ? '' : number.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل منع النسخ القديمة', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: const Text('عند التفعيل، أي نسخة أقل من الحد الأدنى ستظهر لها شاشة تحديث إجبارية.'),
                  value: _enabled,
                  onChanged: _saving ? null : (value) => setState(() => _enabled = value),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : _fillCurrentVersionAsMinimum,
                  icon: const Icon(Icons.done_all_rounded),
                  label: Text(
                    _currentVersion.isEmpty
                        ? 'اجعل النسخة الحالية هي الحد الأدنى الآمن'
                        : 'اجعل $_currentVersion+$_currentBuild هي الحد الأدنى الآمن',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PlatformVersionCard(
          title: 'iPhone / App Store',
          icon: Icons.phone_iphone_rounded,
          minVersionController: _iosMinVersionCtrl,
          minBuildController: _iosMinBuildCtrl,
          storeUrlController: _iosStoreUrlCtrl,
          storeHint: 'رابط صفحة التطبيق في App Store',
        ),
        const SizedBox(height: 12),
        _PlatformVersionCard(
          title: 'Android / Google Play',
          icon: Icons.android_rounded,
          minVersionController: _androidMinVersionCtrl,
          minBuildController: _androidMinBuildCtrl,
          storeUrlController: _androidStoreUrlCtrl,
          storeHint: 'https://play.google.com/store/apps/details?id=com.company.manfathak',
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('نص شاشة التحديث', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _messageCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'الرسالة'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFFFFF8E8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('ملاحظة مهمة', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text('هذا التحكم يعمل فقط على النسخ التي تحتوي ميزة فحص النسخة. إذا كان تطبيق الآيفون المثبت أقدم من هذه الميزة فلن يتأثر إلا بعد نشر تحديث يحتويها.'),
                SizedBox(height: 12),
                Text('طريقة التجربة بدون نشر تحديث', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text('1. ارفع الحد الأدنى مؤقتاً إلى نسخة أعلى من نسختك الحالية، مثل 9.9.9.'),
                Text('2. أغلق التطبيق وافتحه من جديد، ستظهر شاشة التحديث الإجبارية.'),
                Text('3. ارجع من Firebase Console أو من جهاز أدمن آخر وخفض الحد إلى نسخة التطبيق الحالية، ثم اضغط إعادة الفحص.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving ? null : _savePolicy,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'جاري الحفظ...' : 'حفظ سياسة النسخة'),
          ),
        ),
      ],
    );
  }
}

class _PlatformVersionCard extends StatelessWidget {
  const _PlatformVersionCard({
    required this.title,
    required this.icon,
    required this.minVersionController,
    required this.minBuildController,
    required this.storeUrlController,
    required this.storeHint,
  });

  final String title;
  final IconData icon;
  final TextEditingController minVersionController;
  final TextEditingController minBuildController;
  final TextEditingController storeUrlController;
  final String storeHint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minVersionController,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'أقل نسخة',
                      hintText: '1.0.1',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: minBuildController,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [DigitOnlyInputFormatter()],
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'أقل build',
                      hintText: '21',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: storeUrlController,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رابط التحديث',
                hintText: storeHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
