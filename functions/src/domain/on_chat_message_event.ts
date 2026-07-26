import * as admin from 'firebase-admin';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';

import {buildNotificationJob} from './job_builder';
import {runIdempotent} from '../utils/idempotency';
import {logInfo, logWarn} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function clean(v: unknown): string {
  return String(v ?? '').trim();
}

export const onChatMessageEvent = onDocumentCreated(
  {document: 'booking_chats/{bookingId}/messages/{messageId}', region: 'us-central1'},
  async (event) => {
    const bookingId = clean(event.params.bookingId);
    const messageId = clean(event.params.messageId);
    const message = event.data?.data() ?? {};
    const actorId = clean(message.senderId);
    const messageText = clean(message.text);

    if (!bookingId || !messageId || !actorId) {
      logWarn('onChatMessageEvent skipped: missing bookingId/messageId/actorId', {
        bookingId,
        messageId,
        actorId,
      });
      return;
    }

    const bookingSnap = await getDb().collection('bookings').doc(bookingId).get();
    const booking = bookingSnap.data() ?? {};
    const clientId = clean(booking.clientId);
    const outletId = clean(booking.outletId);
    const recipientUid = actorId == clientId ? outletId : clientId;
    if (!recipientUid) {
      logWarn('onChatMessageEvent skipped: recipient not resolved', {
        bookingId,
        messageId,
        actorId,
        clientId,
        outletId,
      });
      return;
    }
    if (recipientUid == actorId) {
      logWarn('onChatMessageEvent skipped: actor and recipient are the same', {
        bookingId,
        messageId,
        actorId,
        recipientUid,
      });
      return;
    }

    const dedupeKey = `message_created:${bookingId}:${messageId}:${recipientUid}`;
    await runIdempotent({
      dedupeKey,
      metadata: {
        push_event_type: 'chat_message_created',
        push_dedupe_key: dedupeKey,
        push_actor_uid: actorId,
        push_recipient_uid: recipientUid,
        push_booking_id: bookingId,
      },
      run: async () => {
        const senderSnap = await getDb().collection('users').doc(actorId).get();
        const sender = senderSnap.data() ?? {};
        const senderName = clean(sender.fullName) || clean(sender.outletName) || 'رسالة جديدة';
        const body = messageText || 'لديك رسالة جديدة بخصوص الطلب.';

        await getDb().collection('notifications').add({
          toUserId: recipientUid,
          type: 'new_message',
          bookingId,
          title: senderName,
          body,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const job = buildNotificationJob({
          type: 'chat_message_created',
          recipientUid,
          bookingId,
          actorId,
          dedupeKey,
          sourceEventId: `chat_message_${bookingId}_${messageId}`,
          screen: 'chat',
          notification: {
            title: senderName,
            body,
          },
          data: {dedupeKey},
        });
        await getDb().collection('notificationJobs').add(job);

        logInfo('onChatMessageEvent created notification + job', {
          bookingId,
          messageId,
          push_event_type: 'chat_message_created',
          push_dedupe_key: dedupeKey,
          push_actor_uid: actorId,
          push_recipient_uid: recipientUid,
          push_booking_id: bookingId,
        });
      },
    });
  }
);
