import * as admin from 'firebase-admin';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';

import {buildNotificationJob} from './job_builder';
import {runIdempotent} from '../utils/idempotency';
import {logInfo, logWarn} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function clean(value: unknown): string {
  return String(value ?? '').trim();
}

function numberValue(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const parsed = Number(String(value ?? '').replace(/,/g, '').trim());
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatMoney(value: unknown): string {
  const amount = Math.round(numberValue(value));
  return amount.toLocaleString('en-US');
}

function offerTypeLabel(type: string): string {
  switch (type) {
    case 'deposit':
      return 'شحن';
    case 'discharge':
      return 'تفريغ';
    case 'withdraw':
    default:
      return 'سحب';
  }
}

export const onOutletOfferCreatedNotifyClients = onDocumentCreated(
  {document: 'outlet_offers/{offerId}', region: 'us-central1'},
  async (event) => {
    const offerId = clean(event.params.offerId);
    const offer = event.data?.data() ?? {};
    const outletId = clean(offer.outletId);
    const status = clean(offer.status) || 'active';
    const type = clean(offer.type) || 'withdraw';

    if (!offerId || !outletId) {
      logWarn('outlet offer notification skipped: missing offerId/outletId', {
        offerId,
        outletId,
      });
      return;
    }

    if (status !== 'active') {
      logInfo('outlet offer notification skipped: offer not active', {
        offerId,
        outletId,
        status,
      });
      return;
    }

    if (type === 'discharge') {
      logInfo('outlet offer notification skipped: discharge offer is outlet-only', {
        offerId,
        outletId,
        type,
      });
      return;
    }

    const clientsSnap = await getDb()
      .collection('users')
      .where('role', '==', 'client')
      .get();
    const clientUids = clientsSnap.docs
      .map((doc) => doc.id)
      .filter((uid) => uid.length > 0 && uid !== outletId);

    if (!clientUids.length) {
      logWarn('outlet offer notification skipped: no clients found', {
        offerId,
        outletId,
        type,
      });
      return;
    }

    const typeLabel = offerTypeLabel(type);
    const priceText = formatMoney(offer.pricePerMillion);
    const bankName = clean(offer.bankName);
    const title = 'عرض جديد من منفذ';
    const body = bankName
      ? `${typeLabel} - كل مليون بـ ${priceText} دينار (${bankName}).`
      : `${typeLabel} - كل مليون بـ ${priceText} دينار.`;

    await Promise.all(
      clientUids.map(async (clientUid) => {
        const dedupeKey = `outlet_offer_created:${offerId}:${clientUid}`;

        await runIdempotent({
          dedupeKey,
          metadata: {
            push_event_type: 'outlet_offer_created',
            push_dedupe_key: dedupeKey,
            push_actor_uid: outletId,
            push_recipient_uid: clientUid,
            outlet_offer_id: offerId,
          },
          run: async () => {
            await getDb().collection('notifications').add({
              toUserId: clientUid,
              type: 'outlet_offer_created',
              bookingId: '',
              outletOfferId: offerId,
              title,
              body,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            const job = buildNotificationJob({
              type: 'outlet_offer_created',
              recipientUid: clientUid,
              bookingId: '',
              actorId: outletId,
              dedupeKey,
              sourceEventId: `outlet_offer_${offerId}`,
              screen: 'outlet_offers',
              notification: {title, body},
              data: {
                dedupeKey,
                outletOfferId: offerId,
                offerType: type,
              },
            });

            await getDb().collection('notificationJobs').add(job);

            logInfo('outlet offer notification job created', {
              push_event_type: 'outlet_offer_created',
              push_dedupe_key: dedupeKey,
              push_actor_uid: outletId,
              push_recipient_uid: clientUid,
              outlet_offer_id: offerId,
              offer_type: type,
            });
          },
        });
      })
    );

    logInfo('outlet offer notifications queued for clients', {
      push_event_type: 'outlet_offer_created',
      outlet_offer_id: offerId,
      outletId,
      clientsCount: clientUids.length,
      offer_type: type,
    });
  }
);
