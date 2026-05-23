import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'bookings_screen.dart';
import 'map_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

class HomeShellScreen extends StatefulWidget {
  const HomeShellScreen({super.key, required this.profile, this.initialIndex = 0});

  final Map<String, dynamic> profile;
  final int initialIndex;
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  static void requestTab(int index) {
    tabRequest.value = index;
  }

  @override
  State<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends State<HomeShellScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    HomeShellScreen.tabRequest.addListener(_onExternalTabRequest);
  }

  @override
  void dispose() {
    HomeShellScreen.tabRequest.removeListener(_onExternalTabRequest);
    super.dispose();
  }

  void _onExternalTabRequest() {
    final target = HomeShellScreen.tabRequest.value;
    if (target == null || !mounted) return;
    setState(() => _index = target);
    HomeShellScreen.tabRequest.value = null;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _pendingRequestsStream(String requestOwnerRole) {
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('status', isEqualTo: 'pending')
        .where('requestOwnerRole', isEqualTo: requestOwnerRole)
        .snapshots();
  }

  int _pendingCount(AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot, String uid) {
    final docs = snapshot.data?.docs ?? const [];
    return docs.where((doc) {
      final data = doc.data();
      final ownerId = (data['createdById'] ?? data['clientId'] ?? '').toString();
      return ownerId != uid;
    }).length;
  }

  Widget _buildHomeScaffold({
    required List<Widget> pages,
    required List<NavigationDestination> destinations,
  }) {
    if (_index >= pages.length) _index = 0;

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: destinations,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = (widget.profile['role'] ?? '').toString();
    final isOutlet = role == 'outlet';
    final uid = (widget.profile['uid'] ?? '').toString();

    final pages = isOutlet
        ? [
            BookingsScreen(
              profile: widget.profile,
              title: 'الطلبات',
              forOwnRequests: true,
              showRequestOwnerTabs: false,
              showCreateButton: true,
            ),
            BookingsScreen(
              profile: widget.profile,
              title: 'طلبات العملاء',
              lockedOutletTab: OutletRequestTab.clientRequests,
              showRequestOwnerTabs: false,
              showCreateButton: false,
              showHistoryTabs: false,
            ),
            BookingsScreen(
              profile: widget.profile,
              title: 'طلبات المنافذ',
              lockedOutletTab: OutletRequestTab.outletRequests,
              showRequestOwnerTabs: false,
              showCreateButton: false,
              showHistoryTabs: false,
            ),
            MapScreen(profile: widget.profile),
            NotificationsScreen(profile: widget.profile),
            ProfileScreen(profile: widget.profile),
          ]
        : [
            BookingsScreen(
              profile: widget.profile,
              title: 'الطلبات',
              forOwnRequests: true,
              showRequestOwnerTabs: false,
              showCreateButton: true,
            ),
            MapScreen(profile: widget.profile),
            NotificationsScreen(profile: widget.profile),
            ProfileScreen(profile: widget.profile),
          ];

    final mapIndex = isOutlet ? 3 : 1;

    final activeMapStream = FirebaseFirestore.instance
        .collection('bookings')
        .where(isOutlet ? 'outletId' : 'clientId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'in_progress']).snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: activeMapStream,
      builder: (context, snap) {
        final hasActiveMap = (snap.data?.docs ?? const []).isNotEmpty;

        if (!isOutlet) {
          return _buildHomeScaffold(
            pages: pages,
            destinations: [
              const NavigationDestination(icon: Icon(Icons.list_alt_rounded), label: 'الطلبات'),
              NavigationDestination(icon: _MapNavIcon(active: hasActiveMap && _index != mapIndex), label: 'الخريطة'),
              const NavigationDestination(icon: Icon(Icons.notifications_active_rounded), label: 'الإشعارات'),
              const NavigationDestination(icon: Icon(Icons.person_rounded), label: 'الحساب'),
            ],
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _pendingRequestsStream('client'),
          builder: (context, clientRequestsSnap) {
            final clientPendingCount = _pendingCount(clientRequestsSnap, uid);
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _pendingRequestsStream('outlet'),
              builder: (context, outletRequestsSnap) {
                final outletPendingCount = _pendingCount(outletRequestsSnap, uid);
                return _buildHomeScaffold(
                  pages: pages,
                  destinations: [
                    const NavigationDestination(icon: Icon(Icons.list_alt_rounded), label: 'الطلبات'),
                    NavigationDestination(
                      icon: _BadgeNavIcon(icon: Icons.groups_rounded, count: clientPendingCount),
                      label: 'العملاء',
                    ),
                    NavigationDestination(
                      icon: _BadgeNavIcon(icon: Icons.store_mall_directory_rounded, count: outletPendingCount),
                      label: 'المنافذ',
                    ),
                    NavigationDestination(icon: _MapNavIcon(active: hasActiveMap && _index != mapIndex), label: 'الخريطة'),
                    const NavigationDestination(icon: Icon(Icons.notifications_active_rounded), label: 'الإشعارات'),
                    const NavigationDestination(icon: Icon(Icons.person_rounded), label: 'الحساب'),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _BadgeNavIcon extends StatelessWidget {
  const _BadgeNavIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          PositionedDirectional(
            top: -8,
            end: -12,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MapNavIcon extends StatefulWidget {
  const _MapNavIcon({required this.active});

  final bool active;

  @override
  State<_MapNavIcon> createState() => _MapNavIconState();
}

class _MapNavIconState extends State<_MapNavIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void didUpdateWidget(covariant _MapNavIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const Icon(Icons.map_rounded);
    return FadeTransition(
      opacity: _controller,
      child: const Icon(Icons.map_rounded, color: Color(0xFFF59E0B)),
    );
  }
}
