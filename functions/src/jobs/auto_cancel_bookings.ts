import * as admin from 'firebase-admin';
import {onSchedule} from 'firebase-functions/v2/scheduler';

import {buildNotificationJob} from '../domain/job_builder';
import {runIdempotent} from '../utils/idempotency';
import {logError, logInfo} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

const ACTIVE_STATUSES = new Set(['pending', 'accepted', 'in_progress', 'awaiting_provider_code']);
const TERMINAL_STATUSES = new Set(['completed', 'cancelled', 'rejected', 'closed']);
const FOURTEEN_HOURS_MS = 14 * 60 * 60 * 1000;

function clean(value: unknown): string {
  return String(value ?? '').trim();
}

function extractCreatedAtMillis(data: FirebaseFirestore.DocumentData): number | null {
  const candidates = [data.createdAt, data.requestCreatedAt];
  for (const candidate of candidates) {
    if (candidate instanceof admin.firestore.Timestamp) {
      return candidate.toMillis();
    }
  }
  return null;
}

async function createAutoCancelNotification(params: {
  bookingId: string;
  recipientUid: string;
  actorId: string;
}): Promise<void> {
  const {bookingId, recipientUid, actorId} = params;
  const dedupeKey = `booking_auto_cancelled_14h:${bookingId}:${recipientUid}`;

  await runIdempotent({
    dedupeKey,
    metadata: {
      push_event_type: 'booking_auto_cancelled_14h',
      push_dedupe_key: dedupeKey,
      push_actor_uid: actorId,
      push_recipient_uid: recipientUid,
      push_booking_id: bookingId,
    },
    run: async () => {
      await getDb().collection('notifications').add({
        toUserId: recipientUid,
        type: 'booking_auto_cancelled_14h',
        bookingId,
        title: 'تم إلغاء الطلب تلقائياً',
        body: 'تم إلغاء الطلب لأنه لم يكتمل خلال 14 ساعة.',
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const job = buildNotificationJob({
        type: 'booking_auto_cancelled_14h',
        recipientUid,
        bookingId,
        actorId,
        screen: 'booking_details',
        dedupeKey,
        sourceEventId: `auto_cancel_${bookingId}`,
        notification: {
          title: 'تم إلغاء الطلب تلقائياً',
          body: 'تم إلغاء الطلب لأنه لم يكتمل خلال 14 ساعة.',
        },
        data: {dedupeKey},
      });
      await getDb().collection('notificationJobs').add(job);
    },
  });
}

export const autoCancelStaleBookings = onSchedule(
  {schedule: 'every 10 minutes', timeZone: 'UTC', region: 'us-central1'},
  async () => {
    const db = getDb();
    const now = Date.now();
    const threshold = now - FOURTEEN_HOURS_MS;

    const activeSnap = await db
      .collection('bookings')
      .where('status', 'in', Array.from(ACTIVE_STATUSES))
      .get();

    let scanned = 0;
    let cancelled = 0;
    let skippedCompleted = 0;
    let skippedAlreadyCancelled = 0;
    let skippedMissingCreatedAt = 0;
    let skippedNotExpired = 0;

    for (const doc of activeSnap.docs) {
      scanned += 1;
      const data = doc.data() ?? {};
      const bookingId = clean(data.bookingId) || doc.id;
      const status = clean(data.status);

      if (TERMINAL_STATUSES.has(status)) {
        if (status == 'completed') {
          skippedCompleted += 1;
        } else {
          skippedAlreadyCancelled += 1;
        }
        continue;
      }

      const createdAtMillis = extractCreatedAtMillis(data);
      if (createdAtMillis == null) {
        skippedMissingCreatedAt += 1;
        logInfo('autoCancelStaleBookings skipped: missing createdAt', {
          bookingId,
          status,
        });
        continue;
      }

      if (createdAtMillis > threshold) {
        skippedNotExpired += 1;
        continue;
      }

      try {
        await doc.ref.set(
          {
            status: 'cancelled',
            cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
            cancelReason: 'auto_timeout_14_hours',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        const clientId = clean(data.clientId) || clean(data.createdById);
        const outletId = clean(data.outletId);
        const recipients = Array.from(new Set([clientId, outletId].filter((uid) => uid)));
        for (const recipientUid of recipients) {
          await createAutoCancelNotification({
            bookingId,
            recipientUid,
            actorId: 'system_auto_cancel',
          });
        }

        cancelled += 1;
      } catch (error) {
        logError('autoCancelStaleBookings failed to cancel booking', {
          bookingId,
          status,
          error: String((error as Error)?.message || error),
        });
      }
    }

    logInfo('autoCancelStaleBookings finished', {
      booking_auto_cancel_scan_count: scanned,
      booking_auto_cancel_cancelled_count: cancelled,
      booking_auto_cancel_skipped_count: skippedCompleted + skippedAlreadyCancelled + skippedMissingCreatedAt + skippedNotExpired,
      skipped_completed: skippedCompleted,
      skipped_already_cancelled: skippedAlreadyCancelled,
      skipped_missing_createdAt: skippedMissingCreatedAt,
      skipped_not_expired: skippedNotExpired,
    });
  }
);
