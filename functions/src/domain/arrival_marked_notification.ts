import * as admin from 'firebase-admin';
import {onDocumentUpdated} from 'firebase-functions/v2/firestore';

import {runIdempotent} from '../utils/idempotency';
import {logInfo, logWarn} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function v(input: unknown): string {
  return String(input ?? '').trim();
}

export const onArrivalMarkedNotifyProvider = onDocumentUpdated(
  {document: 'bookings/{bookingId}', region: 'us-central1'},
  async (event) => {
    const bookingId = v(event.params.bookingId);
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    if (!bookingId) return;

    const beforeStatus = v(before.status);
    const afterStatus = v(after.status);
    const outletId = v(after.outletId);
    const arrivalMarkedBy = v(after.arrivalMarkedBy);
    const clientId = v(after.clientId);

    if (beforeStatus === afterStatus && beforeStatus === 'awaiting_provider_code') return;
    if (afterStatus !== 'awaiting_provider_code') return;
    if (!outletId || !arrivalMarkedBy || !clientId) {
      logWarn('arrival_marked skipped: missing required fields', {bookingId, outletId, arrivalMarkedBy, clientId});
      return;
    }
    if (arrivalMarkedBy !== clientId) {
      logWarn('arrival_marked skipped: marker is not client', {bookingId, outletId, arrivalMarkedBy, clientId});
      return;
    }

    const dedupeKey = `arrival_marked__${bookingId}__${arrivalMarkedBy}`;
    await runIdempotent({
      dedupeKey,
      run: async () => {
        await getDb().collection('notificationJobs').add({
          type: 'arrival_marked',
          bookingId,
          recipientUid: outletId,
          actorId: arrivalMarkedBy,
          dedupeKey,
          sourceEventId: bookingId,
          notification: {
            title: 'تم تسجيل الوصول 📍',
            body: 'صاحب الطلب ضغط "أنا وصلت". افتح الطلب للمتابعة.',
          },
          data: {
            type: 'arrival_marked',
            bookingId,
            screen: 'booking_details',
            actorId: arrivalMarkedBy,
          },
          status: 'queued',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        logInfo('arrival_marked notification job created', {
          bookingId,
          recipientUid: outletId,
          actorId: arrivalMarkedBy,
        });
      },
    });
  }
);