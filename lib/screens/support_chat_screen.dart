import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({
    super.key,
    required this.threadPath,
    required this.currentUserId,
    required this.title,
  });

  final String threadPath;
  final String currentUserId;
  final String title;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  DocumentReference<Map<String, dynamic>>? get _bookingRef {
    final segments = widget.threadPath.split('/');
    if (segments.length < 3 || segments.first != 'booking_chats') return null;
    return FirebaseFirestore.instance.collection('bookings').doc(segments[1]);
  }

  @override
  void initState() {
    super.initState();
    _markThreadAsSeen();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesRef = FirebaseFirestore.instance.collection(widget.threadPath).orderBy('createdAt');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'خروج',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messagesRef.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(child: Text('ابدأ أول رسالة الآن.'));
                }
                _markThreadAsSeen();
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final mine = (data['senderId'] ?? '').toString() == widget.currentUserId;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xFFFFF3E0) : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text((data['text'] ?? '').toString()),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(hintText: 'اكتب رسالتك...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection(widget.threadPath).add({
        'senderId': widget.currentUserId,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _controller.clear();
      await _markThreadAsSeen();
      await _notifyIfNeeded(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markThreadAsSeen() async {
    final bookingRef = _bookingRef;
    if (bookingRef == null) return;
    await bookingRef.set({
      'chatLastSeen': {
        widget.currentUserId: FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  Future<void> _notifyIfNeeded(String text) async {
    final segments = widget.threadPath.split('/');
    if (segments.length < 3) return;

    if (segments.first == 'booking_chats') {
      final bookingId = segments[1];
      debugPrint('[ChatFlow] booking chat message stored; onChatMessageEvent will send remote push bookingId=$bookingId sender=${widget.currentUserId}');
      return;
    }

    if (segments.first == 'trip_support') {
      final bookingId = segments[1];
      final safeMessage = text.trim().isNotEmpty ? text.trim() : 'رسالة دعم بدون نص';
      await FirebaseFirestore.instance.collection('notifications').add({
        'toUserId': 'admin',
        'type': 'trip_support',
        'bookingId': bookingId,
        'title': 'رسالة دعم طلب',
        'body': safeMessage,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('admin_inbox').doc('trip_support_$bookingId').set({
        'threadPath': widget.threadPath,
        'title': 'دعم طلب',
        'lastMessage': safeMessage,
        'senderId': widget.currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[ChatFlow] trip support message bookingId=$bookingId sender=${widget.currentUserId}');
      return;
    }

    if (segments.first == 'support_general') {
      final safeMessage = text.trim().isNotEmpty ? text.trim() : 'رسالة دعم بدون نص';
      await FirebaseFirestore.instance.collection('notifications').add({
        'toUserId': 'admin',
        'type': 'general_support',
        'bookingId': '',
        'title': 'رسالة دعم عامة',
        'body': safeMessage,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final uid = segments[1];
      await FirebaseFirestore.instance.collection('admin_inbox').doc('support_$uid').set({
        'threadPath': widget.threadPath,
        'title': 'دعم عام - $uid',
        'lastMessage': safeMessage,
        'senderId': widget.currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[ChatFlow] general support message sender=${widget.currentUserId} target=$uid');
    }
  }
}
