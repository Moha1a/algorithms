import * as admin from 'firebase-admin';
import {onDocumentUpdated} from 'firebase-functions/v2/firestore';

import {logInfo} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

const ACTIVE_STATUSES = new Set(['accepted', 'in_progress', 'awaiting_provider_code']);

export const enforceSingleActiveOutletBooking = onDocumentUpdated(
  {
    document: 'bookings/{bookingId}',
    region: 'us-central1',
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const bookingRef = event.data?.after.ref;
    if (!bookingRef) return;

    const beforeStatus = String(before.status || '');
    const afterStatus = String(after.status || '');
    const outletId = String(after.outletId || '').trim();

    if (!outletId || !ACTIVE_STATUSES.has(afterStatus)) return;
    if (beforeStatus === afterStatus && String(before.outletId || '') === outletId) return;

    const db = getDb();
    const activeSnap = await db
      .collection('bookings')
      .where('outletId', '==', outletId)
      .where('status', 'in', Array.from(ACTIVE_STATUSES))
      .get();

    const activeDocs = activeSnap.docs;
    if (activeDocs.length <= 1) return;

    const sorted = [...activeDocs].sort((a, b) => {
      const aTs = (a.data().acceptedAt as FirebaseFirestore.Timestamp | undefined)?.toMillis() ?? 0;
      const bTs = (b.data().acceptedAt as FirebaseFirestore.Timestamp | undefined)?.toMillis() ?? 0;
      return aTs - bTs;
    });
    const keep = sorted[sorted.length - 1];

    const batch = db.batch();
    for (const doc of sorted) {
      if (doc.id == keep.id) continue;
      batch.update(doc.ref, {
        status: 'pending',
        outletId: null,
        outletName: null,
        acceptedAt: admin.firestore.FieldValue.delete(),
        revertedReason: 'single_active_outlet_enforced',
        revertedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    logInfo('single active outlet enforced', {
      outletId,
      keptBookingId: keep.id,
      revertedCount: sorted.length - 1,
    });
  }
);
