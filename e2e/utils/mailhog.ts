import { expect, type APIRequestContext } from '@playwright/test';

const mailhogApiBaseUrl =
  process.env.E2E_MAILHOG_API_BASE_URL ||
  `http://127.0.0.1:${process.env.E2E_MAILHOG_HTTP_PORT || '58025'}/api/v2`;

type MailHogMessage = {
  Content: {
    Body: string;
    Headers?: Record<string, string[]>;
  };
  MIME?: {
    Parts?: Array<{
      Body?: string;
    }>;
  };
};

type MailHogSearchResponse = {
  items: MailHogMessage[];
};

export async function waitForVerificationLink(
  request: APIRequestContext,
  email: string,
): Promise<string> {
  const messages = await waitForMessages(request, email, 1);
  const link = extractVerificationLink(messages);

  if (!link) {
    throw new Error(`Verification email was not received for ${email}`);
  }

  return link;
}

export async function waitForInvitationLink(
  request: APIRequestContext,
  email: string,
): Promise<string> {
  const messages = await waitForMessages(request, email, 1);
  const link = extractInvitationLink(messages);

  if (!link) {
    throw new Error(`Invitation email was not received for ${email}`);
  }

  return link;
}

export async function waitForMessageCount(
  request: APIRequestContext,
  email: string,
  count: number,
): Promise<void> {
  await waitForMessages(request, email, count);
}

async function waitForMessages(
  request: APIRequestContext,
  email: string,
  minimumCount: number,
): Promise<MailHogMessage[]> {
  for (let attempt = 0; attempt < 30; attempt++) {
    const response = await request.get(
      `${mailhogApiBaseUrl}/search?kind=to&query=${encodeURIComponent(email)}`,
      { failOnStatusCode: false },
    );

    expect(response.ok()).toBeTruthy();

    const data = (await response.json()) as MailHogSearchResponse;
    if (data.items.length >= minimumCount) {
      return data.items;
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  throw new Error(`Expected at least ${minimumCount} email(s) for ${email}`);
}

function extractVerificationLink(messages: MailHogMessage[]): string | null {
  return extractLink(messages, /https?:\/\/[^\s"]+\/auth\/verify-email\/[^\s"<]+/);
}

function extractInvitationLink(messages: MailHogMessage[]): string | null {
  return extractLink(messages, /https?:\/\/[^\s"]+\/invitation\/[^\s"<]+/);
}

function extractLink(messages: MailHogMessage[], pattern: RegExp): string | null {
  for (const message of messages) {
    const bodies = [
      message.Content.Body,
      ...(message.MIME?.Parts?.map((part) => part.Body || '') || []),
    ];

    for (const body of bodies) {
      const normalizedBody = normalizeMailHogBody(body);
      const match = normalizedBody.match(pattern);

      if (match) {
        return match[0];
      }
    }
  }

  return null;
}

function normalizeMailHogBody(body: string): string {
  return decodeQuotedPrintable(decodeMailHogBody(body));
}

function decodeMailHogBody(body: string): string {
  return body.replace(/\r\n/g, '\n');
}

function decodeQuotedPrintable(body: string): string {
  return body
    .replace(/=\n/g, '')
    .replace(/=([A-F0-9]{2})/gi, (_, hex: string) =>
      String.fromCharCode(Number.parseInt(hex, 16)),
    );
}
