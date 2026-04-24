import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/push_sender_service.dart';
import 'support_chat_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
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
            tabs: [
              Tab(text: 'المنافذ'),
              Tab(text: 'العملاء'),
              Tab(text: 'الرحلات'),
              Tab(text: 'المحادثات'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _UsersAdminTab(role: 'outlet'),
            _UsersAdminTab(role: 'client'),
            _TripsAdminTab(),
            _ChatsAdminTab(),
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
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث برقم الرحلة أو النوع أو الحالة'),
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
                      title: Text('رحلة ${(d['bookingId'] ?? id).toString()}'),
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
                          PopupMenuItem(value: 'cancel', child: Text('إلغاء الرحلة')),
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