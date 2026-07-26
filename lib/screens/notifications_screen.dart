import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'home_shell_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final uid = (profile['uid'] ?? '').toString();
    final stream = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('منفذك - الإشعارات')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('تعذر تحميل الإشعارات: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(child: Text('لا توجد إشعارات حالياً.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (_, i) {
              final data = docs[i].data();
              final isRead = data['isRead'] == true;
              return ListTile(
                onTap: () {
                  docs[i].reference.set({'isRead': true}, SetOptions(merge: true));
                  final role = (profile['role'] ?? '').toString();
                  HomeShellScreen.requestTab(role == 'outlet' ? 3 : 1);
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                tileColor: isRead ? Colors.white : const Color(0xFFFFF7ED),
                title: Text((data['title'] ?? 'إشعار').toString()),
                subtitle: Text((data['body'] ?? '').toString()),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: docs.length,
          );
        },
      ),
    );
  }
}