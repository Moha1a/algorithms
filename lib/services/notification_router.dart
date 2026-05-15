import 'package:flutter/material.dart';

import '../screens/notification_debug_screen.dart';

class NotificationRouter {
  NotificationRouter._();

  static void routeFromPayload({
    required GlobalKey<NavigatorState> navigatorKey,
    required Map<String, dynamic> payload,
  }) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final type = (payload['type'] ?? '').toString();
    final bookingId = (payload['bookingId'] ?? '').toString();

    // Safe routing: if target screen is unavailable, always fallback.
    switch (type) {
      case 'booking_accepted':
      case 'booking_direct_accepted':
      case 'booking_price_proposed':
      case 'chat_message_created':
      case 'booking_auto_cancelled_11h':
        nav.push(
          MaterialPageRoute(
            builder: (_) => NotificationDebugScreen(
              payload: {
                ...payload,
                'resolvedType': type,
                'bookingId': bookingId,
              },
            ),
          ),
        );
        return;
      default:
        nav.push(MaterialPageRoute(builder: (_) => NotificationDebugScreen(payload: payload)));
    }
  }
}
