import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../services/location_guard_service.dart';
import '../services/money_utils.dart';
import '../theme/app_colors.dart';

class CreateBookingScreen extends StatefulWidget {
  const CreateBookingScreen({
    super.key,
    required this.profile,
  });

  final Map<String, dynamic> profile;

  @override
  State<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends State<CreateBookingScreen> {
  static const _minCommissionRate = 0.003;
  static const _maxCommissionRate = 0.006;
  static const _suggestedRate = 0.005;
  static const _cardBank = 'مصرف الرافدين';

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _priceController = TextEditingController();

  String _type = 'withdraw';
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = (widget.profile['role'] ?? 'client').toString();
    final amount = _parseMoney(_amountController.text) ?? 0;
    final price = _parseMoney(_priceController.text) ?? 0;
    final isDischarge = _type == 'discharge';
    final minAllowedCommission = amount * _minCommissionRate;
    final maxAllowedCommission = amount * _maxCommissionRate;
    final suggestedPrice = (amount * _suggestedRate) < 250 ? 250.0 : (amount * _suggestedRate);

    final typeItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'withdraw', child: Text('سحب من بطاقتك')),
      const DropdownMenuItem(value: 'deposit', child: Text('شحن إلى بطاقتك')),
      if (role == 'outlet') const DropdownMenuItem(value: 'discharge', child: Text('تفريغ')),
    ];

    if (role != 'outlet' && _type == 'discharge') {
      _type = 'withdraw';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('منفذك - إنشاء طلب')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'نوع الطلب'),
                  items: typeItems,
                  onChanged: (value) => setState(() => _type = value ?? 'withdraw'),
                ),
                const SizedBox(height: 12),
                _RequestTypeInfoCard(type: _type),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _cardBank,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'مصرف البطاقة',
                    prefixIcon: Icon(Icons.account_balance_rounded),
                  ),
                ),
                if (amount > 0 && !isDischarge)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'العمولة المسموحة لهذا الطلب بين ${MoneyUtils.iqdWithWords(minAllowedCommission)} و ${MoneyUtils.iqdWithWords(maxAllowedCommission)}.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final parsed = _parseMoney(value ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'يرجى إدخال مبلغ صحيح';
                    }
                    return null;
                  },
                ),
                if (amount > 0 && !isDischarge)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('المبلغ المدخل: ${MoneyUtils.iqdWithWords(amount)}'),
                  ),
                const SizedBox(height: 14),
                if (amount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'العمولة المقترحة: ${MoneyUtils.iqdWithWords(suggestedPrice)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                    ),
                  ),
                TextFormField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'العمولة'),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final parsed = _parseMoney(value ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'يرجى إدخال عمولة صحيحة';
                    }
                    if (!isDischarge && amount > 0 && parsed < amount * _minCommissionRate) {
                      return 'العمولة أقل من الحد الأدنى المسموح';
                    }
                    if (!isDischarge && amount > 0 && parsed > amount * _maxCommissionRate) {
                      return 'العمولة أعلى من الحد الأعلى المسموح';
                    }
                    return null;
                  },
                ),
                if (price > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('العمولة المدخلة: ${MoneyUtils.iqdWithWords(price)}'),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _createBooking,
                    icon: _saving ? const SizedBox.shrink() : const Icon(Icons.save_rounded),
                    label: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('إنشاء الطلب'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestNotificationsOptional() async {
    try {
      final current = await FirebaseMessaging.instance.getNotificationSettings();
      FirebaseCrashlytics.instance.setCustomKey('notification_permission_status', current.authorizationStatus.name);
      if (current.authorizationStatus == AuthorizationStatus.authorized ||
          current.authorizationStatus == AuthorizationStatus.provisional) {
        return;
      }
      if (!mounted) return;
      final ask = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text('تفعيل الإشعارات'),
          content: const Text('يمكنك تفعيل الإشعارات لتصلك تحديثات الطلبات والرسائل الجديدة.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('لاحقاً')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('تفعيل الإشعارات')),
          ],
        ),
      );
      if (ask != true) return;
      final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      FirebaseCrashlytics.instance.setCustomKey('notification_permission_status', settings.authorizationStatus.name);
      debugPrint('[REQUEST CREATE] notification permission=${settings.authorizationStatus}');
    } catch (error, stackTrace) {
      debugPrint('[REQUEST CREATE] optional notification permission failed: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
    }
  }

  double? _parseMoney(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    const arabicDigits = {'٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9'};
    arabicDigits.forEach((key, mapped) {
      value = value.replaceAll(key, mapped);
    });
    value = value.replaceAll(',', '').replaceAll(' ', '');
    return double.tryParse(value);
  }

  Future<void> _createBooking() async {
    if (_saving) return;
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    debugPrint('[REQUEST CREATE] start');
    setState(() => _saving = true);

    final uid = (widget.profile['uid'] ?? '').toString();
    final role = (widget.profile['role'] ?? 'client').toString();
    final governorate = (widget.profile['governorate'] ?? '').toString();
    final clientName = (widget.profile['fullName'] ?? '').toString();
    final amount = _parseMoney(_amountController.text) ?? 0;
    final price = _parseMoney(_priceController.text) ?? 0;
    final commission = price;

    final minAllowed = amount * _minCommissionRate;
    final maxAllowed = amount * _maxCommissionRate;

    if (_type != 'discharge' && commission + 0.0001 < minAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('العمولة أقل من الحد الأدنى المسموح وهو ${MoneyUtils.iqdWithWords(minAllowed)}.')),
      );
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (_type != 'discharge' && commission > maxAllowed + 0.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('العمولة أعلى من الحد الأعلى المسموح وهو ${MoneyUtils.iqdWithWords(maxAllowed)}.')),
      );
      if (mounted) setState(() => _saving = false);
      return;
    }

    FirebaseCrashlytics.instance.log('request_create_location_required');
    FirebaseCrashlytics.instance.setCustomKey('request_create_location_required', true);
    final clientPosition = await LocationGuardService.instance.requireCurrentLocation(
      context,
      title: 'مشاركة الموقع مطلوبة لإنشاء الطلب',
      message: 'يجب مشاركة موقعك الحالي قبل إنشاء أي طلب جديد.',
      crashlyticsKey: 'request_create_location_required',
    );
    if (clientPosition == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    final clientLat = clientPosition.latitude;
    final clientLng = clientPosition.longitude;

    await _requestNotificationsOptional();

    try {
      if (role == 'client') {
        FirebaseCrashlytics.instance.setCustomKey('client_active_request_check', true);
        final active = await FirebaseFirestore.instance
            .collection('bookings')
            .where('clientId', isEqualTo: uid)
            .where('status', whereIn: ['pending', 'accepted', 'in_progress', 'awaiting_provider_code'])
            .limit(1)
            .get();
        FirebaseCrashlytics.instance.setCustomKey('client_active_request_found', active.docs.isNotEmpty);
        if (active.docs.isNotEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لديك طلب نشط حالياً. لا يمكنك إنشاء طلب جديد قبل إكمال أو إلغاء الطلب الحالي.')),
          );
          return;
        }
      }

      final duplicateGuard = await FirebaseFirestore.instance
          .collection('bookings')
          .where('clientId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .where('type', isEqualTo: _type)
          .where('amount', isEqualTo: amount)
          .where('price', isEqualTo: price)
          .limit(5)
          .get();

      if (duplicateGuard.docs.isNotEmpty) {
        for (final doc in duplicateGuard.docs) {
          final createdAt = doc.data()['createdAt'];
          if (createdAt is Timestamp) {
            final age = DateTime.now().difference(createdAt.toDate());
            if (age.inSeconds <= 45) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم إنشاء طلب مشابه قبل لحظات. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.')),
              );
              return;
            }
          }
        }
      }

      final ref = FirebaseFirestore.instance.collection('bookings').doc();
      await ref.set({
        'bookingId': ref.id,
        'createdById': uid,
        'clientId': uid,
        'clientName': clientName,
        'outletId': null,
        'status': 'pending',
        'type': _type,
        'amount': amount,
        'price': price,
        'commissionRate': _type == 'discharge' ? null : _maxCommissionRate,
        'commission': commission,
        'cardBank': _cardBank,
        'governorate': governorate,
        'requestOwnerRole': role,
        'createdAt': FieldValue.serverTimestamp(),
        'clientLat': clientLat,
        'clientLng': clientLng,
        'clientLocation': {'lat': clientLat, 'lng': clientLng},
      });

      debugPrint('[REQUEST CREATE] success bookingId=${ref.id}');
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('[REQUEST CREATE] failed: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء الطلب حالياً: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _RequestTypeInfoCard extends StatelessWidget {
  const _RequestTypeInfoCard({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final title = switch (type) {
      'deposit' => 'شحن إلى بطاقتك',
      'discharge' => 'تفريغ رصيد المنفذ',
      _ => 'سحب من بطاقتك',
    };
    final body = switch (type) {
      'deposit' => 'اختر هذا النوع إذا تريد شحن مبلغ إلى بطاقتك عن طريق منفذ مناسب.',
      'discharge' => 'خاص بالمنافذ لتفريغ الرصيد حسب الطلبات المتاحة.',
      _ => 'اختر هذا النوع إذا تريد سحب مبلغ من بطاقتك عن طريق منفذ مناسب.',
    };
    final icon = switch (type) {
      'deposit' => Icons.add_card_rounded,
      'discharge' => Icons.sync_alt_rounded,
      _ => Icons.credit_card_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
