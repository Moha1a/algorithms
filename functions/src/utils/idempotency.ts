import * as admin from 'firebase-admin';

import {logInfo} from './logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export async function runIdempotent(params: {
  dedupeKey: string;
  metadata?: Record<string, unknown>;
  run: () => Promise<void>;
}): Promise<boolean> {
  const {dedupeKey, metadata = {}, run} = params;
  const ref = getDb().collection('notificationLogs').doc(dedupeKey);
  const existing = await ref.get();

  if (existing.exists) {
    logInfo('duplicate_notification_skipped', {
      dedupeKey,
      duplicate_notification_skipped: true,
      ...metadata,
    });
    return false;
  }

  await run();

  await ref.set(
    {
      dedupeKey,
      ...metadata,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  return true;
}
