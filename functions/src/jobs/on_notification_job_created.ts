import * as admin from 'firebase-admin';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';

import {sendNotificationJob} from '../sender/fcm_sender';
import {runIdempotent} from '../utils/idempotency';
import {logError, logInfo} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export const onNotificationJobCreated = onDocumentCreated(
  {document: 'notificationJobs/{jobId}', region: 'us-central1'},
  async (event) => {
    const jobId = String(event.params.jobId || '').trim();
    const job = event.data?.data() ?? {};
    if (!jobId) return;

    const dedupeKey = String(job.dedupeKey || `job_sender__${jobId}`);
    logInfo('Notification job received', {
      jobId,
      dedupeKey,
      type: String(job.type || ''),
      recipientUid: String(job.recipientUid || ''),
    });

    await runIdempotent({
      dedupeKey: `sender__${dedupeKey}`,
      run: async () => {
        try {
          logInfo('sendNotificationJob start', {jobId, type: String(job.type || '')});
          await getDb().collection('notificationJobs').doc(jobId).set(
            {
              status: 'processing',
              processingAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true}
          );

          await sendNotificationJob(job);

          await getDb().collection('notificationJobs').doc(jobId).set(
            {
              status: 'sent',
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true}
          );

          logInfo('Notification job sent', {jobId, type: String(job.type || '')});
          logInfo('sendNotificationJob complete', {jobId, type: String(job.type || '')});
        } catch (error) {
          await getDb().collection('notificationJobs').doc(jobId).set(
            {
              status: 'failed',
              failedAt: admin.firestore.FieldValue.serverTimestamp(),
              lastError: String((error as Error)?.message || error),
            },
            {merge: true}
          );

          logError('Notification job failed', {
            jobId,
            type: String(job.type || ''),
            error: String((error as Error)?.message || error),
          });
        }
      },
    });
  }
);
