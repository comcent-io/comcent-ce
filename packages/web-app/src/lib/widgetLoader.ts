import DialerWidget from './components/DialerWidget/DialerWidget.svelte';
import type { DialerWidgetDelegate } from '$lib/components/DialerWidget/types/DialerWidgetDelegate';

class ComcentDialerWidget {
  private token: string;
  private delegate: DialerWidgetDelegate;
  private dialerWidget: DialerWidget;
  private timer;
  private appBaseUrl: string;
  private sipWsUrl?: string;

  constructor(props: {
    token: string;
    delegate: DialerWidgetDelegate;
    appBaseUrl?: string;
    sipWsUrl?: string;
  }) {
    this.token = props.token;
    this.delegate = props.delegate;
    this.appBaseUrl = props.appBaseUrl || 'https://app.example.com';
    this.sipWsUrl = props.sipWsUrl;
    this.timer = setInterval(
      () => {
        // TODO check if token is expired
        // this.delegate.onTokenExpired();
      },
      1000 * 60 * 5,
    );
  }

  public async load() {
    const payload = decodeJwtPayload<{ subdomain?: string }>(this.token);
    if (!payload?.subdomain) {
      console.log('Invalid widget token');
      return;
    }

    const response = await fetch(`${this.appBaseUrl}/api/v2/${payload.subdomain}/widget/init-config`, {
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.token}`,
      },
    });
    if (!response.ok) {
      console.log('Error fetching widget config', response);
      return;
    }
    const userDetails = await response.json();
    this.dialerWidget = new DialerWidget({
      target: document.body,
      props: {
        subdomain: userDetails.subdomain,
        username: userDetails.username,
        password: userDetails.sipPassword,
        displayName: userDetails.name,
        numbers: userDetails.outboundNumbers,
        delegate: this.delegate,
        authToken: this.token,
        appBaseUrl: this.appBaseUrl,
        sipWsUrl: this.sipWsUrl || (userDetails.serverDomain ? `wss://${userDetails.serverDomain}/` : undefined),
      },
    });
  }
}

(window as any).ComcentDialerWidget = ComcentDialerWidget;

function decodeJwtPayload<T>(token: string): T | null {
  const parts = token.split('.');
  if (parts.length < 2) return null;

  try {
    const base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');
    return JSON.parse(atob(padded)) as T;
  } catch {
    return null;
  }
}
