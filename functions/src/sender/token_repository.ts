import * as admin from 'firebase-admin';

import {logInfo} from '../utils/logger';

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export type DeviceTokenRecord = {
  deviceId: string;
  token: string;
};

export async function getActiveDeviceTokens(uid: string): Promise<DeviceTokenRecord[]> {
  const cleanUid = uid.trim();
  if (!cleanUid) return [];

  const db = getDb();
  const devicesSnap = await db.collection('users').doc(cleanUid).collection('devices').where('notificationEnabled', '==', true).get();

  const devices = devicesSnap.docs
    .map((d) => {
      const data = d.data() ?? {};
      return {
        deviceId: d.id,
        token: String(data.token || '').trim(),
      };
    })
    .filter((d) => d.token);

  if (devices.length > 0) {
    logInfo('Device tokens loaded from devices', {uid: cleanUid, count: devices.length});
    return devices;
  }

  const legacy = await db.collection('users').doc(cleanUid).collection('fcmTokens').get();
  const legacyTokens = legacy.docs
    .map((d) => String((d.data() ?? {}).token || d.id || '').trim())
    .filter((x) => x)
    .map((token, i) => ({deviceId: `legacy_${i}`, token}));

  logInfo('Device tokens loaded from fcmTokens legacy', {uid: cleanUid, count: legacyTokens.length});
  return legacyTokens;
}

export async function deleteDeviceById(uid: string, deviceId: string): Promise<void> {
  if (deviceId.startsWith('legacy_')) return;
  const cleanUid = uid.trim();
  if (!cleanUid) return;
  await getDb().collection('users').doc(cleanUid).collection('devices').doc(deviceId).delete();
}