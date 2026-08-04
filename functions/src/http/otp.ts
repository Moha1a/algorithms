import {onRequest} from 'firebase-functions/v2/https';
import {defineSecret} from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';

const providerBaseUrl = 'https://gateway.standingtech.com';
const senderId = 'Manfathak';
const bulkSmsIraqApiToken = defineSecret('BULKSMSIRAQ_API_TOKEN');

function generateOtp(): string {
  return `${Math.floor(100000 + Math.random() * 900000)}`;
}

function setCors(res: any): void {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function token(): string {
  return bulkSmsIraqApiToken.value().trim();
}

function normalizeRecipient(raw: unknown): string {
  const digits = String(raw ?? '').replace(/\D/g, '');
  if (digits.startsWith('9647') && digits.length === 13) return digits;
  if (digits.startsWith('07') && digits.length === 11) return `964${digits.substring(1)}`;
  if (digits.startsWith('7') && digits.length === 10) return `964${digits}`;
  throw new Error('invalid-recipient');
}

async function postProvider(path: string, body: Record<string, unknown>): Promise<any> {
  const apiToken = token();
  if (!apiToken) {
    throw new Error('missing-bulksmsiraq-token');
  }

  const response = await fetch(`${providerBaseUrl}${path}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiToken}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  let data: any = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch (_) {
    data = {raw: text};
  }
  if (!response.ok) {
    logger.error('otp_provider_http_error', {
      status: response.status,
      path,
      response: data,
    });
    throw new Error('otp-provider-http-error');
  }
  return data;
}

export const sendOtpCode = onRequest(
  {
    region: 'us-central1',
    timeoutSeconds: 30,
    secrets: [bulkSmsIraqApiToken],
  },
  async (req, res) => {
    setCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({status: 'error', code: 'method-not-allowed'});
      return;
    }

    try {
      const recipient = normalizeRecipient(req.body?.recipient);
      const otp = generateOtp();
      const data = await postProvider('/api/v4/sms/send', {
        recipient,
        sender_id: senderId,
        type: 'whatsapp',
        message: otp,
        lang: 'en',
      });
      const id = String(data?.id ?? '').trim();
      if (!id) {
        logger.error('otp_provider_missing_id', {response: data});
        res.status(502).json({status: 'error', code: 'otp-provider-missing-id'});
        return;
      }
      logger.info('otp_sent', {recipientPrefix: recipient.substring(0, 6), providerIdPresent: true});
      res.json({status: 'success', id});
    } catch (error: any) {
      logger.error('otp_send_failed', {message: error?.message ?? String(error)});
      res.status(400).json({status: 'error', code: error?.message ?? 'otp-send-failed'});
    }
  },
);

export const verifyOtpCode = onRequest(
  {
    region: 'us-central1',
    timeoutSeconds: 30,
    secrets: [bulkSmsIraqApiToken],
  },
  async (req, res) => {
    setCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({status: 'error', code: 'method-not-allowed'});
      return;
    }

    try {
      const recipient = normalizeRecipient(req.body?.recipient);
      const code = String(req.body?.code ?? '').replace(/\D/g, '');
      const id = String(req.body?.id ?? '').trim();
      if (code.length < 4 || !id) throw new Error('invalid-otp-request');
      const data = await postProvider('/api/v4/sms/verifyotp', {
        recipient,
        code,
        id,
        expire: 'yes',
      });
      const ok = String(data?.status ?? '').toLowerCase() === 'success';
      logger.info('otp_verify_result', {
        recipientPrefix: recipient.substring(0, 6),
        success: ok,
      });
      res.status(ok ? 200 : 400).json({
        status: ok ? 'success' : 'error',
        code: ok ? 'verified' : 'invalid-otp',
      });
    } catch (error: any) {
      logger.error('otp_verify_failed', {message: error?.message ?? String(error)});
      res.status(400).json({status: 'error', code: error?.message ?? 'otp-verify-failed'});
    }
  },
);
