import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/money_utils.dart';
import 'home_shell_screen.dart';
import 'support_chat_screen.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  double _commissionFromBooking(Map<String, dynamic> b) {
    final amount = (b['amount'] is num) ? (b['amount'] as num).toDouble() : double.tryParse((b['amount'] ?? '0').toString()) ?? 0;
    if (b['commission'] is num) return (b['commission'] as num).toDouble();
    final entered = double.tryParse((b['price'] ?? '').toString());
    return entered ?? 0;
  }

  String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double _safeDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  void _showControlledMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBookingFromMapTap({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String role,
    required String uid,
  }) async {
    debugPrint('MAP_BOOKING_TAP');
    try {
      final raw = doc.data();
      final bookingDocId = _safeString(doc.id, fallback: '');
      final bookingId = _safeString(raw['bookingId'], fallback: bookingDocId);
      final clientId = _safeString(raw['clientId']);
      final createdById = _safeString(raw['createdById']);
      final outletId = _safeString(raw['outletId']);
      final status = _safeString(raw['status'], fallback: 'pending');
      final amount = _safeDouble(raw['amount']);
      final price = _safeDouble(raw['price']);
      final priceProposalsRaw = raw['priceProposals'];
      final proposalsCount = (priceProposalsRaw is List) ? priceProposalsRaw.length : 0;

      debugPrint('MAP_BOOKING_TAP_DATA bookingId=$bookingId docId=$bookingDocId clientId=$clientId createdById=$createdById outletId=$outletId status=$status amount=$amount price=$price proposals=$proposalsCount');

      if (bookingDocId.isEmpty) {
        _showControlledMessage(context, 'تعذر فتح الطلب، قد يكون محذوفاً أو غير متاح');
        return;
      }

      debugPrint('MAP_BOOKING_OPEN_START');
      final fresh = await FirebaseFirestore.instance.collection('bookings').doc(bookingDocId).get().timeout(const Duration(seconds: 8));
      if (!fresh.exists || fresh.data() == null) {
        _showControlledMessage(context, 'تعذر فتح الطلب، قد يكون محذوفاً أو غير متاح');
        return;
      }

      final freshData = fresh.data()!;
      final lat = _safeDouble(freshData['clientLat'], fallback: double.nan);
      final lng = _safeDouble(freshData['clientLng'], fallback: double.nan);
      final hasValidCoordinates = lat.isFinite && lng.isFinite;
      if (!hasValidCoordinates) {
        _showControlledMessage(context, 'تعذر تحديد الإحداثيات بدقة، سيتم فتح تفاصيل الطلب بشكل آمن.');
      }

      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookingMapDetailsScreen(
            bookingDocId: bookingDocId,
            role: role,
            currentUserId: uid,
          ),
        ),
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('MAP_BOOKING_OPEN_FAILED_CONTROLLED: $error');
      debugPrint('$stackTrace');
      _showControlledMessage(context, 'تعذر فتح الطلب، قد يكون محذوفاً أو غير متاح');
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('MAP_BOOKING_OPEN_FAILED_CONTROLLED: $error');
      debugPrint('$stackTrace');
      _showControlledMessage(context, 'تعذر فتح الطلب، قد يكون محذوفاً أو غير متاح');
    } catch (error, stackTrace) {
      debugPrint('MAP_BOOKING_OPEN_FAILED_CONTROLLED: $error');
      debugPrint('$stackTrace');
      _showControlledMessage(context, 'تعذر فتح الطلب، قد يكون محذوفاً أو غير متاح');
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MAP_TAB_OPEN');
    final uid = _safeString(profile['uid']);
    final role = _safeString(profile['role']);
    final field = role == 'outlet' ? 'outletId' : 'clientId';
    final stream = FirebaseFirestore.instance
        .collection('bookings')
        .where(field, isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'in_progress', 'awaiting_provider_code'])
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('منفذك - الخريطة')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          debugPrint('MAP_BOOKINGS_LOAD_START');
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('MAP_BOOKING_OPEN_FAILED_CONTROLLED: ${snapshot.error}');
            return const Center(child: Text('تعذر تحميل الطلبات حالياً.'));
          }
          final docs = snapshot.data?.docs ?? const [];
          debugPrint('MAP_BOOKINGS_LOAD_SUCCESS count=${docs.length}');
          if (docs.isEmpty) {
            return const Center(
              child: Text('ليس لديك طلبات حالية'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final b = docs[i].data();
              final safeAmount = _safeDouble(b['amount']);
              return Card(
                child: ListTile(
                  title: Text('رحلة نشطة: ${_safeString(b['bookingId'], fallback: docs[i].id)}'),
                  subtitle: Text(
                    'الحالة: ${_safeString(b['status'], fallback: 'pending')} • المبلغ: ${MoneyUtils.iqdWithWords(safeAmount)} • العمولة: ${MoneyUtils.iqdWithWords(_commissionFromBooking(b))}',
                  ),
                  leading: const Icon(Icons.map_rounded),
                  onTap: () async {
                    await _openBookingFromMapTap(
                      context: context,
                      doc: docs[i],
                      role: role,
                      uid: uid,
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class BookingMapDetailsScreen extends StatefulWidget {
  const BookingMapDetailsScreen({
    super.key,
    required this.bookingDocId,
    required this.role,
    required this.currentUserId,
  });

  final String bookingDocId;
  final String role;
  final String currentUserId;

  @override
  State<BookingMapDetailsScreen> createState() => _BookingMapDetailsScreenState();
}

class _BookingMapDetailsScreenState extends State<BookingMapDetailsScreen> {
  final TextEditingController _completionCodeController = TextEditingController();
  Timer? _countdownTimer;
  int _codeSecondsLeft = 0;
  String? _visibleSecretCode;
  bool _completionHandled = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _completionCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('bookings').doc(widget.bookingDocId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final booking = snapshot.data?.data();
        if (booking == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('تفاصيل الرحلة')),
            body: const Center(child: Text('تعذر تحميل الرحلة.')),
          );
        }

        final bookingId = (booking['bookingId'] ?? widget.bookingDocId).toString();
        final type = (booking['type'] ?? '').toString();
        final amount = (booking['amount'] ?? 0).toString();
        final price = (booking['price'] ?? 0).toString();
        final status = (booking['status'] ?? '').toString();
        _maybeHandleCompletionTransition(booking, status);
        final summary = _financialSummary(
          type: type,
          amount: amount,
          price: price,
          booking: booking,
          currentUserId: widget.currentUserId,
        );
        final clientName = (booking['clientName'] ?? '').toString();
        final outletName = (booking['outletName'] ?? '').toString();

        final client = _extractLatLng(booking, candidateRoots: ['clientLocation', 'client']);
        final outlet = _extractLatLng(booking, candidateRoots: ['outletLocation', 'outlet']);

        return Scaffold(
          appBar: AppBar(title: Text('رحلة $bookingId')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                height: 280,
                child: _LiveTripMap(client: client, outlet: outlet),
              ),
              if (client == null && outlet == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'تعذر تحديد الإحداثيات الدقيقة للطرفين حالياً، لكن شاشة الرحلة ما زالت متاحة.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 12),
              if (client != null || outlet != null)
                FilledButton.icon(
                  onPressed: () => _openMapLink(context, client: client, outlet: outlet),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('فتح الاتجاهات في خرائط Google'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SupportChatScreen(
                        threadPath: 'booking_chats/$bookingId/messages',
                        currentUserId: widget.currentUserId,
                        title: widget.role == 'client' ? 'مراسلة المنفذ' : 'مراسلة العميل',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(widget.role == 'client' ? 'مراسلة المنفذ' : 'مراسلة العميل'),
              ),
              const SizedBox(height: 12),
              _buildCompletionSection(context, booking, status),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('أطراف الطلب', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (widget.role == 'outlet' && clientName.isNotEmpty) Text('العميل: $clientName'),
                      if (widget.role == 'client' && outletName.isNotEmpty) Text('المنفذ: $outletName'),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الملخص المالي', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('الاستلام والتسليم', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('سلّم: ${MoneyUtils.iqdWithWords(double.tryParse(summary.$1) ?? 0)}'),
                      Text('استلم: ${MoneyUtils.iqdWithWords(double.tryParse(summary.$2) ?? 0)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _cancelBookingWithConfirmation(status: status),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء الطلب'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompletionSection(BuildContext context, Map<String, dynamic> booking, String status) {
    final isRequester = (booking['clientId'] ?? '').toString() == widget.currentUserId;
    final isProvider = (booking['outletId'] ?? '').toString() == widget.currentUserId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('إكمال الطلب', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (isRequester && status == 'accepted')
              FilledButton(
                onPressed: _markArrivalWithoutShowingCode,
                child: const Text('أنا وصلت'),
              ),
            if (isRequester && status == 'awaiting_provider_code') ...[
              FilledButton.icon(
                onPressed: () => _openSecretCodeSheet(booking),
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('إظهار الرمز السري'),
              ),
            ],
            if (isProvider && status == 'awaiting_provider_code') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _completionCodeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'أدخل رمز الإكمال'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _confirmCompletion,
                child: const Text('تأكيد إكمال الطلب'),
              ),
            ],
            if (status == 'completed')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('تم إكمال الطلب بنجاح.', style: TextStyle(color: Colors.green)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _markArrivalWithoutShowingCode() async {
    await FirebaseFirestore.instance.collection('bookings').doc(widget.bookingDocId).update({
      'status': 'awaiting_provider_code',
      'arrivalMarkedAt': FieldValue.serverTimestamp(),
      'arrivalMarkedBy': widget.currentUserId,
      'completionCode': FieldValue.delete(),
      'completionCodeExpiresAt': FieldValue.delete(),
      'completionCodeIssuedAt': FieldValue.delete(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل الوصول. يمكنك الآن الضغط على "إظهار الرمز السري".')),
    );
  }

  Future<(String, DateTime)> _generateNewSecretCode() async {
    final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
    final expiresAt = DateTime.now().add(const Duration(seconds: 30));
    await FirebaseFirestore.instance.collection('bookings').doc(widget.bookingDocId).update({
      'status': 'awaiting_provider_code',
      'arrivalMarkedBy': widget.currentUserId,
      'completionCode': code,
      'completionCodeExpiresAt': Timestamp.fromDate(expiresAt),
      'completionCodeIssuedAt': FieldValue.serverTimestamp(),
    });
    return (code, expiresAt);
  }

  void _startCountdown(DateTime expiresAt, void Function(void Function()) setModalState) {
    _countdownTimer?.cancel();
    void tick() {
      final diff = expiresAt.difference(DateTime.now()).inSeconds;
      setModalState(() => _codeSecondsLeft = diff < 0 ? 0 : diff);
    }
    tick();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _openSecretCodeSheet(Map<String, dynamic> booking) async {
    final status = (booking['status'] ?? '').toString();
    final isRequester = (booking['clientId'] ?? '').toString() == widget.currentUserId;
    if (!isRequester || status != 'awaiting_provider_code') return;

    final existingCode = (booking['completionCode'] ?? '').toString().trim();
    final existingExpiryRaw = booking['completionCodeExpiresAt'];
    DateTime? existingExpiry;
    if (existingExpiryRaw is Timestamp) {
      existingExpiry = existingExpiryRaw.toDate();
    }

    _visibleSecretCode = existingCode.isEmpty ? null : existingCode;
    if (existingExpiry != null) {
      _codeSecondsLeft = existingExpiry.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30).toInt();
    } else {
      _codeSecondsLeft = 0;
    }
    final shouldGenerateNow = _visibleSecretCode == null || _codeSecondsLeft <= 0;
    if (shouldGenerateNow) {
      final generated = await _generateNewSecretCode();
      _visibleSecretCode = generated.$1;
      existingExpiry = generated.$2;
      _codeSecondsLeft = existingExpiry.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30).toInt();
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          if (existingExpiry != null && _codeSecondsLeft > 0 && _countdownTimer == null) {
            _startCountdown(existingExpiry!, setModalState);
          }
          return AlertDialog(
            title: const Text('الرمز السري المؤقت'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تحذير قانوني ومالي: مشاركة الرمز تعني إقرارًا رسميًا من صاحب الطلب بأنه استلم المبلغ بالكامل وأن العملية المالية تمت بنجاح.',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF2D39C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _visibleSecretCode == null ? 'لم يتم إنشاء رمز بعد' : 'الرمز الحالي: $_visibleSecretCode',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('الوقت المتبقي: ${_codeSecondsLeft}s'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _codeSecondsLeft > 0
                      ? null
                      : () async {
                          final result = await _generateNewSecretCode();
                          _visibleSecretCode = result.$1;
                          existingExpiry = result.$2;
                          _startCountdown(existingExpiry!, setModalState);
                          setModalState(() {});
                        },
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_codeSecondsLeft > 0 ? 'انتظر انتهاء العداد للتجديد' : 'تجديد الرمز (30 ثانية)'),
                ),
                const Text(
                  'هذا الرمز مؤقت وسينتهي تلقائيًا عند انتهاء العدّاد.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _maybeHandleCompletionTransition(Map<String, dynamic> booking, String status) {
    if (status != 'completed' || _completionHandled) return;
    _completionHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openRatingDialogAfterCompletion(booking);
      if (!mounted) return;
      HomeShellScreen.requestTab(0);
      Navigator.of(context).maybePop();
    });
  }

  Future<void> _openRatingDialogAfterCompletion(Map<String, dynamic> booking) async {
    int stars = 5;
    final noteController = TextEditingController();
    final targetRoleLabel = _rateTargetRoleLabel(booking);
    final targetRoleValue = _rateTargetRoleValue(booking);
    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setStateDialog) => AlertDialog(
            title: Text('تقييم $targetRoleLabel'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    children: List.generate(5, (index) {
                      final selected = index < stars;
                      return IconButton(
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        padding: const EdgeInsets.all(6),
                        onPressed: () => setStateDialog(() => stars = index + 1),
                        icon: Icon(
                          selected ? Icons.star_rounded : Icons.star_border_rounded,
                          color: selected ? Colors.amber : Colors.grey,
                        ),
                      );
                    }),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('تخطي'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('إرسال التقييم'),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;

      final bookingId = (booking['bookingId'] ?? widget.bookingDocId).toString();
      final fromUserId = widget.currentUserId;
      final toUserId = ((booking['clientId'] ?? '').toString() == fromUserId)
          ? (booking['outletId'] ?? '').toString()
          : (booking['clientId'] ?? '').toString();
      if (toUserId.isEmpty) return;

      final existing = await FirebaseFirestore.instance
          .collection('ratings')
          .where('bookingId', isEqualTo: bookingId)
          .where('fromUserId', isEqualTo: fromUserId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return;

      await FirebaseFirestore.instance.collection('ratings').add({
        'bookingId': bookingId,
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        'toUserRole': targetRoleValue,
        'stars': stars,
        'adminOnlyNote': noteController.text.trim(),
        'publicNote': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شكراً، تم إرسال تقييمك.')));
    } finally {
      noteController.dispose();
    }
  }

  String _rateTargetRoleLabel(Map<String, dynamic> booking) {
    final isClient = (booking['clientId'] ?? '').toString() == widget.currentUserId;
    return isClient ? 'المنفذ' : 'العميل';
  }

  String _rateTargetRoleValue(Map<String, dynamic> booking) {
    final isClient = (booking['clientId'] ?? '').toString() == widget.currentUserId;
    return isClient ? 'outlet' : 'client';
  }

  Future<void> _confirmCompletion() async {
    final enteredCode = _completionCodeController.text.trim();
    if (enteredCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال الرمز أولاً')));
      return;
    }
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = FirebaseFirestore.instance.collection('bookings').doc(widget.bookingDocId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final status = (data['status'] ?? '').toString();
        final storedCode = (data['completionCode'] ?? '').toString();
        final expiresRaw = data['completionCodeExpiresAt'];
        final expiresAt = expiresRaw is Timestamp ? expiresRaw.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        if (status != 'awaiting_provider_code') {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'invalid-state', message: 'الحالة الحالية لا تسمح بالإكمال.');
        }
        if (DateTime.now().isAfter(expiresAt)) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'code-expired', message: 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.');
        }
        if (storedCode.isEmpty || enteredCode != storedCode) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'invalid-code', message: 'الرمز غير صحيح.');
        }
        tx.update(ref, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'completedBy': widget.currentUserId,
          'completionCode': FieldValue.delete(),
          'completionCodeExpiresAt': FieldValue.delete(),
        });
      });
      if (!mounted) return;
      _completionCodeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إكمال الطلب بنجاح.')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر إكمال الطلب.')));
    }
  }

  Future<void> _cancelBookingWithConfirmation({required String status}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text('هل أنت متأكد من إلغاء الطلب؟'),
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
    if (confirm != true || !mounted) return;

    final uid = widget.currentUserId;
    final isAfterAcceptance = status == 'accepted' || status == 'in_progress' || status == 'awaiting_provider_code';
    final db = FirebaseFirestore.instance;
    final bookingRef = db.collection('bookings').doc(widget.bookingDocId);

    if (!isAfterAcceptance) {
      await bookingRef.update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': uid,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
      Navigator.of(context).maybePop();
      return;
    }

    final now = DateTime.now();
    final dayKey = '${now.year}-${now.month}-${now.day}';
    final dailyRef = db.collection('bookingCancellationDaily').doc('${uid}_$dayKey');

    try {
      await db.runTransaction((tx) async {
        final bookingSnap = await tx.get(bookingRef);
        final currentStatus = (bookingSnap.data()?['status'] ?? '').toString();
        final acceptedState = currentStatus == 'accepted' || currentStatus == 'in_progress' || currentStatus == 'awaiting_provider_code';
        if (!acceptedState) {
          tx.update(bookingRef, {
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
            'cancelledBy': uid,
          });
          return;
        }

        final dailySnap = await tx.get(dailyRef);
        final currentCount = (dailySnap.data()?['count'] as num?)?.toInt() ?? 0;
        if (currentCount >= 3) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'cancel-limit',
            message: 'تم الوصول للحد اليومي للإلغاء بعد القبول (3 مرات).',
          );
        }

        tx.update(bookingRef, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': uid,
        });
        tx.set(dailyRef, {
          'userId': uid,
          'dayKey': dayKey,
          'count': currentCount + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
      Navigator.of(context).maybePop();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر إلغاء الطلب')));
    }
  }

  Future<void> _openMapLink(BuildContext context, {LatLng? client, LatLng? outlet}) async {
    final destination = widget.role == 'client' ? (outlet ?? client) : (client ?? outlet);
    final origin = widget.role == 'client' ? client : outlet;
    if (destination == null) return;

    final googleMapsAppUri = Uri.parse(
      origin != null
          ? 'comgooglemaps://?saddr=${origin.latitude},${origin.longitude}&daddr=${destination.latitude},${destination.longitude}&directionsmode=driving'
          : 'geo:${destination.latitude},${destination.longitude}?q=${destination.latitude},${destination.longitude}',
    );
    final webFallbackUri = Uri.parse(
      origin != null
          ? 'https://www.google.com/maps/dir/?api=1&origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&travelmode=driving'
          : 'https://www.google.com/maps/search/?api=1&query=${destination.latitude},${destination.longitude}',
    );

    if (await canLaunchUrl(googleMapsAppUri)) {
      await launchUrl(googleMapsAppUri, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(webFallbackUri)) {
      await launchUrl(webFallbackUri, mode: LaunchMode.externalApplication);
      return;
    }

    await Clipboard.setData(ClipboardData(text: webFallbackUri.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الخرائط تلقائيًا. تم نسخ الرابط كحل بديل.')),
      );
    }
  }

  LatLng? _extractLatLng(Map<String, dynamic> booking, {required List<String> candidateRoots}) {
    for (final root in candidateRoots) {
      final node = booking[root];
      if (node is Map) {
        final lat = _num(node['lat']);
        final lng = _num(node['lng']);
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }

    final latKeys = ['${candidateRoots.first}Lat', '${candidateRoots.first}_lat', candidateRoots.first == 'clientLocation' ? 'clientLat' : 'outletLat'];
    final lngKeys = ['${candidateRoots.first}Lng', '${candidateRoots.first}_lng', candidateRoots.first == 'clientLocation' ? 'clientLng' : 'outletLng'];

    for (int i = 0; i < latKeys.length; i++) {
      final lat = _num(booking[latKeys[i]]);
      final lng = _num(booking[lngKeys[i]]);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return null;
  }

  double? _num(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  (String, String) _financialSummary({
    required String type,
    required String amount,
    required String price,
    required Map<String, dynamic> booking,
    required String currentUserId,
  }) {
    final amountValue = double.tryParse(amount) ?? 0;
    final commission = (booking['commission'] is num)
        ? (booking['commission'] as num).toDouble()
        : double.tryParse((booking['price'] ?? '0').toString()) ?? 0;
    final acceptedOutletId = (booking['outletId'] ?? '').toString();
    final isAcceptedOutlet = acceptedOutletId.isNotEmpty && currentUserId == acceptedOutletId;

    final withdrawOutletReceive = amountValue;
    final withdrawOutletDeliver = amountValue - commission;
    final depositOutletReceive = amountValue + commission;
    final depositOutletDeliver = amountValue;
    final dischargeOutletReceive = amountValue;
    final dischargeOutletDeliver = amountValue + commission;

    double deliver;
    double receive;
    switch (type) {
      case 'withdraw':
        deliver = isAcceptedOutlet ? withdrawOutletDeliver : withdrawOutletReceive;
        receive = isAcceptedOutlet ? withdrawOutletReceive : withdrawOutletDeliver;
        break;
      case 'deposit':
        deliver = isAcceptedOutlet ? depositOutletDeliver : depositOutletReceive;
        receive = isAcceptedOutlet ? depositOutletReceive : depositOutletDeliver;
        break;
      case 'discharge':
        deliver = isAcceptedOutlet ? dischargeOutletDeliver : dischargeOutletReceive;
        receive = isAcceptedOutlet ? dischargeOutletReceive : dischargeOutletDeliver;
        break;
      default:
        deliver = amountValue;
        receive = amountValue;
    }
    return ('${deliver.toStringAsFixed(0)}', '${receive.toStringAsFixed(0)}');
  }
}

class _LiveTripMap extends StatefulWidget {
  const _LiveTripMap({required this.client, required this.outlet});

  final LatLng? client;
  final LatLng? outlet;

  @override
  State<_LiveTripMap> createState() => _LiveTripMapState();
}

class _LiveTripMapState extends State<_LiveTripMap> {
  GoogleMapController? _controller;

  @override
  Widget build(BuildContext context) {
    final target = widget.client ?? widget.outlet;
    if (target == null) {
      return const Center(
        child: Text('لا توجد إحداثيات متاحة لهذه الرحلة حالياً.'),
      );
    }

    final markers = <Marker>{
      if (widget.client != null)
        Marker(
          markerId: const MarkerId('client'),
          position: widget.client!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'موقع العميل'),
        ),
      if (widget.outlet != null)
        Marker(
          markerId: const MarkerId('outlet'),
          position: widget.outlet!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'موقع المنفذ'),
        ),
    };

    final polylines = <Polyline>{
      if (widget.client != null && widget.outlet != null)
        Polyline(
          polylineId: const PolylineId('route_line'),
          points: [widget.client!, widget.outlet!],
          color: Colors.green,
          width: 4,
        ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: kIsWeb
          ? Container(
              color: const Color(0xFFF3F4F6),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'الخريطة التفاعلية غير متاحة حالياً على الويب. استخدم زر الاتجاهات.',
                textAlign: TextAlign.center,
              ),
            )
          : GoogleMap(
              initialCameraPosition: CameraPosition(target: target, zoom: 16),
              mapType: MapType.normal,
              myLocationButtonEnabled: false,
              compassEnabled: true,
              zoomControlsEnabled: false,
              markers: markers,
              polylines: polylines,
              onMapCreated: (c) {
                debugPrint('[MAP INIT] map created');
                _controller = c;
                _fitBounds();
              },
      ),
    );
  }

  Future<void> _fitBounds() async {
    if (_controller == null) return;

    final client = widget.client;
    final outlet = widget.outlet;

    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;

    if (client == null && outlet == null) return;

    if (client == null || outlet == null) {
      final point = client ?? outlet;
      if (point != null) {
        await _controller?.animateCamera(CameraUpdate.newLatLngZoom(point, 16));
      }
      return;
    }

    final latDiff = (client.latitude - outlet.latitude).abs();
    final lngDiff = (client.longitude - outlet.longitude).abs();
    final isVeryClose = latDiff < 0.00008 && lngDiff < 0.00008;
    if (isVeryClose) {
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(client, 18));
      return;
    }

    final south = math.min(client.latitude, outlet.latitude);
    final north = math.max(client.latitude, outlet.latitude);
    final west = math.min(client.longitude, outlet.longitude);
    final east = math.max(client.longitude, outlet.longitude);

    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );

    try {
      await _controller?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
    } catch (error) {
      debugPrint('[MAP INIT] fit bounds failed: $error');
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(client, 16));
    }
  }
}