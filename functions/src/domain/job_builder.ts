import * as admin from 'firebase-admin';

export type NotificationJobType =
  | 'booking_price_proposed'
  | 'booking_accepted'
  | 'booking_direct_accepted'
  | 'booking_new_request_created'
  | 'chat_message_created'
  | 'booking_auto_cancelled_11h'
  | 'booking_auto_cancelled_14h';

export type NotificationJobPayload = {
  type: NotificationJobType;
  recipientUid: string;
  bookingId: string;
  actorId?: string;
  screen: string;
  notification: {
    title: string;
    body: string;
  };
  data: Record<string, string>;
  dedupeKey?: string;
  sourceEventId: string;
};

function fallbackDedupeKey(input: NotificationJobPayload): string {
  return `job__${input.sourceEventId}__${input.type}__${input.recipientUid}`;
}

export function buildNotificationJob(input: NotificationJobPayload) {
  return {
    type: input.type,
    recipientUid: input.recipientUid,
    bookingId: input.bookingId,
    actorId: input.actorId || '',
    screen: input.screen,
    sourceEventId: input.sourceEventId,
    notification: input.notification,
    data: {
      ...input.data,
      type: input.type,
      bookingId: input.bookingId,
      screen: input.screen,
      actorId: input.actorId || '',
    },
    status: 'pending',
    dedupeKey: input.dedupeKey || fallbackDedupeKey(input),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}
