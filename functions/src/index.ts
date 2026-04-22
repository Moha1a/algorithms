import * as admin from 'firebase-admin';

import {cancelOtherPendingOffersForAcceptedOutlet} from './domain/cancel_other_pending_offers';
import {enforceSingleActiveOutletBooking} from './domain/enforce_single_active_outlet';
import {cleanupStaleDeviceTokensDaily} from './jobs/daily_cleanup';
import {autoCancelStaleBookings} from './jobs/auto_cancel_bookings';
import {sendPushNotification} from './http/send_push_notification';
import {onNotificationJobCreated} from './jobs/on_notification_job_created';
import {onArrivalMarkedNotifyProvider} from './domain/arrival_marked_notification';
import {onBookingEventCreated} from './domain/events';
import {onChatMessageEvent} from './domain/on_chat_message_event';

if (!admin.apps.length) {
  admin.initializeApp();
}

exports.sendPushNotification = sendPushNotification;
exports.onNotificationJobCreated = onNotificationJobCreated;
exports.cleanupStaleDeviceTokensDaily = cleanupStaleDeviceTokensDaily;
exports.autoCancelStaleBookings = autoCancelStaleBookings;
exports.enforceSingleActiveOutletBooking = enforceSingleActiveOutletBooking;
exports.cancelOtherPendingOffersForAcceptedOutlet = cancelOtherPendingOffersForAcceptedOutlet;
exports.onArrivalMarkedNotifyProvider = onArrivalMarkedNotifyProvider;
exports.onBookingEventCreated = onBookingEventCreated;
exports.onChatMessageEvent = onChatMessageEvent;