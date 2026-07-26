import * as admin from 'firebase-admin';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';

import {buildNotificationJob} from './job_builder';
import {runIdempotent} from '../utils/idempotency';
import {logError, logInfo, logWarn} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function clean(value: unknown): string {
  return String(value ?? '').trim();
}

function requestTypeLabel(type: string): string {
  switch (type) {
    case 'withdraw':
      return 'سحب';
    case 'deposit':
      return 'شحن';
    case 'discharge':
      return 'تفريغ';
    default:
      return 'جديد';
  }
}

function outletCanReceiveNewRequest(user: FirebaseFirestore.DocumentData): boolean {
  if (clean(user.role) !== 'outlet') return false;
  const approvalStatus = clean(user.approvalStatus);
  return approvalStatus.length === 0 || approvalStatus === 'approved';
}

export const onBookingCreatedNotifyOutlets = onDocumentCreated(
  {document: 'bookings/{bookingId}', region: 'us-central1'},
  async (event) => {
    const bookingId = clean(event.params.bookingId);
    const booking = event.data?.data() ?? {};
    const status = clean(booking.status);
    const actorId = clean(booking.createdById) || clean(booking.clientId);
    const type = clean(booking.type);
    const typeLabel = requestTypeLabel(type);

    if (!bookingId) {
      logWarn('onBookingCreatedNotifyOutlets skipped: missing bookingId');
      return;
    }

    if (status && status !== 'pending') {
      logInfo('onBookingCreatedNotifyOutlets skipped: booking not pending', {
        bookingId,
        status,
        push_event_type: 'booking_new_request_created',
      });
      return;
    }

    const outletsSnap = await getDb().collection('users').where('role', '==', 'outlet').get();
    let scanned = 0;
    let eligible = 0;
    let notified = 0;
    let skippedActor = 0;
    let skippedNotApproved = 0;

    for (const doc of outletsSnap.docs) {
      scanned += 1;
      const recipientUid = clean(doc.id);
      const user = doc.data() ?? {};
      if (!outletCanReceiveNewRequest(user)) {
        skippedNotApproved += 1;
        continue;
      }
      if (actorId && recipientUid === actorId) {
        skippedActor += 1;
        continue;
      }

      eligible += 1;
      const dedupeKey = `booking_new_request_created:${bookingId}:${recipientUid}`;
      try {
        const processed = await runIdempotent({
          dedupeKey,
          metadata: {
            push_event_type: 'booking_new_request_created',
            push_dedupe_key: dedupeKey,
            push_actor_uid: actorId,
            push_recipient_uid: recipientUid,
            push_booking_id: bookingId,
            request_type: type,
          },
          run: async () => {
            const title = 'طلب جديد متاح';
            const body = `نزل طلب ${typeLabel} جديد. افتح منفذك لمراجعة التفاصيل.`;

            await getDb().collection('notifications').add({
              toUserId: recipientUid,
              type: 'booking_new_request_created',
              bookingId,
              title,
              body,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            const job = buildNotificationJob({
              type: 'booking_new_request_created',
              recipientUid,
              bookingId,
              actorId,
              dedupeKey,
              sourceEventId: `booking_created_${bookingId}`,
              screen: 'bookings',
              notification: {title, body},
              data: {
                dedupeKey,
                requestType: type,
                requestOwnerRole: clean(booking.requestOwnerRole),
              },
            });
            await getDb().collection('notificationJobs').add(job);
          },
        });
        if (processed) notified += 1;
      } catch (error) {
        logError('onBookingCreatedNotifyOutlets failed for recipient', {
          bookingId,
          recipientUid,
          push_event_type: 'booking_new_request_created',
          error: String((error as Error)?.message || error),
        });
      }
    }

    logInfo('onBookingCreatedNotifyOutlets complete', {
      bookingId,
      push_event_type: 'booking_new_request_created',
      push_actor_uid: actorId,
      request_type: type,
      outlets_scanned: scanned,
      outlets_eligible: eligible,
      outlets_notified: notified,
      outlets_skipped_actor: skippedActor,
      outlets_skipped_not_approved: skippedNotApproved,
    });
  }
);
