import { logger } from '$lib/server/logger';
import { env as envPublic } from '$env/dynamic/public';
import { env as envPrivate } from '$env/dynamic/private';
import qs from 'qs';

const PAYPAL_BASE_URL = envPrivate.PAYPAL_BASE_URL!;
const PAYPAL_CLIENT_ID = envPublic.PUBLIC_PAYPAL_CLIENT_ID;
const PAYPAL_CLIENT_SECRET = envPrivate.PAYPAL_CLIENT_SECRET!;

export async function getAmountFromPaypal(orderId: string, paypalAccessToken: string) {
  try {
    const response = await fetch(`${PAYPAL_BASE_URL}/v2/checkout/orders/${orderId}`, {
      headers: { Authorization: `Bearer ${paypalAccessToken}` },
    });
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    const data = await response.json();
    logger.info('PayPal amount fetched successfully');
    return data.purchase_units[0].amount.value;
  } catch (error: any) {
    logger.error(error.message);
  }
}

export async function generateAccessToken() {
  try {
    const credentials = Buffer.from(`${PAYPAL_CLIENT_ID}:${PAYPAL_CLIENT_SECRET}`).toString(
      'base64',
    );
    const response = await fetch(`${PAYPAL_BASE_URL}/v1/oauth2/token`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `Basic ${credentials}`,
      },
      body: qs.stringify({ grant_type: 'client_credentials' }),
    });
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    const data = await response.json();
    logger.info('PayPal access token generated successfully');
    return data.access_token;
  } catch (error: any) {
    logger.error(error.message);
  }
}
