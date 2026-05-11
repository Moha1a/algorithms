import * as admin from 'firebase-admin';
import {onRequest} from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';

import {deleteDeviceById, getActiveDeviceTokens} from '../sender/token_repository';

type PushPayload = {
  recipientUid?: string;
  title?: string;
  body?: string;
  type?: string;
  bookingId?: string;
  actorId?: string;
};

function applyCors(req: {headers: Record<string, unknown>}, res: {set: (name: string, value: string) => void}): void {
  const origin = String(req.headers.origin || '*');
  res.set('Access-Control-Allow-Origin', origin);
  res.set('Vary', 'Origin');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Max-Age', '3600');
}

function isInvalidTokenError(code: string): boolean {
  return code.includes('registration-token-not-registered') || code.includes('invalid-registration-token');
}

export const sendPushNotification = onRequest({region: 'us-central1', invoker: 'public'}, async (req, res) => {
  applyCors(req, res);
  logger.info('sendPushNotification request arrived', {
    method: req.method,
    body: req.body || {},
  });

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ok: false, error: 'Method not allowed'});
    return;
  }

  try {
    const payload = (req.body || {}) as PushPayload;
    const recipientUid = String(payload.recipientUid || '').trim();
    const title = String(payload.title || '').trim();
    const body = String(payload.body || '').trim();
    const type = String(payload.type || '').trim();
    const bookingId = String(payload.bookingId || '').trim();
    const actorId = String(payload.actorId || '').trim();
    if (!recipientUid || !title || !body) {
      res.status(400).json({ok: false, error: 'Missing recipientUid/title/body'});
      return;
    }

    logger.info('sendPushNotification parsed payload', {
      push_recipient_uid: recipientUid,
      push_event_type: type,
      bookingId,
      actorId,
      eventCategory:
        type === 'price_proposal' || type === 'price_proposal_updated'
          ? 'proposal'
          : type === 'order_accepted' || type === 'booking_accepted'
            ? 'acceptance'
            : type === 'new_message'
              ? 'message'
              : type.startsWith('admin_')
                ? 'admin'
                : 'other',
    });

    const loadedDevices = await getActiveDeviceTokens(recipientUid);
    const seenTokens = new Set<string>();
    const devices = loadedDevices.filter((device) => {
      if (!device.token || seenTokens.has(device.token)) return false;
      seenTokens.add(device.token);
      return true;
    });
    const tokens = devices.map((device) => device.token);
    const tokensCount = tokens.length;

    logger.info('sendPushNotification tokens found', {
      push_recipient_uid: recipientUid,
      push_event_type: type,
      push_tokens_found: tokensCount,
      bookingId,
    });

    if (!tokensCount) {
      logger.warn('sendPushNotification skipped: no tokens', {
        push_recipient_uid: recipientUid,
        push_tokens_found: 0,
        type,
        bookingId,
      });
      res.status(200).json({ok: true, skipped: 'no_tokens'});
      return;
    }

    devices.forEach((device, idx) => {
      logger.info('sendPushNotification token send attempt', {
        push_recipient_uid: recipientUid,
        push_event_type: type,
        tokenIndex: idx,
        deviceId: device.deviceId,
        platform: device.platform || '',
        tokenPreview: `${device.token.slice(0, 12)}...`,
      });
    });

    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {title, body},
      data: {type, bookingId, actorId},
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
    const failures = result.responses
      .map((r, i) => ({r, i}))
      .filter((x) => !x.r.success)
      .map((x) => {
        const errorCode = String(x.r.error?.code || 'unknown');
        if (isInvalidTokenError(errorCode)) {
          cleanups.push(deleteDeviceById(recipientUid, devices[x.i].deviceId));
        }
        logger.error('sendPushNotification token send failed', {
          push_recipient_uid: recipientUid,
          push_event_type: type,
          push_send_failure: true,
          fcm_error_code: errorCode,
          tokenIndex: x.i,
          deviceId: devices[x.i]?.deviceId || '',
          tokenPreview: `${tokens[x.i]?.slice(0, 12) || ''}...`,
          errorMessage: String(x.r.error?.message || 'unknown'),
        });
        return {
          tokenIndex: x.i,
          errorCode,
          errorMessage: String(x.r.error?.message || 'unknown'),
        };
      });

    result.responses.forEach((r, i) => {
      if (!r.success) return;
      logger.info('sendPushNotification token send success', {
        push_recipient_uid: recipientUid,
        push_event_type: type,
        push_send_success: true,
        tokenIndex: i,
        deviceId: devices[i]?.deviceId || '',
        messageId: r.messageId || '',
      });
    });

    if (cleanups.length) await Promise.all(cleanups);

    logger.info('sendPushNotification result', {
      push_recipient_uid: recipientUid,
      push_event_type: type,
      tokensCount,
      successCount: result.successCount,
      failureCount: result.failureCount,
      cleanedInvalidDevices: cleanups.length,
      failures,
      type,
      bookingId,
      actorId,
    });

    res.status(200).json({
      ok: true,
      recipientUid,
      tokensCount,
      successCount: result.successCount,
      failureCount: result.failureCount,
      cleanedInvalidDevices: cleanups.length,
      failures,
    });
  } catch (error) {
    const err = error as Error;
    logger.error('sendPushNotification failed', {
      fcm_error_code: (error as {code?: string})?.code || 'unknown',
      errorCode: (error as {code?: string})?.code || 'unknown',
      errorMessage: err?.message || String(error),
    });
    res.status(500).json({
      ok: false,
      errorCode: (error as {code?: string})?.code || 'unknown',
      errorMessage: err?.message || String(error),
    });
  }
});
