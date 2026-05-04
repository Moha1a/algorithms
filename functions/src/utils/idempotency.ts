import * as admin from 'firebase-admin';

import {logInfo} from './logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export async function runIdempotent(params: {
  dedupeKey: string;
  run: () => Promise<void>;
}): Promise<boolean> {
  const {dedupeKey, run} = params;
  const ref = getDb().collection('notificationLogs').doc(dedupeKey);
  const existing = await ref.get();

  if (existing.exists) {
    logInfo('Idempotency: skip duplicate event', {dedupeKey});
    return false;
  }

  await run();

  await ref.set(
    {
      dedupeKey,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  return true;
}
