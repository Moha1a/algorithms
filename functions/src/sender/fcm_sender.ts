import * as admin from 'firebase-admin';

import {deleteDeviceById, getActiveDeviceTokens} from './token_repository';
import {logInfo, logWarn, logError} from '../utils/logger';

export async function sendNotificationJob(job: FirebaseFirestore.DocumentData): Promise<void> {
  const recipientUid = String(job.recipientUid || '').trim();
  if (!recipientUid) {
    logWarn('FCM sender skipped: recipientUid missing', {job});
    return;
  }

  const devices = await getActiveDeviceTokens(recipientUid);
  if (!devices.length) {
    logInfo('FCM sender skipped: no active devices', {
      recipientUid,
      bookingId: job.bookingId || '',
    });
    return;
  }

  const tokens = devices.map((d) => d.token);
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: String(job.notification?.title || 'إشعار جديد'),
      body: String(job.notification?.body || ''),
    },
    data: {
      type: String(job.data?.type || ''),
      bookingId: String(job.data?.bookingId || ''),
      screen: String(job.data?.screen || ''),
      actorId: String(job.data?.actorId || ''),
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'high_importance_channel',
      },
    },
    apns: {
      payload: {
        aps: {sound: 'default'},
      },
    },
  });

  const cleanups: Array<Promise<void>> = [];

  response.responses.forEach((r, idx) => {
    if (r.success) return;

    const code = r.error?.code || 'unknown';
    const message = r.error?.message || 'unknown';

    logError('FCM token send failed', {
      bookingId: String(job.bookingId || ''),
      recipientUid,
      tokenIndex: idx,
      // token logging for diagnosis (masked to avoid dumping full token)
      tokenPreview: `${tokens[idx]?.slice(0, 12) || ''}...`,
      errorCode: code,
      errorMessage: message,
      fullError: String(r.error || ''),
    });

    if (code.includes('registration-token-not-registered') || code.includes('invalid-registration-token')) {
      cleanups.push(deleteDeviceById(recipientUid, devices[idx].deviceId));
    }
  });

  if (cleanups.length) await Promise.all(cleanups);

  logInfo('FCM sender finished', {
    recipientUid,
    bookingId: String(job.bookingId || ''),
    type: String(job.type || ''),
    successCount: response.successCount,
    failureCount: response.failureCount,
    cleanedInvalidDevices: cleanups.length,
  });
}
