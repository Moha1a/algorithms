import * as admin from 'firebase-admin';
import {onRequest} from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';

import {getActiveDeviceTokens} from '../sender/token_repository';

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

async function tokensForUser(uid: string): Promise<string[]> {
  const devices = await getActiveDeviceTokens(uid);
  return Array.from(new Set(devices.map((d) => d.token).filter((t) => t)));
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
      recipientUid,
      type,
      bookingId,
      actorId,
      eventCategory:
        type === 'price_proposal' || type === 'price_proposal_updated'
          ? 'proposal'
          : type === 'order_accepted'
            ? 'acceptance'
            : type === 'new_message'
              ? 'message'
              : type.startsWith('admin_')
                ? 'admin'
                : 'other',
    });

    const tokens = await tokensForUser(recipientUid);
    const tokensCount = tokens.length;

    if (!tokensCount) {
      logger.warn('sendPushNotification skipped: no tokens', {
        recipientUid,
        tokensCount: 0,
        type,
        bookingId,
      });
      res.status(200).json({ok: true, skipped: 'no_tokens'});
      return;
    }

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
        payload: {aps: {sound: 'default'}},
      },
    });

    const failures = result.responses
      .map((r, i) => ({r, i}))
      .filter((x) => !x.r.success)
      .map((x) => ({
        tokenIndex: x.i,
        errorCode: String(x.r.error?.code || 'unknown'),
        errorMessage: String(x.r.error?.message || 'unknown'),
      }));

    logger.info('sendPushNotification result', {
      recipientUid,
      tokensCount,
      successCount: result.successCount,
      failureCount: result.failureCount,
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
      failures,
    });
  } catch (error) {
    const err = error as Error;
    logger.error('sendPushNotification failed', {
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
