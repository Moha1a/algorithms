import * as admin from 'firebase-admin';
import {onDocumentUpdated} from 'firebase-functions/v2/firestore';

import {logInfo} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export const cancelOtherPendingOffersForAcceptedOutlet = onDocumentUpdated(
  {
    document: 'bookings/{bookingId}',
    region: 'us-central1',
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const bookingId = event.params.bookingId;
    const beforeStatus = String(before.status || '');
    const afterStatus = String(after.status || '');
    const outletId = String(after.outletId || '').trim();

    if (!outletId) return;
    if (!(beforeStatus != 'accepted' && afterStatus == 'accepted')) return;

    const db = getDb();
    const pendingSnap = await db
      .collection('bookings')
      .where('status', '==', 'pending')
      .get();

    const batch = db.batch();
    let touched = 0;
    for (const doc of pendingSnap.docs) {
      if (doc.id === bookingId) continue;
      const data = doc.data() ?? {};
      const proposalsRaw = Array.isArray(data.priceProposals) ? data.priceProposals : [];
      if (!proposalsRaw.length) continue;
      const proposals = proposalsRaw.map((p) => ({...(p as Record<string, unknown>)}));
      const filtered = proposals.filter((p) => String(p.outletId || '') !== outletId);
      if (filtered.length === proposals.length) continue;
      batch.update(doc.ref, {
        priceProposals: filtered,
        lastProposalCleanupAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      touched += 1;
    }

    if (touched > 0) {
      await batch.commit();
    }
    logInfo('cancelOtherPendingOffersForAcceptedOutlet done', {bookingId, outletId, touched});
  }
);
