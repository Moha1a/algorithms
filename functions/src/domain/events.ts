import * as admin from 'firebase-admin';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';

import {buildNotificationJob, NotificationJobType} from './job_builder';
import {runIdempotent} from '../utils/idempotency';
import {logInfo, logWarn} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

type BookingEvent = {
  type?: NotificationJobType;
  bookingId?: string;
  clientId?: string;
  outletId?: string;
  acceptedOutletId?: string;
  actorId?: string;
  price?: string | number;
  createdAt?: unknown;
};

function val(v: unknown): string {
  return String(v ?? '').trim();
}

function resolveRecipient(event: BookingEvent): string {
  const type = val(event.type) as NotificationJobType;
  if (type === 'booking_price_proposed') {
    return val(event.clientId);
  }
  if (type === 'booking_accepted') {
    return val(event.acceptedOutletId) || val(event.outletId);
  }
  if (type === 'chat_message_created') {
    const actor = val(event.actorId);
    const client = val(event.clientId);
    const outlet = val(event.outletId) || val(event.acceptedOutletId);
    if (actor && actor === client) return outlet;
    if (actor && actor === outlet) return client;
    // fallback if actor unknown
    return client || outlet;
  }
  return '';
}

function buildNotificationText(type: NotificationJobType, event: BookingEvent): {title: string; body: string; screen: string} {
  switch (type) {
    case 'booking_price_proposed':
      return {
        title: 'عرض سعر جديد 💰',
        body: `تم إضافة عرض سعر${val(event.price) ? ` بقيمة ${val(event.price)}` : ''} على الطلب.`,
        screen: 'booking_proposals',
      };
    case 'booking_accepted':
      return {
        title: 'تم قبولك كمنفذ ✅',
        body: 'تم اختيارك لتنفيذ الطلب.',
        screen: 'booking_details',
      };
    case 'chat_message_created':
      return {
        title: 'رسالة جديدة 💬',
        body: 'لديك رسالة جديدة في المحادثة.',
        screen: 'chat',
      };
    default:
      return {
        title: 'إشعار جديد',
        body: 'لديك تحديث جديد.',
        screen: 'notifications',
      };
  }
}

export const onBookingEventCreated = onDocumentCreated(
  {document: 'bookingEvents/{eventId}', region: 'us-central1'},
  async (snapshotEvent) => {
    const eventId = val(snapshotEvent.params.eventId);
    const event = (snapshotEvent.data?.data() ?? {}) as BookingEvent;

    const type = val(event.type) as NotificationJobType;
    const bookingId = val(event.bookingId);
    const actorId = val(event.actorId);

    logInfo('bookingEvents trigger fired', {
      eventId,
      type,
      bookingId,
    });

    if (!eventId || !bookingId || !type) {
      logWarn('bookingEvents skipped: missing required fields', {eventId, type, bookingId});
      return;
    }

    if (!['booking_price_proposed', 'booking_accepted', 'chat_message_created'].includes(type)) {
      logWarn('bookingEvents skipped: unsupported type', {eventId, type});
      return;
    }

    const recipientUid = resolveRecipient(event);
    if (!recipientUid) {
      logWarn('bookingEvents skipped: recipient not resolved', {
        eventId,
        type,
        bookingId,
        clientId: val(event.clientId),
        outletId: val(event.outletId),
        acceptedOutletId: val(event.acceptedOutletId),
        actorId,
      });
      return;
    }

    const dedupeKey = `event_pipeline__${eventId}__${type}`;

    await runIdempotent({
      dedupeKey,
      run: async () => {
        const txt = buildNotificationText(type, event);
        const job = buildNotificationJob({
          type,
          bookingId,
          recipientUid,
          actorId,
          dedupeKey: `job__${eventId}`,
          sourceEventId: eventId,
          screen: txt.screen,
          notification: {
            title: txt.title,
            body: txt.body,
          },
          data: {},
        });

        await getDb().collection('notificationJobs').add(job);

        logInfo('notificationJobs created from bookingEvents', {
          eventId,
          type,
          bookingId,
          recipientUid,
        });
      },
    });
  }
);
