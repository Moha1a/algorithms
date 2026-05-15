import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class PushSenderService {
  PushSenderService._();
  static final PushSenderService instance = PushSenderService._();

  static const String _configuredEndpoint =
      String.fromEnvironment('SEND_PUSH_ENDPOINT', defaultValue: '');

  String _resolveEndpoint() {
    if (_configuredEndpoint.trim().isNotEmpty) {
      return _configuredEndpoint.trim();
    }
    final projectId = Firebase.app().options.projectId.trim();
    return 'https://us-central1-$projectId.cloudfunctions.net/sendPushNotification';
  }

  Future<void> sendPush({
    required String recipientUid,
    required String title,
    required String body,
    required String type,
    String bookingId = '',
    String actorId = '',
    String dedupeKey = '',
  }) async {
    if (recipientUid.trim().isEmpty) return;

    final client = HttpClient();
    final crashlytics = FirebaseCrashlytics.instance;
    try {
      final endpoint = _resolveEndpoint();
      crashlytics.setCustomKey('push_event_type', type);
      crashlytics.setCustomKey('push_recipient_uid', recipientUid);
      crashlytics.setCustomKey('push_send_success', false);
      crashlytics.setCustomKey('push_send_failure', false);
      debugPrint('[PushSenderService] send type=$type to=$recipientUid bookingId=$bookingId endpoint=$endpoint');
      final req = await client.postUrl(Uri.parse(endpoint));
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'recipientUid': recipientUid,
          'title': title,
          'body': body,
          'type': type,
          'bookingId': bookingId,
          'actorId': actorId,
          'dedupeKey': dedupeKey.isNotEmpty ? dedupeKey : '$type:$bookingId:$recipientUid:$actorId',
        }),
      );

      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('Push send failed with status ${res.statusCode}: $text', uri: Uri.parse(endpoint));
      }
      crashlytics.setCustomKey('push_send_success', true);
      debugPrint('[PushSenderService] send success type=$type to=$recipientUid status=${res.statusCode}');
    } catch (e) {
      debugPrint('[PushSenderService] send exception: $e');
      crashlytics.setCustomKey('push_send_failure', true);
      crashlytics.recordError(e, StackTrace.current, fatal: false);
      rethrow;
    } finally {
      client.close();
    }
  }
}
