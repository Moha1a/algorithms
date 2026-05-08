import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/location_guard_service.dart';
import '../services/money_utils.dart';
import '../services/ratings_service.dart';
import 'chat_screen.dart';
import 'create_booking_screen.dart';
import 'support_chat_screen.dart';

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
  final _bookings = FirebaseFirestore.instance.collection('bookings');
  final _users = FirebaseFirestore.instance.collection('users');
  final _ratingsService = RatingsService();
  final _locationGuard = LocationGuardService.instance;

  bool _loadingAction = false;

  Future<void> _markArrived(String docId) async {
    if (_loadingAction) return;
    setState(() => _loadingAction = true);
    try {
      await _bookings.doc(docId).set({
        'status': 'awaiting_provider_code',
        'arrivalMarkedBy': widget.currentUserId,
        'arrivalAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر تحديث الحالة')));
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  Future<void> _completeWithCode(String docId, String expectedCode) async {
    if (_loadingAction) return;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد إكمال الطلب'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'رمز التحقق'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true) return;
    if (controller.text.trim() != expectedCode.trim()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز التحقق غير صحيح')));
      return;
    }

    setState(() => _loadingAction = true);
    try {
      await _bookings.doc(docId).set({
        'status': 'completed',
        'completedBy': widget.currentUserId,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إكمال الطلب بنجاح')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر إكمال الطلب')));
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  Future<void> _cancelAccepted(String docId) async {
    if (_loadingAction) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text('هل تريد إلغاء هذا الطلب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لا')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loadingAction = true);
    try {
      await _bookings.doc(docId).set({
        'status': 'cancelled',
        'cancelledBy': widget.currentUserId,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر إلغاء الطلب')));
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _bookings.doc(widget.bookingDocId).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.active && !snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final booking = snap.data?.data();
        if (booking == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('متابعة الطلب على الخريطة')),
            body: const Center(child: Text('لم يتم العثور على الطلب')),
          );
        }

        final status = (booking['status'] ?? '').toString();
        final type = (booking['type'] ?? '').toString();
        final amount = (booking['amount'] ?? '').toString();
        final price = (booking['price'] ?? '').toString();
        final bookingId = (booking['bookingId'] ?? widget.bookingDocId).toString();

        final client = _extractLatLng(booking, candidateRoots: ['clientLocation', 'client']);
        final outlet = _extractLatLng(booking, candidateRoots: ['outletLocation', 'outlet']);

        final acceptedOutletId = (booking['outletId'] ?? '').toString();
        final clientId = (booking['clientId'] ?? '').toString();
        final isClientOwner = clientId.isNotEmpty && clientId == widget.currentUserId;
        final isAcceptedProvider = acceptedOutletId.isNotEmpty && acceptedOutletId == widget.currentUserId;
        final isParty = isClientOwner || isAcceptedProvider;

        final mapAvailable = client != null || outlet != null;
        final canOpenDirections = mapAvailable;
        final (deliver, receive) = _financialSummary(
          type: type,
          amount: amount,
          price: price,
          booking: booking,
          currentUserId: widget.currentUserId,
        );

        return Scaffold(
          appBar: AppBar(title: const Text('متابعة الطلب على الخريطة')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رقم الطلب: $bookingId', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('الحالة: $status'),
                    Text('النوع: $type'),
                    Text('المبلغ: ${MoneyUtils.iqdWithWords(double.tryParse(amount) ?? 0)}'),
                    Text('التسليم: ${MoneyUtils.iqdWithWords(double.tryParse(deliver) ?? 0)}'),
                    Text('الاستلام: ${MoneyUtils.iqdWithWords(double.tryParse(receive) ?? 0)}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 280,
                child: _LiveTripMap(client: client, outlet: outlet),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: canOpenDirections ? () => _openMapLink(context, client: client, outlet: outlet) : null,
                    icon: const Icon(Icons.map_rounded),
                    label: const Text('متابعة الطلب على الخريطة'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isParty
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  bookingId: bookingId,
                                  currentUserId: widget.currentUserId,
                                  title: widget.role == 'client' ? 'مراسلة المنفذ' : 'مراسلة العميل',
                                ),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('المحادثة'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SupportChatScreen(
                            threadPath: 'trip_support/$bookingId/messages',
                            currentUserId: widget.currentUserId,
                            title: 'دعم الرحلة',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('دعم الرحلة'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (status == 'accepted' && isClientOwner)
                FilledButton(
                  onPressed: _loadingAction ? null : () => _markArrived(widget.bookingDocId),
                  child: _loadingAction
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('أنا وصلت'),
                ),
              if (status == 'awaiting_provider_code' && isAcceptedProvider)
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: _bookings.doc(widget.bookingDocId).get(),
                  builder: (context, s) {
                    final code = (s.data?.data()?['completionCode'] ?? '').toString();
                    return FilledButton(
                      onPressed: (_loadingAction || code.isEmpty) ? null : () => _completeWithCode(widget.bookingDocId, code),
                      child: _loadingAction
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('تأكيد إكمال الطلب'),
                    );
                  },
                ),
              if (status == 'pending' && isClientOwner)
                OutlinedButton(
                  onPressed: _loadingAction ? null : () => _cancelAccepted(widget.bookingDocId),
                  child: const Text('إلغاء الطلب'),
                ),
              const SizedBox(height: 16),
              _PartyInfoCard(
                users: _users,
                clientId: clientId,
                outletId: acceptedOutletId,
                role: widget.role,
                ratingsService: _ratingsService,
              ),
            ],
          ),
        );
      },
    );
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
        if (_isValidCoordinate(lat, lng)) return LatLng(lat!, lng!);
      }
    }

    final latKeys = ['${candidateRoots.first}Lat', '${candidateRoots.first}_lat', candidateRoots.first == 'clientLocation' ? 'clientLat' : 'outletLat'];
    final lngKeys = ['${candidateRoots.first}Lng', '${candidateRoots.first}_lng', candidateRoots.first == 'clientLocation' ? 'clientLng' : 'outletLng'];

    for (int i = 0; i < latKeys.length; i++) {
      final lat = _num(booking[latKeys[i]]);
      final lng = _num(booking[lngKeys[i]]);
      if (_isValidCoordinate(lat, lng)) return LatLng(lat!, lng!);
    }
    return null;
  }

  bool _isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
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
    final validClient = _safeLatLng(widget.client);
    final validOutlet = _safeLatLng(widget.outlet);
    final target = validClient ?? validOutlet;
    FirebaseCrashlytics.instance.setCustomKey('map_plugin_used', 'google_maps_flutter');
    FirebaseCrashlytics.instance.setCustomKey('has_client_location', validClient != null);
    FirebaseCrashlytics.instance.setCustomKey('has_outlet_location', validOutlet != null);
    if (target == null) {
      FirebaseCrashlytics.instance.log('map_open_blocked_invalid_coordinates');
      return const Center(
        child: Text('لا توجد إحداثيات متاحة لهذه الرحلة حالياً.'),
      );
    }

    final markers = <Marker>{
      if (validClient != null)
        Marker(
          markerId: const MarkerId('client'),
          position: validClient,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'موقع العميل'),
        ),
      if (validOutlet != null)
        Marker(
          markerId: const MarkerId('outlet'),
          position: validOutlet,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'موقع المنفذ'),
        ),
    };

    final polylines = <Polyline>{
      if (validClient != null && validOutlet != null)
        Polyline(
          polylineId: const PolylineId('route_line'),
          points: [validClient, validOutlet],
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
                FirebaseCrashlytics.instance.log('map_widget_created');
                _controller = c;
                _fitBounds();
              },
            ),
    );
  }

  Future<void> _fitBounds() async {
    if (_controller == null) return;

    final client = _safeLatLng(widget.client);
    final outlet = _safeLatLng(widget.outlet);

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

  LatLng? _safeLatLng(LatLng? point) {
    if (point == null) return null;
    if (point.latitude.isNaN || point.longitude.isNaN) return null;
    if (point.latitude.isInfinite || point.longitude.isInfinite) return null;
    if (point.latitude < -90 || point.latitude > 90) return null;
    if (point.longitude < -180 || point.longitude > 180) return null;
    return point;
  }
}

class _PartyInfoCard extends StatelessWidget {
  const _PartyInfoCard({
    required this.users,
    required this.clientId,
    required this.outletId,
    required this.role,
    required this.ratingsService,
  });

  final CollectionReference<Map<String, dynamic>> users;
  final String clientId;
  final String outletId;
  final String role;
  final RatingsService ratingsService;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadProfiles(),
      builder: (context, snap) {
        final list = snap.data ?? const <Map<String, dynamic>>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('أطراف الرحلة', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ...list.map((p) {
                final name = (p['fullName'] ?? '').toString();
                final r = (p['role'] ?? '').toString();
                final id = (p['uid'] ?? '').toString();
                final outletName = (p['outletName'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${r == 'outlet' ? 'منفذ' : 'عميل'}: ${name.isNotEmpty ? name : id}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (outletName.isNotEmpty) Text('($outletName)', style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              FutureBuilder<double?>(
                future: ratingsService.getAverageRatingForUser(role == 'client' ? outletId : clientId),
                builder: (context, s) {
                  final text = s.data == null ? 'بدون تقييم' : '⭐ ${s.data!.toStringAsFixed(1)}';
                  return Text('متوسط التقييم: $text', style: const TextStyle(color: Colors.black54));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadProfiles() async {
    final ids = <String>{};
    if (clientId.isNotEmpty) ids.add(clientId);
    if (outletId.isNotEmpty) ids.add(outletId);
    final list = <Map<String, dynamic>>[];
    for (final id in ids) {
      final doc = await users.doc(id).get();
      final data = doc.data();
      if (data != null) {
        list.add({...data, 'uid': id});
      }
    }
    return list;
  }
}