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
  proposalId?: string;
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
  if (type === 'booking_direct_accepted') {
    return val(event.clientId);
  }
  if (type === 'chat_message_created') {
    const actor = val(event.actorId);
    const client = val(event.clientId);
    const outlet = val(event.outletId) || val(event.acceptedOutletId);
    if (actor && actor === client) return outlet;
    if (actor && actor === outlet) return client;
    return client || outlet;
  }
  return '';
}

function buildNotificationText(type: NotificationJobType, event: BookingEvent): {title: string; body: string; screen: string} {
  switch (type) {
    case 'booking_price_proposed':
      return {
        title: 'وصل عرض سعر جديد',
        body: val(event.price).length > 0
            ? `أرسل المنفذ عرض سعر جديد بقيمة ${val(event.price)}.`
            : 'أرسل المنفذ عرض سعر جديد لطلبك.',
        screen: 'booking_proposals',
      };
    case 'booking_accepted':
      return {
        title: 'تم قبول عرضك',
        body: 'قام صاحب الطلب بقبول عرض السعر الخاص بك.',
        screen: 'booking_details',
      };
    case 'booking_direct_accepted':
      return {
        title: 'تم قبول طلبك',
        body: 'وافق منفذ الراشد على طلبك مباشرة.',
        screen: 'booking_details',
      };
    case 'chat_message_created':
      return {
        title: 'رسالة جديدة',
        body: 'لديك رسالة جديدة بخصوص الطلب.',
        screen: 'chat',
      };
    case 'booking_auto_cancelled_11h':
    case 'booking_auto_cancelled_14h':
      return {
        title: 'تم إلغاء الطلب تلقائياً',
        body: 'تم إلغاء الطلب لأنه لم يكتمل خلال 14 ساعة.',
        screen: 'booking_details',
      };
    default:
      return {
        title: 'إشعار جديد',
        body: 'لديك تحديث جديد.',
        screen: 'notifications',
      };
  }
}

function buildEventDedupeKey(eventId: string, event: BookingEvent, recipientUid: string): string {
  const type = val(event.type) as NotificationJobType;
  const bookingId = val(event.bookingId);
  const actorId = val(event.actorId);
  const acceptedProposalProviderUid = val(event.acceptedOutletId) || val(event.outletId);

  if (type === 'booking_price_proposed') {
    return `proposal_created:${bookingId}:${val(event.proposalId) || val(event.outletId) || actorId}:${recipientUid}:${val(event.price)}`;
  }
  if (type === 'booking_accepted') {
    return `proposal_accepted:${bookingId}:${acceptedProposalProviderUid}:${recipientUid}`;
  }
  if (type === 'booking_direct_accepted') {
    return `booking_direct_accepted:${bookingId}:${recipientUid}`;
  }
  if (type === 'chat_message_created') {
    return `message_created:${bookingId}:${eventId}:${recipientUid}`;
  }
  return `event_pipeline:${eventId}:${type}:${recipientUid}`;
}

export const onBookingEventCreated = onDocumentCreated(
  {document: 'bookingEvents/{eventId}', region: 'us-central1'},
  async (snapshotEvent) => {
    const eventId = val(snapshotEvent.params.eventId);
    const event = (snapshotEvent.data?.data() ?? {}) as BookingEvent;

    const type = val(event.type) as NotificationJobType;
    const bookingId = val(event.bookingId);
    const actorId = val(event.actorId);
    const recipientUid = resolveRecipient(event);
    const acceptedProposalProviderUid = val(event.acceptedOutletId) || val(event.outletId);

    logInfo('bookingEvents trigger fired', {
      eventId,
      notification_event_type: type,
      push_event_type: type,
      push_booking_id: bookingId,
      actor_uid: actorId,
      recipient_uid: recipientUid,
      accepted_proposal_provider_uid: acceptedProposalProviderUid,
    });

    if (!eventId || !bookingId || !type) {
      logWarn('bookingEvents skipped: missing required fields', {
        eventId,
        notification_event_type: type,
        push_booking_id: bookingId,
      });
      return;
    }

    if (!['booking_price_proposed', 'booking_accepted', 'booking_direct_accepted', 'chat_message_created'].includes(type)) {
      logWarn('bookingEvents skipped: unsupported type', {
        eventId,
        notification_event_type: type,
        push_booking_id: bookingId,
      });
      return;
    }

    if (!recipientUid) {
      logWarn('bookingEvents skipped: recipient not resolved', {
        eventId,
        notification_event_type: type,
        push_booking_id: bookingId,
        clientId: val(event.clientId),
        outletId: val(event.outletId),
        acceptedOutletId: val(event.acceptedOutletId),
        actor_uid: actorId,
        recipient_uid: recipientUid,
        accepted_proposal_provider_uid: acceptedProposalProviderUid,
      });
      return;
    }

    if (recipientUid == actorId) {
      logWarn('bookingEvents skipped: actor and recipient are the same', {
        eventId,
        notification_event_type: type,
        push_booking_id: bookingId,
        actor_uid: actorId,
        recipient_uid: recipientUid,
        accepted_proposal_provider_uid: acceptedProposalProviderUid,
      });
      return;
    }

    const dedupeKey = buildEventDedupeKey(eventId, event, recipientUid);

    await runIdempotent({
      dedupeKey,
      metadata: {
        push_event_type: type,
        push_dedupe_key: dedupeKey,
        push_actor_uid: actorId,
        push_recipient_uid: recipientUid,
        push_booking_id: bookingId,
        accepted_proposal_provider_uid: acceptedProposalProviderUid,
      },
      run: async () => {
        const txt = buildNotificationText(type, event);
        const job = buildNotificationJob({
          type,
          bookingId,
          recipientUid,
          actorId,
          dedupeKey,
          sourceEventId: eventId,
          screen: txt.screen,
          notification: {
            title: txt.title,
            body: txt.body,
          },
          data: {
            dedupeKey,
            acceptedProposalProviderUid,
          },
        });

        await getDb().collection('notificationJobs').add(job);

        logInfo('notificationJobs created from bookingEvents', {
          eventId,
          notification_event_type: type,
          push_dedupe_key: dedupeKey,
          push_booking_id: bookingId,
          push_actor_uid: actorId,
          push_recipient_uid: recipientUid,
          accepted_proposal_provider_uid: acceptedProposalProviderUid,
        });
      },
    });
  }
);
