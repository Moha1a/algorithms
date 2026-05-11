import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_colors.dart';
import 'create_booking_screen.dart';
import 'support_chat_screen.dart';
import '../services/money_utils.dart';
import '../services/location_guard_service.dart';
import 'map_screen.dart';

enum BookingFilter { active, history }
enum OutletRequestTab { clientRequests, outletRequests }
enum OutletTypeFilter { withdraw, deposit, discharge }

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({
    super.key,
    required this.profile,
    this.title = 'منفذك - الطلبات',
    this.lockedOutletTab,
    this.showRequestOwnerTabs = true,
    this.showCreateButton = true,
    this.forOwnRequests = false,
    this.showHistoryTabs = true,
  });

  final Map<String, dynamic> profile;
  final String title;
  final OutletRequestTab? lockedOutletTab;
  final bool showRequestOwnerTabs;
  final bool showCreateButton;
  final bool forOwnRequests;
  final bool showHistoryTabs;

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  BookingFilter _filter = BookingFilter.active;
  OutletRequestTab _outletTab = OutletRequestTab.clientRequests;
  OutletTypeFilter _outletType = OutletTypeFilter.withdraw;
  double? _providerLat;
  double? _providerLng;

  @override
  void initState() {
    super.initState();
    final role = (widget.profile['role'] ?? '').toString();
    if (role == 'outlet' && !widget.forOwnRequests) {
      _loadProviderLocation();
    }
  }

  Future<void> _loadProviderLocation() async {
    try {
      final pos = await LocationGuardService.instance.getFreshCurrentPosition();
      if (!mounted) return;
      setState(() {
        _providerLat = pos.latitude;
        _providerLng = pos.longitude;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final uid = (widget.profile['uid'] ?? '').toString();
    final role = (widget.profile['role'] ?? '').toString();
    final fullName = (widget.profile['fullName'] ?? '').toString();
    final effectiveOutletTab = widget.lockedOutletTab ?? _outletTab;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: widget.showCreateButton ? FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => CreateBookingScreen(profile: widget.profile),
            ),
          );
          if (created == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم إنشاء الطلب بنجاح')),
            );
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('إنشاء طلب'),
      ) : null,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primarySoft, Color(0xFFFFF8ED)]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحبًا ${fullName.isEmpty ? 'مستخدم' : fullName}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'الدور الحالي: ${role == 'outlet' ? 'منفذ' : 'عميل'}',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                ),
              ],
            ),
          ),
          if (role == 'outlet' && widget.showRequestOwnerTabs)
            _SegmentContainer(
              child: Row(
                children: [
                  Expanded(
                    child: _FilterChip(
                      label: 'طلبات العملاء',
                      selected: effectiveOutletTab == OutletRequestTab.clientRequests,
                      onTap: () => setState(() => _outletTab = OutletRequestTab.clientRequests),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FilterChip(
                      label: 'طلبات المنافذ',
                      selected: effectiveOutletTab == OutletRequestTab.outletRequests,
                      onTap: () => setState(() => _outletTab = OutletRequestTab.outletRequests),
                    ),
                  ),
                ],
              ),
            ),
          if (role == 'outlet' && !widget.forOwnRequests)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TypeBadge(
                    label: 'سحب',
                    selected: _outletType == OutletTypeFilter.withdraw,
                    onTap: () => setState(() => _outletType = OutletTypeFilter.withdraw),
                  ),
                  _TypeBadge(
                    label: 'شحن',
                    selected: _outletType == OutletTypeFilter.deposit,
                    onTap: () => setState(() => _outletType = OutletTypeFilter.deposit),
                  ),
                  if (effectiveOutletTab == OutletRequestTab.outletRequests)
                    _TypeBadge(
                      label: 'تفريغ',
                      selected: _outletType == OutletTypeFilter.discharge,
                      onTap: () => setState(() => _outletType = OutletTypeFilter.discharge),
                    ),
                ],
              ),
            ),
          if (widget.showHistoryTabs)
            _SegmentContainer(
              child: Row(
              children: [
                Expanded(
                  child: _FilterChip(
                    label: 'الطلبات الجارية',
                    selected: _filter == BookingFilter.active,
                    onTap: () => setState(() => _filter = BookingFilter.active),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FilterChip(
                    label: 'الطلبات السابقة',
                    selected: _filter == BookingFilter.history,
                    onTap: () => setState(() => _filter = BookingFilter.history),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _bookingsQuery(uid: uid, role: role, effectiveOutletTab: effectiveOutletTab).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'تعذر تحميل الطلبات.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                final filtered = (widget.showHistoryTabs ? docs.where(_matchesFilter) : docs.where((d) => (d.data()['status'] ?? "").toString() == "pending")).where((d) {
                  if (role == 'outlet' && !widget.forOwnRequests) {
                    if ((d.data()['createdById'] ?? '').toString() == uid) return false;
                    final km = _distanceToRequestOwnerKm(d.data());
                    if (km != null && km > 15) return false;
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        _filter == BookingFilter.active ? 'لا توجد طلبات جارية حالياً.' : 'لا توجد طلبات سابقة حالياً.',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = filtered[index].data();
                    final bookingId = (data['bookingId'] ?? filtered[index].id).toString();
                    final status = (data['status'] ?? '').toString();
                    final type = (data['type'] ?? '').toString();
                    final amount = (data['amount'] ?? '-').toString();
                    final price = (data['price'] ?? '-').toString();
                    final ownerDistanceKm = _distanceToRequestOwnerKm(data);

                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [
                          BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 8)),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (role == 'outlet' && !widget.forOwnRequests) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _typeLabel(type),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  _StatusBadge(status: status),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _chip('المبلغ: ${MoneyUtils.iqdWithWords(double.tryParse(amount) ?? 0)}'),
                                  _chip('العمولة: ${_commissionText(amount, price)}'),
                                  _UserBadge(creatorId: (data['createdById'] ?? '').toString()),
                                  _chip('المسافة: ${_formatDistanceKm(ownerDistanceKm)}'),
                                ],
                              ),
                            ] else ...[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 170),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'الطلب',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '#${_shortBookingId(bookingId)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    constraints: const BoxConstraints(maxWidth: 170),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primarySoft,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Text(
                                      MoneyUtils.iqdWithWords(double.tryParse(amount) ?? 0),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  _StatusBadge(status: status),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _chip('النوع: ${_typeLabel(type)}'),
                                  _chip('السعر: $price'),
                                ],
                              ),
                            ],
                            if (role == 'client' && (status == 'accepted' || status == 'in_progress' || status == 'completed') && (data['outletName'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('المنفذ المقبول: ${(data['outletName'] ?? '').toString()}'),
                              ),
                            if (role == 'outlet' && (status == 'accepted' || status == 'in_progress' || status == 'completed') && (data['clientName'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('صاحب الطلب: ${(data['clientName'] ?? '').toString()}'),
                              ),
                            if (status == 'cancelled' && (data['cancelReason'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'سبب الإلغاء: ${_cancelReasonLabel((data['cancelReason'] ?? '').toString())}',
                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                                ),
                              ),
                            const SizedBox(height: 10),
                            _actionsForBooking(
                              bookingDocId: filtered[index].id,
                              data: data,
                              role: role,
                              uid: uid,
                            ),
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
      ),
    );
  }

  Query<Map<String, dynamic>> _bookingsQuery({
    required String uid,
    required String role,
    required OutletRequestTab effectiveOutletTab,
  }) {
    final base = FirebaseFirestore.instance.collection('bookings');
    if (widget.forOwnRequests) {
      return base.where('createdById', isEqualTo: uid);
    }
    if (role == 'outlet') {
      final requestOwnerRole = effectiveOutletTab == OutletRequestTab.clientRequests ? 'client' : 'outlet';
      final typeValue = switch (_outletType) {
        OutletTypeFilter.withdraw => 'withdraw',
        OutletTypeFilter.deposit => 'deposit',
        OutletTypeFilter.discharge => 'discharge',
      };
      return base.where('status', isEqualTo: 'pending').where('requestOwnerRole', isEqualTo: requestOwnerRole).where('type', isEqualTo: typeValue);
    }
    return base.where('clientId', isEqualTo: uid);
  }

  bool _matchesFilter(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final status = (doc.data()['status'] ?? '').toString();
    const activeStatuses = {'pending', 'accepted', 'in_progress', 'awaiting_provider_code'};
    if (_filter == BookingFilter.active) {
      return activeStatuses.contains(status);
    }
    return !activeStatuses.contains(status);
  }


  double? _distanceToRequestOwnerKm(Map<String, dynamic> data) {
    if (_providerLat == null || _providerLng == null) return null;
    final clientLat = _toDouble(data['clientLat']);
    final clientLng = _toDouble(data['clientLng']);
    if (clientLat == null || clientLng == null) return null;
    final meters = Geolocator.distanceBetween(_providerLat!, _providerLng!, clientLat, clientLng);
    return meters / 1000;
  }

  String _distanceLabel(double km) {
    if (km <= 5) return 'قريب';
    if (km <= 8) return 'متوسط البعد';
    if (km <= 12) return 'بعيد';
    return 'بعيد جدا';
  }

  String _formatDistanceKm(double? km) {
    FirebaseCrashlytics.instance.setCustomKey('distance_calculation_status', km == null ? 'missing' : 'available');
    if (km == null || km.isNaN || km.isInfinite || km < 0) return 'المسافة غير متوفرة';
    final meters = km * 1000;
    if (meters < 1000) return '${meters.round()} م';
    return '${km.toStringAsFixed(1)} كم (${_distanceLabel(km)})';
  }

  double? _proposalDistanceKm(Map<String, dynamic> booking, Map<String, dynamic> proposal) {
    final clientLat = _toDouble(booking['clientLat']);
    final clientLng = _toDouble(booking['clientLng']);
    final outletLat = _toDouble(proposal['outletLat']);
    final outletLng = _toDouble(proposal['outletLng']);
    if (clientLat == null || clientLng == null || outletLat == null || outletLng == null) return null;
    return Geolocator.distanceBetween(clientLat, clientLng, outletLat, outletLng) / 1000;
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }


  String _typeLabel(String type) {
    switch (type) {
      case 'withdraw':
        return 'سحب';
      case 'deposit':
        return 'شحن';
      case 'discharge':
        return 'تفريغ';
      default:
        return type;
    }
  }

  String _commissionText(String amountText, String priceText) {
    final amount = double.tryParse(amountText) ?? 0;
    final price = double.tryParse(priceText) ?? amount;
    final commission = price;
    return MoneyUtils.iqdWithWords(commission);
  }

  String _shortBookingId(String bookingId) {
    final clean = bookingId.trim();
    if (clean.length <= 10) return clean;
    return '${clean.substring(0, 6)}...${clean.substring(clean.length - 4)}';
  }

  String _cancelReasonLabel(String reason) {
    switch (reason) {
      case 'auto_cancel_no_arrival_within_3h':
        return 'تم الإلغاء تلقائيًا لعدم الضغط على "أنا وصلت" خلال 3 ساعات من القبول.';
      case 'auto_cancel_no_completion_within_1h':
        return 'تم الإلغاء تلقائيًا لعدم تأكيد الإكمال خلال ساعة من تسجيل الوصول.';
      default:
        return reason;
    }
  }

  Widget _actionsForBooking({
    required String bookingDocId,
    required Map<String, dynamic> data,
    required String role,
    required String uid,
  }) {
    final status = (data['status'] ?? '').toString();
    final proposals = (data['priceProposals'] as List?)?.cast<Map>() ?? const [];
    final isPending = status == 'pending';
    final acceptedOutlet = (data['outletId'] ?? '').toString();
    final bookingId = (data['bookingId'] ?? bookingDocId).toString();

    final widgets = <Widget>[];

    if (role == 'outlet' && isPending) {
      final hasMyProposal = proposals.any((p) => (p['outletId'] ?? '').toString() == uid);
      widgets.add(
        OutlinedButton(
          onPressed: () => _suggestPrice(bookingDocId),
          child: Text(hasMyProposal ? 'تم اقتراح سعر — انقر لتغيير الاقتراح' : 'اقتراح سعر'),
        ),
      );
    }

    if (role == 'client' && isPending && proposals.isNotEmpty) {
      for (final p in proposals) {
        final outletId = (p['outletId'] ?? '').toString();
        final price = (p['price'] ?? '').toString();
        final proposalDistanceKm = _proposalDistanceKm(data, Map<String, dynamic>.from(p));
        final distanceText = ' — المسافة: ${_formatDistanceKm(proposalDistanceKm)}';
        widgets.add(
          FutureBuilder<double?>(
            future: _fetchAverageRating(outletId),
            builder: (context, snap) {
              final ratingText = snap.data == null ? 'بدون تقييم' : '⭐ ${snap.data!.toStringAsFixed(1)}';
              return OutlinedButton(
                onPressed: () => _acceptProposal(bookingDocId, outletId, price),
                child: Text(
                  'قبول عرض $price من $outletId $ratingText$distanceText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        );
      }
    }

    final isParty = acceptedOutlet.isNotEmpty && (acceptedOutlet == uid || (data['clientId'] ?? '').toString() == uid);
    final isChatOpen = status == 'accepted' || status == 'in_progress';
    if (isParty && isChatOpen) {
      widgets.add(
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookingMapDetailsScreen(
                  bookingDocId: bookingDocId,
                  role: role,
                  currentUserId: uid,
                ),
              ),
            );
          },
          icon: const Icon(Icons.map_rounded),
          label: const Text('متابعة الرحلة على الخريطة'),
        ),
      );
      widgets.add(
        _chatButtonWithUnread(
          bookingId: bookingId,
          uid: uid,
          role: role,
        ),
      );
      widgets.add(
        TextButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SupportChatScreen(
                  threadPath: 'trip_support/$bookingId/messages',
                  currentUserId: uid,
                  title: 'دعم الرحلة',
                ),
              ),
            );
          },
          icon: const Icon(Icons.support_agent_rounded),
          label: const Text('دعم الرحلة'),
        ),
      );
    }


    final isOwner = (data['createdById'] ?? data['clientId'] ?? '').toString() == uid;
    if (isOwner && status == 'pending') {
      widgets.add(
        OutlinedButton(
          onPressed: () => _cancelAcceptedBooking(bookingDocId, uid),
          child: const Text('إلغاء الطلب'),
        ),
      );
    }

    final isClientOwner = (data['clientId'] ?? '').toString() == uid;
    final isAcceptedProvider = acceptedOutlet == uid;

    if (isClientOwner && status == 'accepted') {
      widgets.add(
        FilledButton(
          onPressed: () => _markArrivedAndGenerateCode(bookingDocId, uid),
          child: const Text('أنا وصلت'),
        ),
      );
    }

    if (isAcceptedProvider && status == 'awaiting_provider_code') {
      widgets.add(
        FilledButton(
          onPressed: () => _confirmCompletionWithCode(bookingDocId, uid),
          child: const Text('تأكيد إكمال الطلب'),
        ),
      );
    }

    if (status == 'completed' && isParty) {
      final targetRoleLabel = _rateTargetRoleLabel(data, uid);
      widgets.add(
        TextButton(
          onPressed: () => _rateBooking(bookingDocId, data, uid),
          child: Text('تقييم $targetRoleLabel بعد الإكمال'),
        ),
      );
    }

    if (widgets.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: widgets);
  }

  Widget _chatButtonWithUnread({
    required String bookingId,
    required String uid,
    required String role,
  }) {
    final stream = FirebaseFirestore.instance
        .collection('booking_chats/$bookingId/messages')
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final unread = docs.where((d) => (d.data()['senderId'] ?? '').toString() != uid).length;
        final hasUnread = unread > 0;
        return TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: hasUnread ? Colors.deepOrange : null,
            backgroundColor: hasUnread ? const Color(0xFFFFF3E0) : null,
          ),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SupportChatScreen(
                  threadPath: 'booking_chats/$bookingId/messages',
                  currentUserId: uid,
                  title: role == 'client' ? 'مراسلة المنفذ' : 'مراسلة العميل',
                ),
              ),
            );
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.chat_bubble_outline_rounded),
              if (hasUnread)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
          label: Text(role == 'client' ? 'مراسلة المنفذ' : 'مراسلة العميل'),
        );
      },
    );
  }

  Future<void> _suggestPrice(String bookingDocId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اقتراح سعر'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'السعر المقترح'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final price = double.tryParse(ctrl.text.trim());
    if (price == null || price <= 0) return;


    final uid = (widget.profile['uid'] ?? '').toString();

    final bookingSnapForValidation = await FirebaseFirestore.instance.collection('bookings').doc(bookingDocId).get();
    final bookingDataForValidation = bookingSnapForValidation.data() ?? <String, dynamic>{};
    final bookingType = (bookingDataForValidation['type'] ?? '').toString();
    final bookingAmount = (bookingDataForValidation['amount'] is num)
        ? (bookingDataForValidation['amount'] as num).toDouble()
        : double.tryParse((bookingDataForValidation['amount'] ?? '0').toString()) ?? 0;
    final ownerRequestedPrice = (bookingDataForValidation['price'] is num)
        ? (bookingDataForValidation['price'] as num).toDouble()
        : double.tryParse((bookingDataForValidation['price'] ?? '0').toString()) ?? 0;

    if (bookingType == 'withdraw' || bookingType == 'deposit') {
      final minCommission = bookingAmount * 0.003;
      final maxCommission = bookingAmount * 0.006;
      if (price < minCommission - 0.0001 || price > maxCommission + 0.0001) {
        if (!mounted) return;
        final typeLabel = bookingType == 'withdraw' ? 'السحب' : 'الشحن';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم رفض الاقتراح: في $typeLabel يجب أن يكون السعر بين '
              '${MoneyUtils.iqdWithWords(minCommission)} و ${MoneyUtils.iqdWithWords(maxCommission)} '
              '(0.003 إلى 0.006 من مبلغ الطلب).',
            ),
          ),
        );
        return;
      }
    }
    if (bookingType == 'withdraw' && ownerRequestedPrice > 0) {
      final maxByOwner = ownerRequestedPrice * 1.2;
      if (price > maxByOwner + 0.0001) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم رفض الاقتراح: في السحب لا يمكن أن يزيد سعر المنفذ عن 20% من سعر صاحب الطلب (${MoneyUtils.iqdWithWords(maxByOwner)}).'),
          ),
        );
        return;
      }
    }
    if (bookingType == 'deposit' && ownerRequestedPrice > 0) {
      final maxByOwner = ownerRequestedPrice + 5000;
      if (price > maxByOwner + 0.0001) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم رفض الاقتراح: في الشحن الحد الأعلى هو ${MoneyUtils.iqdWithWords(maxByOwner)} (سعر الطلب + 5000).'),
          ),
        );
        return;
      }
    }

    FirebaseCrashlytics.instance.log('price_proposal_location_required');
    FirebaseCrashlytics.instance.setCustomKey('price_proposal_location_required', true);
    final outletPosition = await LocationGuardService.instance.requireCurrentLocation(
      context,
      title: 'مشاركة الموقع مطلوبة لعرض السعر',
      message: 'نحتاج موقع المنفذ الحالي حتى يظهر للعميل ويتم حساب المسافة بينكما قبل قبول الطلب.',
      crashlyticsKey: 'price_proposal_location_required',
    );
    if (outletPosition == null) return;
    final outletLat = outletPosition.latitude;
    final outletLng = outletPosition.longitude;
    final clientLatForDistance = _toDouble(bookingDataForValidation['clientLat']);
    final clientLngForDistance = _toDouble(bookingDataForValidation['clientLng']);
    final distanceKm = (clientLatForDistance == null || clientLngForDistance == null)
        ? null
        : Geolocator.distanceBetween(clientLatForDistance, clientLngForDistance, outletLat, outletLng) / 1000;
    debugPrint('[ProposalFlow] provider distance=${_formatDistanceKm(distanceKm)}');

    final ref = FirebaseFirestore.instance.collection('bookings').doc(bookingDocId);
    String ownerId = '';
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      ownerId = (data['clientId'] ?? data['createdById'] ?? '').toString();
      final proposals = (data['priceProposals'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? <Map<String, dynamic>>[];
      final idx = proposals.indexWhere((p) => (p['outletId'] ?? '').toString() == uid);
      final uniqueOutletIds = proposals.map((p) => (p['outletId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();

      if (idx < 0 && uniqueOutletIds.length >= 2) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'proposal-limit-exceeded',
          message: 'تم الوصول للحد الأقصى: يسمح فقط باقتراحين من منفذين مختلفين لهذا الطلب',
        );
      }

      final item = <String, dynamic>{
        'outletId': uid,
        'price': price,
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      };
      item['outletLat'] = outletLat;
      item['outletLng'] = outletLng;
      item['outletLocation'] = {'lat': outletLat, 'lng': outletLng};
      if (distanceKm != null) item['distanceKm'] = distanceKm;
      if (idx >= 0) {
        proposals[idx] = item;
      } else {
        proposals.add(item);
      }
      tx.update(ref, {'priceProposals': proposals, 'lastProposalAt': FieldValue.serverTimestamp()});
    });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'تعذر حفظ الاقتراح')),
      );
      return;
    }
    debugPrint('[ProposalFlow] proposal saved/updated bookingId=$bookingDocId ownerId=$ownerId');
    if (ownerId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('bookingEvents').add({
          'type': 'booking_price_proposed',
          'bookingId': bookingDocId,
          'clientId': ownerId,
          'outletId': uid,
          'actorId': uid,
          'price': price,
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint('[ProposalFlow] booking price proposal event created bookingId=$bookingDocId recipientUid=$ownerId');
      } catch (e) {
        debugPrint('[ProposalFlow] booking price proposal event failed bookingId=$bookingDocId recipientUid=$ownerId error=$e');
      }
    }
  }

  Future<void> _acceptProposal(String bookingDocId, String outletId, String price) async {
    debugPrint('[ProposalFlow] accepting proposal bookingId=$bookingDocId outletId=$outletId');
    final p = double.tryParse(price) ?? 0;
    final bookingRef = FirebaseFirestore.instance.collection('bookings').doc(bookingDocId);
    final bookingSnap = await bookingRef.get();
    final bookingData = bookingSnap.data() ?? <String, dynamic>{};
    final proposals = (bookingData['priceProposals'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? <Map<String, dynamic>>[];
    final acceptedProposal = proposals.cast<Map<String, dynamic>?>().firstWhere(
      (proposal) => (proposal?['outletId'] ?? '').toString() == outletId,
      orElse: () => null,
    );

    final outletSnap = await FirebaseFirestore.instance.collection('users').doc(outletId).get();
    final outletName = (outletSnap.data()?['fullName'] ?? outletSnap.data()?['outletName'] ?? outletId).toString();
    double? outletLat = _toDouble(acceptedProposal?['outletLat']);
    double? outletLng = _toDouble(acceptedProposal?['outletLng']);
    if (outletLat == null || outletLng == null) {
      FirebaseCrashlytics.instance.log('accept_location_required');
      FirebaseCrashlytics.instance.setCustomKey('accept_location_required', true);
      final outletPosition = await LocationGuardService.instance.requireCurrentLocation(
        context,
        title: 'مشاركة الموقع مطلوبة لقبول الطلب',
        message: 'نحتاج موقع المنفذ الحالي حتى يظهر للعميل ويتم حساب المسافة بينكما.',
        crashlyticsKey: 'accept_location_required',
      );
      if (outletPosition == null) return;
      outletLat = outletPosition.latitude;
      outletLng = outletPosition.longitude;
    }

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final bookingSnapTx = await tx.get(bookingRef);
        final bookingDataTx = bookingSnapTx.data() ?? <String, dynamic>{};
        final currentStatus = (bookingDataTx['status'] ?? '').toString();
        if (currentStatus != 'pending') {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'invalid-state',
            message: 'تم تحديث حالة الطلب من قبل مستخدم آخر. أعد تحميل الصفحة.',
          );
        }

        final payload = <String, dynamic>{
          'outletId': outletId,
          'status': 'accepted',
          'price': p,
          'commission': p,
          'acceptedAt': FieldValue.serverTimestamp(),
          'outletName': outletName,
        };
        payload['outletLat'] = outletLat;
        payload['outletLng'] = outletLng;
        payload['outletLocation'] = {'lat': outletLat, 'lng': outletLng};
        tx.update(bookingRef, payload);
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'تعذر قبول العرض حاليًا.')),
      );
      return;
    }
    final clientId = (widget.profile['uid'] ?? '').toString();
    try {
      await FirebaseFirestore.instance.collection('bookingEvents').add({
        'type': 'booking_accepted',
        'bookingId': bookingDocId,
        'clientId': clientId,
        'outletId': outletId,
        'acceptedOutletId': outletId,
        'actorId': clientId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[ProposalFlow] booking accepted event created bookingId=$bookingDocId outletId=$outletId');
    } catch (e) {
      debugPrint('[ProposalFlow] booking accepted event failed bookingId=$bookingDocId outletId=$outletId error=$e');
    }
    await _cancelOtherPendingOffersForOutlet(
      acceptedBookingDocId: bookingDocId,
      outletId: outletId,
    );
    if (clientId.isNotEmpty) {
      await _createNotification(
        toUserId: clientId,
        type: 'booking_accepted',
        bookingId: bookingDocId,
        title: 'تم قبول الطلب',
        body: 'أصبح الطلب نشطًا ويمكن متابعة الرحلة',
      );
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<void> _cancelOtherPendingOffersForOutlet({
    required String acceptedBookingDocId,
    required String outletId,
  }) async {
    final pendingSnap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('status', isEqualTo: 'pending')
        .limit(150)
        .get();
    if (pendingSnap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in pendingSnap.docs) {
      if (doc.id == acceptedBookingDocId) continue;
      final data = doc.data();
      final proposals = (data['priceProposals'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];
      if (proposals.isEmpty) continue;
      final filtered = proposals
          .where((p) => (p['outletId'] ?? '').toString() != outletId)
          .toList();
      if (filtered.length == proposals.length) continue;
      batch.update(doc.reference, {
        'priceProposals': filtered,
        'lastProposalCleanupAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _rateBooking(String bookingDocId, Map<String, dynamic> booking, String uid) async {
    final ctrl = TextEditingController();
    int stars = 5;
    final targetRoleLabel = _rateTargetRoleLabel(booking, uid);
    final targetRoleValue = _rateTargetRoleValue(booking, uid);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('تقييم $targetRoleLabel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: stars,
                items: List.generate(5, (i) => i + 1).map((n) => DropdownMenuItem(value: n, child: Text('$n نجوم'))).toList(),
                onChanged: (v) => setModalState(() => stars = v ?? 5),
              ),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final toUserId = ((booking['clientId'] ?? '').toString() == uid) ? (booking['outletId'] ?? '').toString() : (booking['clientId'] ?? '').toString();
    if (toUserId.isEmpty) return;

    final existing = await FirebaseFirestore.instance
        .collection('ratings')
        .where('bookingId', isEqualTo: (booking['bookingId'] ?? bookingDocId).toString())
        .where('fromUserId', isEqualTo: uid)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لقد قمت بالتقييم مسبقًا لهذا الطلب')));
      return;
    }

    await FirebaseFirestore.instance.collection('ratings').add({
      'bookingId': (booking['bookingId'] ?? bookingDocId).toString(),
      'fromUserId': uid,
      'toUserId': toUserId,
      'toUserRole': targetRoleValue,
      'stars': stars,
      'adminOnlyNote': ctrl.text.trim(),
      'publicNote': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _rateTargetRoleLabel(Map<String, dynamic> booking, String uid) {
    final isClient = (booking['clientId'] ?? '').toString() == uid;
    return isClient ? 'المنفذ' : 'العميل';
  }

  String _rateTargetRoleValue(Map<String, dynamic> booking, String uid) {
    final isClient = (booking['clientId'] ?? '').toString() == uid;
    return isClient ? 'outlet' : 'client';
  }


  Future<double?> _fetchAverageRating(String userId) async {
    if (userId.trim().isEmpty) return null;
    final snap = await FirebaseFirestore.instance.collection('ratings').where('toUserId', isEqualTo: userId).limit(100).get();
    if (snap.docs.isEmpty) return null;
    double total = 0;
    int count = 0;
    for (final d in snap.docs) {
      final s = d.data()['stars'];
      if (s is num) {
        total += s.toDouble();
        count += 1;
      }
    }
    if (count == 0) return null;
    return total / count;
  }

  Future<void> _cancelAcceptedBooking(String bookingDocId, String uid) async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final db = FirebaseFirestore.instance;
    final bookingRef = db.collection('bookings').doc(bookingDocId);
    final dayKey = '${dayStart.year}-${dayStart.month}-${dayStart.day}';
    final dailyRef = db.collection('bookingCancellationDaily').doc('${uid}_$dayKey');

    try {
      await db.runTransaction((tx) async {
        final bookingSnap = await tx.get(bookingRef);
        final booking = bookingSnap.data() ?? <String, dynamic>{};
        final status = (booking['status'] ?? '').toString();
        final started = status == 'accepted' || status == 'in_progress' || status == 'awaiting_provider_code';
        final pending = status == 'pending';
        if (!started && !pending) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'invalid-state', message: 'لا يمكن إلغاء هذا الطلب في حالته الحالية');
        }

        if (started) {
          final dailySnap = await tx.get(dailyRef);
          final currentCount = (dailySnap.data()?['count'] as num?)?.toInt() ?? 0;
          if (currentCount >= 3) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'cancel-limit', message: 'تم الوصول للحد اليومي للإلغاء (3 مرات)');
          }
          tx.set(dailyRef, {
            'userId': uid,
            'dayKey': dayKey,
            'count': currentCount + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        tx.update(bookingRef, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': uid,
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر إلغاء الطلب')));
    }
  }

  Future<void> _markArrivedAndGenerateCode(String bookingDocId, String uid) async {
    final ref = FirebaseFirestore.instance.collection('bookings').doc(bookingDocId);
    await ref.update({
      'status': 'awaiting_provider_code',
      'arrivalMarkedBy': uid,
      'arrivalMarkedAt': FieldValue.serverTimestamp(),
      'completionCode': FieldValue.delete(),
      'completionCodeExpiresAt': FieldValue.delete(),
      'completionCodeIssuedAt': FieldValue.delete(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل الوصول. انتقل إلى الخريطة ثم اضغط "إظهار الرمز السري".')),
    );
  }

  Future<void> _confirmCompletionWithCode(String bookingDocId, String uid) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إدخال رمز الإكمال'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'الرمز المؤقت'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final code = controller.text.trim();
    final ref = FirebaseFirestore.instance.collection('bookings').doc(bookingDocId);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final status = (data['status'] ?? '').toString();
        final storedCode = (data['completionCode'] ?? '').toString();
        final expiresRaw = data['completionCodeExpiresAt'];
        final expiresAt = expiresRaw is Timestamp ? expiresRaw.toDate() : DateTime.fromMillisecondsSinceEpoch(0);

        if (status != 'awaiting_provider_code') {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'invalid-state', message: 'الحالة لا تسمح بالإكمال الآن');
        }
        if (DateTime.now().isAfter(expiresAt)) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'code-expired', message: 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا');
        }
        if (storedCode.isEmpty || storedCode != code) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'invalid-code', message: 'الرمز غير صحيح');
        }

        tx.update(ref, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'completedBy': uid,
          'completionCode': FieldValue.delete(),
          'completionCodeExpiresAt': FieldValue.delete(),
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إكمال الطلب بنجاح')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر إكمال الطلب')));
    }
  }

  Future<void> _createNotification({
    required String toUserId,
    required String type,
    required String bookingId,
    required String title,
    required String body,
  }) async {
    if (toUserId.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('notifications').add({
      'toUserId': toUserId,
      'type': type,
      'bookingId': bookingId,
      'title': title,
      'body': body,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

class _UserBadge extends StatelessWidget {
  const _UserBadge({required this.creatorId});

  final String creatorId;

  @override
  Widget build(BuildContext context) {
    if (creatorId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(creatorId).get(),
      builder: (context, snapshot) {
        final text = (snapshot.data?.data()?['adminBadgeText'] ?? snapshot.data?.data()?['adminBadge'] ?? 'بدون شارة').toString();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Text('شارة: $text', style: const TextStyle(fontSize: 12)),
        );
      },
    );
  }
}

class _SegmentContainer extends StatelessWidget {
  const _SegmentContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(color: selected ? AppColors.primaryDark : AppColors.textMuted, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'pending' => AppColors.primaryDark,
      'accepted' => AppColors.info,
      'in_progress' => const Color(0xFF7C3AED),
      'completed' => AppColors.success,
      'cancelled' => AppColors.danger,
      _ => AppColors.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
