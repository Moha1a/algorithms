const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

if (!admin.apps.length) {
  admin.initializeApp();
}

function applyCors(req, res) {
  const origin = String(req.headers.origin || "*");
  res.set("Access-Control-Allow-Origin", origin);
  res.set("Vary", "Origin");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Max-Age", "3600");
}

async function tokensForUser(uid) {
  const db = admin.firestore();
  const tokens = [];

  const devicesSnap = await db.collection("users").doc(uid).collection("devices").where("notificationEnabled", "==", true).get();
  devicesSnap.forEach((d) => {
    const t = String(d.data()?.token || "").trim();
    if (t) tokens.push(t);
  });

  if (!tokens.length) {
    const legacy = await db.collection("users").doc(uid).collection("fcmTokens").get();
    legacy.forEach((d) => {
      const t = String(d.id || "").trim();
      if (t) tokens.push(t);
    });
  }

  return Array.from(new Set(tokens));
}

exports.sendPushNotification = onRequest({ region: "us-central1" }, async (req, res) => {
  applyCors(req, res);

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "Method not allowed" });
    return;
  }

  try {
    const {
      recipientUid,
      title,
      body,
      type = "",
      bookingId = "",
      actorId = "",
    } = req.body || {};

    if (!recipientUid || !title || !body) {
      res.status(400).json({ ok: false, error: "Missing recipientUid/title/body" });
      return;
    }

    const tokens = await tokensForUser(String(recipientUid));
    const tokensCount = tokens.length;
    if (!tokens.length) {
      logger.warn("sendPushNotification skipped: no tokens", {
        recipientUid,
        tokensCount: 0,
        type,
        bookingId,
      });
      res.status(200).json({ ok: true, skipped: "no_tokens" });
      return;
    }

    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        type: String(type || ""),
        bookingId: String(bookingId || ""),
        actorId: String(actorId || ""),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "high_importance_channel",
          sound: "default"
        }
      },
      apns: {
        payload: {
          aps: { sound: "default" }
        }
      }
    });

    const failures = result.responses
      .map((r, i) => ({ r, i }))
      .filter((x) => !x.r.success)
      .map((x) => ({
        tokenIndex: x.i,
        errorCode: String(x.r.error?.code || "unknown"),
        errorMessage: String(x.r.error?.message || "unknown"),
      }));

    logger.info("sendPushNotification direct event send", {
      recipientUid,
      tokensCount,
      bookingId,
      type,
      successCount: result.successCount,
      failureCount: result.failureCount,
      failures,
    });

    res.status(200).json({
      ok: true,
      tokensCount,
      successCount: result.successCount,
      failureCount: result.failureCount,
      failures,
    });
  } catch (err) {
    logger.error("sendPushNotification failed", {
      errorCode: String(err?.code || "unknown"),
      errorMessage: String(err?.message || err),
    });
    res.status(500).json({
      ok: false,
      errorCode: String(err?.code || "unknown"),
      errorMessage: String(err?.message || err),
    });
  }
});
