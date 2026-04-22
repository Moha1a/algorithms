import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_guard_service.dart';
import '../services/money_utils.dart';

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
    final minAllowedCommission = amount * _minCommissionRate;
    final maxAllowedCommission = amount * _maxCommissionRate;
    final suggestedPrice = (amount * _suggestedRate) < 250 ? 250.0 : (amount * _suggestedRate);

    final typeItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'withdraw', child: Text('سحب (سحب من بطاقتك)')),
      const DropdownMenuItem(value: 'deposit', child: Text('شحن (شحن إلى بطاقتك)')),
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
                  onChanged: (v) => setState(() => _type = v ?? 'withdraw'),
                ),
                if (amount > 0)
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
                  validator: (v) {
                    final n = _parseMoney((v ?? ''));
                    if (n == null || n <= 0) return 'يرجى إدخال مبلغ صحيح';
                    return null;
                  },
                ),
                if (amount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('قيمة المبلغ: ${MoneyUtils.iqdWithWords(amount)}'),
                  ),
                const SizedBox(height: 14),

                if (amount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'السعر المقترح: ${MoneyUtils.iqdWithWords(suggestedPrice)}  •  توفير 17% عن السعر الاصلي',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                    ),
                  ),
                TextFormField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'العمولة'),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = _parseMoney((v ?? ''));
                    if (n == null || n <= 0) return 'يرجى إدخال سعر صحيح';
                    if (amount > 0 && n < amount * _minCommissionRate) {
                      return 'العمولة أقل من الحد الأدنى المسموح (0.003 لكل دينار)';
                    }
                    if (amount > 0 && n > amount * _maxCommissionRate) {
                      return 'العمولة أعلى من الحد الأعلى المسموح (0.006 لكل دينار)';
                    }
                    return null;
                  },
                ),
                if (price > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('قيمة السعر: ${MoneyUtils.iqdWithWords(price)}'),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _createBooking,
                    icon: _saving ? const SizedBox.shrink() : const Icon(Icons.save_rounded),
                    label: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('حفظ الطلب'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  double? _parseMoney(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    const arabicDigits = {'٠':'0','١':'1','٢':'2','٣':'3','٤':'4','٥':'5','٦':'6','٧':'7','٨':'8','٩':'9'};
    arabicDigits.forEach((k,v){ value = value.replaceAll(k,v); });
    value = value.replaceAll(',', '').replaceAll(' ', '');
    return double.tryParse(value);
  }

  Future<void> _createBooking() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final hasLocation = await LocationGuardService.instance.ensureLocationEnabled(context);
    if (!hasLocation) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    final uid = (widget.profile['uid'] ?? '').toString();
    final role = (widget.profile['role'] ?? 'client').toString();
    final governorate = (widget.profile['governorate'] ?? '').toString();
    final clientName = (widget.profile['fullName'] ?? '').toString();
    final amount = _parseMoney(_amountController.text) ?? 0;
    final price = _parseMoney(_priceController.text) ?? 0;
    final commission = price;

    final minAllowed = amount * _minCommissionRate;
    final maxAllowed = amount * _maxCommissionRate;

    if (commission + 0.0001 < minAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم رفض الطلب: الحد الأدنى للعمولة هو ${MoneyUtils.iqdWithWords(minAllowed)}.')),
      );
      return;
    }
    if (commission > maxAllowed + 0.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم رفض الطلب: الحد الأعلى للعمولة هو ${MoneyUtils.iqdWithWords(maxAllowed)}.')),
      );
      return;
    }

    Position clientPosition;
    try {
      clientPosition = await LocationGuardService.instance.getFreshCurrentPosition();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديد موقعك الحالي بدقة: $e')),
      );
      return;
    }

    final clientLat = clientPosition.latitude;
    final clientLng = clientPosition.longitude;

    try {
      if (role == 'client') {
        final active = await FirebaseFirestore.instance
            .collection('bookings')
            .where('clientId', isEqualTo: uid)
            .where('status', whereIn: ['pending', 'accepted', 'in_progress'])
            .limit(1)
            .get();
        if (active.docs.isNotEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكنك إنشاء أكثر من طلب جاري واحد حالياً')),
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
                const SnackBar(content: Text('تم إرسال طلب مماثل قبل لحظات. يرجى الانتظار قليلاً.')),
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
        'commissionRate': _maxCommissionRate,
        'commission': commission,
        'clientLat': clientLat,
        'clientLng': clientLng,
        'clientLocation': {'lat': clientLat, 'lng': clientLng},
        'governorate': governorate,
        'requestOwnerRole': role,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء الطلب: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}