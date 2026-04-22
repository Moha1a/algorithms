import * as admin from 'firebase-admin';
import {onSchedule} from 'firebase-functions/v2/scheduler';

import {logInfo} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export const autoCancelStaleBookings = onSchedule(
  {schedule: 'every 10 minutes', timeZone: 'UTC', region: 'us-central1'},
  async () => {
    const db = getDb();
    const now = Date.now();
    const acceptedThreshold = now - 3 * 60 * 60 * 1000; // 3 hours
    const awaitingThreshold = now - 1 * 60 * 60 * 1000; // 1 hour

    const acceptedSnap = await db
      .collection('bookings')
      .where('status', '==', 'accepted')
      .where('acceptedAt', '<=', admin.firestore.Timestamp.fromMillis(acceptedThreshold))
      .get();

    let cancelledAccepted = 0;
    for (const doc of acceptedSnap.docs) {
      const d = doc.data() ?? {};
      if (d.arrivalMarkedAt) continue;
      await doc.ref.update({
        status: 'cancelled',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        cancelReason: 'auto_cancel_no_arrival_within_3h',
      });
      cancelledAccepted += 1;
    }

    const awaitingSnap = await db
      .collection('bookings')
      .where('status', '==', 'awaiting_provider_code')
      .where('arrivalMarkedAt', '<=', admin.firestore.Timestamp.fromMillis(awaitingThreshold))
      .get();

    let cancelledAwaiting = 0;
    for (const doc of awaitingSnap.docs) {
      await doc.ref.update({
        status: 'cancelled',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        cancelReason: 'auto_cancel_no_completion_within_1h',
      });
      cancelledAwaiting += 1;
    }

    logInfo('autoCancelStaleBookings finished', {
      cancelledAccepted,
      cancelledAwaiting,
    });
  }
);
