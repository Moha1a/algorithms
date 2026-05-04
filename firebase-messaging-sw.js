importScripts("https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I",
  authDomain: "qiqa-c17c2.firebaseapp.com",
  projectId: "qiqa-c17c2",
  storageBucket: "qiqa-c17c2.firebasestorage.app",
  messagingSenderId: "1025525101614",
  appId: "1:1025525101614:web:08c4c874f05d1713cfdbbf",
  measurementId: "G-B0L165W2VE"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(payload => {
  const title = payload?.notification?.title || payload?.data?.title || "إشعار جديد";
  const body = payload?.notification?.body || payload?.data?.body || "";
  const bookingId = payload?.data?.bookingId || "";
  self.registration.showNotification(title, {
    body,
    tag: bookingId || "qiqa-background-notification",
    renotify: true,
    data: { bookingId, url: "/" },
    icon: "https://www.gstatic.com/mobilesdk/160503_mobilesdk/logo/2x/firebase_28dp.png",
    badge: "https://www.gstatic.com/mobilesdk/160503_mobilesdk/logo/2x/firebase_28dp.png"
  });
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  event.waitUntil(clients.matchAll({ type: "window", includeUncontrolled: true }).then(clientList => {
    for (const client of clientList) {
      if ("focus" in client) return client.focus();
    }
    if (clients.openWindow) return clients.openWindow("/");
  }));
});
