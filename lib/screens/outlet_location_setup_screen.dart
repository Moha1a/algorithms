import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_guard_service.dart';
import 'home_shell_screen.dart';

class OutletLocationSetupScreen extends StatefulWidget {
  const OutletLocationSetupScreen({
    super.key,
    required this.profile,
    this.popOnSave = false,
  });

  final Map<String, dynamic> profile;
  final bool popOnSave;

  @override
  State<OutletLocationSetupScreen> createState() =>
      _OutletLocationSetupScreenState();
}

class _OutletLocationSetupScreenState extends State<OutletLocationSetupScreen> {
  static const LatLng _basra = LatLng(30.5085, 47.7835);

  late LatLng _selected = LatLng(
    _toDouble(widget.profile['fixedLat'] ??
            widget.profile['currentLat'] ??
            widget.profile['lat']) ??
        _basra.latitude,
    _toDouble(widget.profile['fixedLng'] ??
            widget.profile['currentLng'] ??
            widget.profile['lng']) ??
        _basra.longitude,
  );
  late final TextEditingController _regionController = TextEditingController(
    text: (widget.profile['region'] ??
            widget.profile['outletRegion'] ??
            widget.profile['governorate'] ??
            '')
        .toString(),
  );
  bool _requestingLocation = true;
  bool _saving = false;
  GoogleMapController? _controller;

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestLocation());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    final position = await LocationGuardService.instance.requireCurrentLocation(
      context,
      title: 'مشاركة موقع المنفذ مطلوبة',
      message: 'يجب تحديد موقع المنفذ على الخريطة قبل الدخول للبرنامج.',
      crashlyticsKey: 'outlet_fixed_location_required',
      timeLimit: const Duration(seconds: 10),
    );
    if (!mounted) return;
    setState(() {
      _requestingLocation = false;
      if (position != null) {
        _selected = LatLng(position.latitude, position.longitude);
      }
    });
    if (position != null) {
      await _controller
          ?.animateCamera(CameraUpdate.newLatLngZoom(_selected, 16));
    }
  }

  Future<void> _save() async {
    if (_regionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل المنطقة قبل المتابعة.')),
      );
      return;
    }
    final uid = (widget.profile['uid'] ?? '').toString();
    if (uid.isEmpty) return;
    setState(() => _saving = true);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fixedLat': _selected.latitude,
      'fixedLng': _selected.longitude,
      'lat': _selected.latitude,
      'lng': _selected.longitude,
      'region': _regionController.text.trim(),
      'outletRegion': _regionController.text.trim(),
      'fixedLocationConfigured': true,
      'fixedLocationUpdatedAt': FieldValue.serverTimestamp(),
      'fixedLocationUpdatedBy': FirebaseAuth.instance.currentUser?.uid ?? uid,
    }, SetOptions(merge: true));
    if (!mounted) return;
    final nextProfile = {
      ...widget.profile,
      'fixedLat': _selected.latitude,
      'fixedLng': _selected.longitude,
      'region': _regionController.text.trim(),
      'outletRegion': _regionController.text.trim(),
      'fixedLocationConfigured': true,
    };
    setState(() => _saving = false);
    if (widget.popOnSave) {
      Navigator.of(context).pop(nextProfile);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeShellScreen(profile: nextProfile)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحديد موقع المنفذ')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _regionController,
              decoration: const InputDecoration(
                labelText: 'المنطقة',
                prefixIcon: Icon(Icons.location_city_rounded),
              ),
            ),
          ),
          Expanded(
            child: _requestingLocation
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    initialCameraPosition:
                        CameraPosition(target: _selected, zoom: 13),
                    onMapCreated: (controller) => _controller = controller,
                    markers: {
                      Marker(
                        markerId: const MarkerId('outlet_fixed_location'),
                        position: _selected,
                        draggable: true,
                        infoWindow: const InfoWindow(title: 'موقع المنفذ'),
                        onDragEnd: (value) => setState(() => _selected = value),
                      ),
                    },
                    onTap: (value) => setState(() => _selected = value),
                    myLocationButtonEnabled: true,
                    myLocationEnabled: true,
                    zoomControlsEnabled: true,
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                height: 50,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving || _requestingLocation ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('حفظ الموقع والمنطقة'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
