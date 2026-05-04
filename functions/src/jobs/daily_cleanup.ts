import * as admin from 'firebase-admin';
import {onSchedule} from 'firebase-functions/v2/scheduler';

import {logInfo} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}
const DAYS_OLD = 60;

export const cleanupStaleDeviceTokensDaily = onSchedule(
  {schedule: 'every day 03:00', timeZone: 'UTC', region: 'us-central1'},
  async () => {
    const threshold = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - DAYS_OLD * 24 * 60 * 60 * 1000)
    );

    const db = getDb();
    const usersSnap = await db.collection('users').get();
    let removed = 0;

    for (const userDoc of usersSnap.docs) {
      const devicesSnap = await userDoc.ref.collection('devices').get();
      const batch = db.batch();

      for (const deviceDoc of devicesSnap.docs) {
        const d = deviceDoc.data() ?? {};
        const enabled = Boolean(d.notificationEnabled ?? false);
        const lastSeenAt = d.lastSeenAt as FirebaseFirestore.Timestamp | undefined;
        const lastTokenAt = d.lastTokenAt as FirebaseFirestore.Timestamp | undefined;

        const staleBySeen = !lastSeenAt || lastSeenAt.toMillis() < threshold.toMillis();
        const staleByToken = !lastTokenAt || lastTokenAt.toMillis() < threshold.toMillis();

        if (!enabled || staleBySeen || staleByToken) {
          batch.delete(deviceDoc.ref);
          removed += 1;
        }
      }

      await batch.commit();
    }

    logInfo('Daily cleanup finished', {removedDevices: removed, daysOldThreshold: DAYS_OLD});
  }
);
