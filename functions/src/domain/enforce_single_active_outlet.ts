import {onDocumentUpdated} from 'firebase-functions/v2/firestore';

import {logInfo} from '../utils/logger';

export const enforceSingleActiveOutletBooking = onDocumentUpdated(
  {
    document: 'bookings/{bookingId}',
    region: 'us-central1',
  },
  async (event) => {
    logInfo('provider_multiple_accept_allowed', {
      provider_multiple_accept_allowed: true,
      bookingId: String(event.params.bookingId || '').trim(),
    });
  }
);
