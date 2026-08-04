import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/business_hours_service.dart';
import '../services/distance_utils.dart';
import '../services/location_guard_service.dart';
import '../services/money_utils.dart';
import '../theme/app_colors.dart';

class OutletOffersScreen extends StatefulWidget {
  const OutletOffersScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<OutletOffersScreen> createState() => _OutletOffersScreenState();
}

class _OutletOffersScreenState extends State<OutletOffersScreen> {
  static const _minimumAmount = 1000.0;
  static const _cardBank = 'مصرف الرافدين';

  bool _savingLocation = false;

  String get _role => (widget.profile['role'] ?? '').toString();
  String get _uid => (widget.profile['uid'] ?? '').toString();
  bool get _isOutlet => _role == 'outlet';

  double? _profileLat(Map<String, dynamic> data) => DistanceUtils.toDouble(
        data['currentLat'] ??
            data['fixedLat'] ??
            data['lat'] ??
            data['clientLat'],
      );

  double? _profileLng(Map<String, dynamic> data) => DistanceUtils.toDouble(
        data['currentLng'] ??
            data['fixedLng'] ??
            data['lng'] ??
            data['clientLng'],
      );

  double? _distanceKm(
    Map<String, dynamic> offer,
    Map<String, dynamic> currentProfile,
  ) {
    return DistanceUtils.kmBetween(
      fromLat: _profileLat(currentProfile),
      fromLng: _profileLng(currentProfile),
      toLat: offer['outletLat'],
      toLng: offer['outletLng'],
    );
  }

  Future<void> _shareLocation() async {
    if (_uid.isEmpty || _savingLocation) return;
    setState(() => _savingLocation = true);
    final position = await LocationGuardService.instance.requireCurrentLocation(
      context,
      title: 'مشاركة الموقع',
      message: 'شارك موقعك حتى تظهر لك المسافة والبعد عن المنافذ بدقة.',
      crashlyticsKey: 'outlet_offers_distance_location_required',
      timeLimit: const Duration(seconds: 8),
    );
    if (position != null) {
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({
        'currentLat': position.latitude,
        'currentLng': position.longitude,
        'lat': position.latitude,
        'lng': position.longitude,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      widget.profile['currentLat'] = position.latitude;
      widget.profile['currentLng'] = position.longitude;
      widget.profile['lat'] = position.latitude;
      widget.profile['lng'] = position.longitude;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث الموقع لعرض المسافات.')),
        );
      }
    }
    if (mounted) setState(() => _savingLocation = false);
  }

  Future<void> _openCreateOfferSheet(
    Map<String, dynamic> currentProfile,
  ) async {
    final priceCtrl = TextEditingController();
    final maxClientsCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var offerType = 'withdraw';

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
          child: StatefulBuilder(
            builder: (context, setModalState) => Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إنشاء عرض منفذ',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'حدد السعر لكل مليون دينار وعدد العملاء الأقصى. العرض يبقى ظاهراً بدون وقت انتهاء.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: offerType,
                    decoration: const InputDecoration(
                      labelText: 'نوع العرض',
                      prefixIcon: Icon(Icons.swap_horiz_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'withdraw',
                        child: Text('سحب'),
                      ),
                      DropdownMenuItem(
                        value: 'deposit',
                        child: Text('شحن'),
                      ),
                      DropdownMenuItem(
                        value: 'discharge',
                        child: Text('تفريغ'),
                      ),
                    ],
                    onChanged: (value) =>
                        setModalState(() => offerType = value ?? 'withdraw'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [MoneyInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'كل مليون بـ',
                      prefixIcon: Icon(Icons.payments_rounded),
                      suffixText: 'د.ع',
                    ),
                    validator: (value) {
                      final price = _parseMoney(value ?? '');
                      if (price == null || price <= 0) {
                        return 'أدخل السعر لكل مليون دينار';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: maxClientsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'عدد العملاء',
                      prefixIcon: Icon(Icons.groups_rounded),
                    ),
                    validator: (value) {
                      final count = int.tryParse((value ?? '').trim());
                      if (count == null || count <= 0) {
                        return 'أدخل الحد الأقصى للعملاء';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (formKey.currentState?.validate() != true) return;
                        Navigator.pop(ctx, true);
                      },
                      icon: const Icon(Icons.add_circle_rounded),
                      label: const Text('نشر العرض'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (ok != true) return;
    final pricePerMillion = _parseMoney(priceCtrl.text) ?? 0;
    final maxClients = int.tryParse(maxClientsCtrl.text.trim()) ?? 1;
    final outletLat = DistanceUtils.toDouble(currentProfile['fixedLat'] ??
        currentProfile['currentLat'] ??
        currentProfile['lat']);
    final outletLng = DistanceUtils.toDouble(currentProfile['fixedLng'] ??
        currentProfile['currentLng'] ??
        currentProfile['lng']);

    await FirebaseFirestore.instance.collection('outlet_offers').add({
      'outletId': _uid,
      'outletName': 'منفذ',
      'outletRegion':
          (currentProfile['region'] ?? currentProfile['outletRegion'] ?? '')
              .toString()
              .trim(),
      'outletGovernorate': (currentProfile['governorate'] ?? '').toString(),
      'businessHours': currentProfile['businessHours'],
      'outletLat': outletLat,
      'outletLng': outletLng,
      'type': offerType,
      'pricePerMillion': pricePerMillion,
      'maxClients': maxClients,
      'activeAcceptedCount': 0,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر عرض المنفذ.')),
      );
    }
  }

  Future<void> _acceptOffer(String offerId, Map<String, dynamic> offer) async {
    if (_uid.isEmpty) return;
    final outletOpen = await _isOutletOpenForOffer(offer);
    if (!outletOpen) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('المنفذ مغلق حالياً، لا يمكن قبول العرض.')),
      );
      return;
    }
    final result = await _openAcceptOfferSheet(offer);
    if (result == null) return;

    final clientPosition =
        await LocationGuardService.instance.requireCurrentLocation(
      context,
      title: 'مشاركة الموقع مطلوبة لقبول العرض',
      message: 'نحتاج موقعك حتى يظهر الطلب على الخريطة ويتم حساب المسافة.',
      crashlyticsKey: 'outlet_offer_accept_location_required',
      timeLimit: const Duration(seconds: 8),
    );
    if (clientPosition == null) return;

    final offerRef =
        FirebaseFirestore.instance.collection('outlet_offers').doc(offerId);
    final bookings = FirebaseFirestore.instance.collection('bookings');
    final bookingRef = bookings.doc();
    final now = DateTime.now();
    final activeSeats = await bookings
        .where('sourceOutletOfferId', isEqualTo: offerId)
        .where('status',
            whereIn: ['accepted', 'in_progress', 'awaiting_provider_code'])
        .limit(100)
        .get();

    final activeSeatCount = activeSeats.docs.where((doc) {
      final data = doc.data();
      final expires = data['offerSeatExpiresAt'];
      if (expires is Timestamp && expires.toDate().isBefore(now)) {
        return false;
      }
      return true;
    }).length;

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final freshOffer = await tx.get(offerRef);
        if (!freshOffer.exists) throw Exception('العرض غير متاح.');
        final data = freshOffer.data() ?? <String, dynamic>{};
        if ((data['status'] ?? '').toString() != 'active') {
          throw Exception('العرض غير متاح حالياً.');
        }
        final maxClients = (data['maxClients'] is num)
            ? (data['maxClients'] as num).toInt()
            : 1;
        if (activeSeatCount >= maxClients) {
          throw Exception('اكتمل عدد العملاء النشطين لهذا العرض.');
        }
        final outletId = (data['outletId'] ?? '').toString();
        final amount = result.amount;
        final commission =
            max(250.0, (amount / 1000000.0) * result.pricePerMillion);
        final currentRole = (widget.profile['role'] ?? _role).toString();
        final clientName = currentRole == 'outlet'
            ? 'منفذ'
            : (widget.profile['fullName'] ?? 'عميل').toString();
        tx.set(bookingRef, {
          'bookingId': bookingRef.id,
          'createdById': _uid,
          'clientId': _uid,
          'clientName': clientName,
          'outletId': outletId,
          'outletName': 'منفذ',
          'outletRegion': (data['outletRegion'] ?? '').toString(),
          'outletGovernorate': (data['outletGovernorate'] ?? '').toString(),
          'status': 'accepted',
          'type': result.type,
          'amount': amount,
          'price': commission,
          'commission': commission,
          'pricePerMillion': result.pricePerMillion,
          'cardBank': _cardBank,
          'governorate': (widget.profile['governorate'] ?? '').toString(),
          'requestOwnerRole': currentRole == 'outlet' ? 'outlet' : 'client',
          'createdAt': FieldValue.serverTimestamp(),
          'acceptedAt': FieldValue.serverTimestamp(),
          'source': 'outlet_offer',
          'sourceOutletOfferId': offerId,
          'offerSeatExpiresAt': Timestamp.fromDate(
            now.add(const Duration(days: 8)),
          ),
          'clientLat': clientPosition.latitude,
          'clientLng': clientPosition.longitude,
          'clientLocation': {
            'lat': clientPosition.latitude,
            'lng': clientPosition.longitude,
          },
          'outletLat': data['outletLat'],
          'outletLng': data['outletLng'],
          'outletLocation': {
            'lat': data['outletLat'],
            'lng': data['outletLng']
          },
        });
        tx.update(offerRef, {
          'activeAcceptedCount': activeSeatCount + 1,
          'lastAcceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(offerRef.collection('acceptances').doc(bookingRef.id), {
          'bookingId': bookingRef.id,
          'clientId': _uid,
          'clientName': 'عميل',
          'amount': amount,
          'commission': commission,
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
          'seatExpiresAt': Timestamp.fromDate(now.add(const Duration(days: 8))),
        });
      });

      await FirebaseFirestore.instance.collection('bookingEvents').add({
        'type': 'booking_accepted',
        'bookingId': bookingRef.id,
        'clientId': _uid,
        'outletId': (offer['outletId'] ?? '').toString(),
        'acceptedOutletId': (offer['outletId'] ?? '').toString(),
        'actorId': _uid,
        'source': 'outlet_offer',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم قبول العرض وإنشاء الطلب. ستجده في الخريطة.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<_AcceptOfferResult?> _openAcceptOfferSheet(
    Map<String, dynamic> offer,
  ) async {
    final amountCtrl = TextEditingController();
    final type = (offer['type'] ?? 'withdraw').toString();
    final pricePerMillion = offer['pricePerMillion'] is num
        ? (offer['pricePerMillion'] as num).toDouble()
        : 0.0;
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet<_AcceptOfferResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final amount = _parseMoney(amountCtrl.text) ?? 0;
          final commission = max(250.0, (amount / 1000000.0) * pricePerMillion);
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
                    'قبول عرض المنفذ',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'نوع الطلب'),
                    child: Text(
                      _typeLabel(type),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [MoneyInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'المبلغ',
                      prefixIcon: Icon(Icons.payments_rounded),
                    ),
                    onChanged: (_) => setModalState(() {}),
                    validator: (value) {
                      final parsed = _parseMoney(value ?? '');
                      if (parsed == null || parsed < _minimumAmount) {
                        return 'أقل مبلغ مسموح هو ${MoneyUtils.formatIqD(_minimumAmount)}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFD89B)),
                    ),
                    child: Text(
                      'عمولة الطلب المتوقعة: ${MoneyUtils.formatIqD(commission)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (formKey.currentState?.validate() != true) return;
                        Navigator.pop(
                          ctx,
                          _AcceptOfferResult(
                            type: type,
                            amount: _parseMoney(amountCtrl.text) ?? 0,
                            pricePerMillion: pricePerMillion,
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('تأكيد قبول العرض'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double? _parseMoney(String input) {
    final digits = MoneyUtils.normalizeDigitsOnly(input);
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'deposit':
        return 'شحن';
      case 'discharge':
        return 'تفريغ';
      case 'withdraw':
      default:
        return 'سحب';
    }
  }

  Future<int> _activeSeatCount(String offerId) async {
    final now = DateTime.now();
    final snap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('sourceOutletOfferId', isEqualTo: offerId)
        .where('status',
            whereIn: ['accepted', 'in_progress', 'awaiting_provider_code'])
        .limit(100)
        .get();
    return snap.docs.where((doc) {
      final expires = doc.data()['offerSeatExpiresAt'];
      if (expires is Timestamp && expires.toDate().isBefore(now)) return false;
      return true;
    }).length;
  }

  Future<bool> _isOutletOpenForOffer(Map<String, dynamic> offer) async {
    final outletId = (offer['outletId'] ?? '').toString();
    Map<String, dynamic> profile = Map<String, dynamic>.from(offer);
    if (outletId.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(outletId)
          .get()
          .timeout(const Duration(seconds: 6));
      profile = {...profile, ...?snap.data()};
    }
    return BusinessHoursService.isOpenNow(profile);
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return const Scaffold(body: Center(child: Text('تعذر تحميل الحساب.')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(_uid).snapshots(),
      builder: (context, profileSnap) {
        final liveProfile = {
          ...widget.profile,
          ...?profileSnap.data?.data(),
        };
        final stream = FirebaseFirestore.instance
            .collection('outlet_offers')
            .where('status', isEqualTo: 'active')
            .snapshots();

        return Scaffold(
          appBar: AppBar(title: const Text('عروض المنافذ')),
          floatingActionButton: _isOutlet
              ? FloatingActionButton.extended(
                  onPressed: () => _openCreateOfferSheet(liveProfile),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إنشاء عرض'),
                )
              : null,
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data();
                final outletId = (data['outletId'] ?? '').toString();
                final offerType = (data['type'] ?? 'withdraw').toString();
                if (!_isOutlet && offerType == 'discharge') return false;
                if (outletId == _uid && !_isOutlet) return false;
                return true;
              }).toList()
                ..sort((a, b) {
                  final da =
                      _distanceKm(a.data(), liveProfile) ?? double.maxFinite;
                  final db =
                      _distanceKm(b.data(), liveProfile) ?? double.maxFinite;
                  return da.compareTo(db);
                });

              if (docs.isEmpty) {
                return _EmptyOffersState(isOutlet: _isOutlet);
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final km = _distanceKm(data, liveProfile);
                  final outletId = (data['outletId'] ?? '').toString();
                  final offerType = (data['type'] ?? 'withdraw').toString();
                  final canAccept = (!_isOutlet && offerType != 'discharge') ||
                      (_isOutlet &&
                          offerType == 'discharge' &&
                          outletId != _uid);
                  return FutureBuilder<int>(
                    future: _activeSeatCount(doc.id),
                    builder: (context, seatSnap) => FutureBuilder<bool>(
                      future: _isOutletOpenForOffer(data),
                      builder: (context, openSnap) {
                        if (openSnap.hasData && openSnap.data == false) {
                          return const SizedBox.shrink();
                        }
                        return _OutletOfferCard(
                          offerId: doc.id,
                          data: data,
                          activeSeatCount: seatSnap.data,
                          distanceText: DistanceUtils.text(km),
                          distanceLevel: DistanceUtils.level(km),
                          needsLocation: km == null,
                          savingLocation: _savingLocation,
                          onShareLocation: _shareLocation,
                          onAccept: canAccept
                              ? () => _acceptOffer(doc.id, data)
                              : null,
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _AcceptOfferResult {
  const _AcceptOfferResult({
    required this.type,
    required this.amount,
    required this.pricePerMillion,
  });

  final String type;
  final double amount;
  final double pricePerMillion;
}

class _EmptyOffersState extends StatelessWidget {
  const _EmptyOffersState({required this.isOutlet});

  final bool isOutlet;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_offer_rounded,
                size: 54, color: AppColors.accent),
            const SizedBox(height: 12),
            const Text(
              'لا توجد عروض منافذ حالياً',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              isOutlet
                  ? 'أنشئ عرضاً جديداً ليظهر للعملاء.'
                  : 'ستظهر هنا عروض المنافذ المتاحة قريباً.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutletOfferCard extends StatelessWidget {
  const _OutletOfferCard({
    required this.offerId,
    required this.data,
    required this.activeSeatCount,
    required this.distanceText,
    required this.distanceLevel,
    required this.needsLocation,
    required this.savingLocation,
    required this.onShareLocation,
    required this.onAccept,
  });

  final String offerId;
  final Map<String, dynamic> data;
  final int? activeSeatCount;
  final String distanceText;
  final String distanceLevel;
  final bool needsLocation;
  final bool savingLocation;
  final VoidCallback onShareLocation;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final region =
        (data['outletRegion'] ?? 'المنطقة غير محددة').toString().trim();
    final governorate = (data['outletGovernorate'] ?? '').toString().trim();
    final type = (data['type'] ?? 'withdraw').toString();
    final typeLabel = _offerTypeLabel(type);
    final price = data['pricePerMillion'] is num
        ? (data['pricePerMillion'] as num).toDouble()
        : 0.0;
    final maxClients =
        data['maxClients'] is num ? (data['maxClients'] as num).toInt() : 0;
    final storedActiveAccepted = data['activeAcceptedCount'] is num
        ? (data['activeAcceptedCount'] as num).toInt()
        : 0;
    final activeAccepted = activeSeatCount ?? storedActiveAccepted;
    final remaining = max(0, maxClients - activeAccepted);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFD89B)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 29,
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppColors.primaryDark,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'منفذ',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (governorate.isNotEmpty) governorate,
                        if (region.isNotEmpty) region,
                      ].isEmpty
                          ? 'المنطقة غير محددة'
                          : [
                              if (governorate.isNotEmpty) governorate,
                              if (region.isNotEmpty) region,
                            ].join(' - '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E8),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFFFD89B)),
                    ),
                    child: Text(
                      typeLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    distanceText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    distanceLevel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFD89B)),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: AppColors.accent, size: 30),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'لكل مليون',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  MoneyUtils.formatIqD(price),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.groups_rounded,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                'المقاعد النشطة المتبقية: $remaining',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (needsLocation) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: savingLocation ? null : onShareLocation,
              icon: const Icon(Icons.my_location_rounded),
              label: Text(
                savingLocation
                    ? 'جاري تحديث الموقع...'
                    : 'مشاركة الموقع لرؤية البعد والمسافة',
              ),
            ),
          ],
          if (onAccept != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: remaining <= 0 ? null : onAccept,
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('قبول العرض'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _offerTypeLabel(String type) {
  switch (type) {
    case 'deposit':
      return 'شحن';
    case 'discharge':
      return 'تفريغ';
    case 'withdraw':
    default:
      return 'سحب';
  }
}
