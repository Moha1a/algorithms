import * as admin from 'firebase-admin';

import {deleteDeviceById, getActiveDeviceTokens} from './token_repository';
import {logInfo, logWarn, logError} from '../utils/logger';

function isInvalidTokenError(code: string): boolean {
  return code.includes('registration-token-not-registered') || code.includes('invalid-registration-token');
}

export async function sendNotificationJob(job: FirebaseFirestore.DocumentData): Promise<void> {
  const recipientUid = String(job.recipientUid || '').trim();
  if (!recipientUid) {
    logWarn('FCM sender skipped: recipientUid missing', {job});
    return;
  }

  const devices = await getActiveDeviceTokens(recipientUid);
  const title = String(job.notification?.title || 'إشعار جديد');
  const body = String(job.notification?.body || '');
  const eventType = String(job.data?.type || job.type || '');
  const bookingId = String(job.data?.bookingId || job.bookingId || '');
  const actorId = String(job.data?.actorId || job.actorId || '');
  const screen = String(job.data?.screen || job.screen || '');

  if (!devices.length) {
    logInfo('FCM sender skipped: no active devices', {
      push_recipient_uid: recipientUid,
      push_event_type: eventType,
      push_tokens_found: 0,
      bookingId,
    });
    return;
  }

  logInfo('FCM sender tokens found', {
    push_recipient_uid: recipientUid,
    push_event_type: eventType,
    push_tokens_found: devices.length,
    bookingId,
  });

  devices.forEach((device, idx) => {
    logInfo('FCM token send attempt', {
      push_recipient_uid: recipientUid,
      push_event_type: eventType,
      tokenIndex: idx,
      deviceId: device.deviceId,
      platform: device.platform || '',
      tokenPreview: `${device.token.slice(0, 12)}...`,
    });
  });

  const tokens = devices.map((d) => d.token);
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {title, body},
    data: {
      type: eventType,
      bookingId,
      screen,
      actorId,
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'high_importance_channel',
        sound: 'default',
      },
    },
    apns: {
      headers: {
        'apns-push-type': 'alert',
        'apns-priority': '10',
      },
      payload: {
        aps: {
          alert: {title, body},
          sound: 'default',
        },
      },
    },
  });

  const cleanups: Array<Promise<void>> = [];

  response.responses.forEach((r, idx) => {
    if (r.success) {
      logInfo('FCM token send success', {
        push_recipient_uid: recipientUid,
        push_event_type: eventType,
        push_send_success: true,
        tokenIndex: idx,
        deviceId: devices[idx]?.deviceId || '',
        messageId: r.messageId || '',
      });
      return;
    }

    const code = r.error?.code || 'unknown';
    const message = r.error?.message || 'unknown';

    logError('FCM token send failed', {
      bookingId,
      recipientUid,
      push_recipient_uid: recipientUid,
      push_event_type: eventType,
      push_send_failure: true,
      fcm_error_code: code,
      tokenIndex: idx,
      tokenPreview: `${tokens[idx]?.slice(0, 12) || ''}...`,
      errorCode: code,
      errorMessage: message,
      fullError: String(r.error || ''),
    });

    if (isInvalidTokenError(code)) {
      cleanups.push(deleteDeviceById(recipientUid, devices[idx].deviceId));
    }
  });

  if (cleanups.length) await Promise.all(cleanups);

  logInfo('FCM sender finished', {
    recipientUid,
    push_recipient_uid: recipientUid,
    push_event_type: eventType,
    bookingId,
    type: String(job.type || ''),
    push_send_success: response.successCount > 0,
    push_send_failure: response.failureCount > 0,
    successCount: response.successCount,
    failureCount: response.failureCount,
    cleanedInvalidDevices: cleanups.length,
  });
}
