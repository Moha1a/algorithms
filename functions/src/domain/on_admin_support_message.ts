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

async function getAdminUids(): Promise<string[]> {
  const snap = await getDb().collection('users').where('role', '==', 'admin').get();
  return snap.docs.map((doc) => doc.id).filter((uid) => uid.length > 0);
}

async function createAdminSupportNotification(args: {
  threadKind: 'general' | 'trip';
  threadId: string;
  messageId: string;
  actorId: string;
  messageText: string;
}): Promise<void> {
  const adminUids = await getAdminUids();
  if (!adminUids.length) {
    logWarn('admin support notification skipped: no admin users found', {
      threadKind: args.threadKind,
      threadId: args.threadId,
      messageId: args.messageId,
      actorId: args.actorId,
    });
    return;
  }

  const actorSnap = await getDb().collection('users').doc(args.actorId).get();
  const actor = actorSnap.data() ?? {};
  const actorName =
    clean(actor.fullName) ||
    clean(actor.outletName) ||
    clean(actor.name) ||
    'مستخدم';
  const body = args.messageText || 'لديك رسالة جديدة من مستخدم.';

  await Promise.all(
    adminUids
      .filter((adminUid) => adminUid !== args.actorId)
      .map(async (adminUid) => {
        const dedupeKey = `admin_support_message:${args.threadKind}:${args.threadId}:${args.messageId}:${adminUid}`;

        await runIdempotent({
          dedupeKey,
          metadata: {
            push_event_type: 'admin_support_message',
            push_dedupe_key: dedupeKey,
            push_actor_uid: args.actorId,
            push_recipient_uid: adminUid,
            support_thread_kind: args.threadKind,
            support_thread_id: args.threadId,
          },
          run: async () => {
            await getDb().collection('notifications').add({
              toUserId: adminUid,
              type: 'admin_support_message',
              bookingId: args.threadKind === 'trip' ? args.threadId : '',
              title: `رسالة من ${actorName}`,
              body,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            const job = buildNotificationJob({
              type: 'admin_support_message',
              recipientUid: adminUid,
              bookingId: args.threadKind === 'trip' ? args.threadId : '',
              actorId: args.actorId,
              dedupeKey,
              sourceEventId: `admin_support_${args.threadKind}_${args.threadId}_${args.messageId}`,
              screen: 'admin_chat',
              notification: {
                title: `رسالة من ${actorName}`,
                body,
              },
              data: {
                dedupeKey,
                supportThreadKind: args.threadKind,
                supportThreadId: args.threadId,
                messageId: args.messageId,
              },
            });

            await getDb().collection('notificationJobs').add(job);

            logInfo('admin support notification job created', {
              push_event_type: 'admin_support_message',
              push_dedupe_key: dedupeKey,
              push_actor_uid: args.actorId,
              push_recipient_uid: adminUid,
              support_thread_kind: args.threadKind,
              support_thread_id: args.threadId,
              messageId: args.messageId,
            });
          },
        });
      })
  );
}

export const onGeneralSupportMessageCreated = onDocumentCreated(
  {document: 'support_general/{threadId}/messages/{messageId}', region: 'us-central1'},
  async (event) => {
    const threadId = clean(event.params.threadId);
    const messageId = clean(event.params.messageId);
    const message = event.data?.data() ?? {};
    const actorId = clean(message.senderId);
    const messageText = clean(message.text);

    if (!threadId || !messageId || !actorId) {
      logWarn('general support admin notification skipped: missing fields', {
        threadId,
        messageId,
        actorId,
      });
      return;
    }

    await createAdminSupportNotification({
      threadKind: 'general',
      threadId,
      messageId,
      actorId,
      messageText,
    });
  }
);

export const onTripSupportMessageCreated = onDocumentCreated(
  {document: 'trip_support/{threadId}/messages/{messageId}', region: 'us-central1'},
  async (event) => {
    const threadId = clean(event.params.threadId);
    const messageId = clean(event.params.messageId);
    const message = event.data?.data() ?? {};
    const actorId = clean(message.senderId);
    const messageText = clean(message.text);

    if (!threadId || !messageId || !actorId) {
      logWarn('trip support admin notification skipped: missing fields', {
        threadId,
        messageId,
        actorId,
      });
      return;
    }

    await createAdminSupportNotification({
      threadKind: 'trip',
      threadId,
      messageId,
      actorId,
      messageText,
    });
  }
);
