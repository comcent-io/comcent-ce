import type { APIRequestContext, Page } from '@playwright/test';

const baseUrl = process.env.PUBLIC_ROOT_URL || 'http://localhost:4173';

export async function loginApi(
  request: APIRequestContext,
  params: { email: string; password: string },
) {
  const response = await request.post(`${baseUrl}/api/v2/auth/login`, {
    data: {
      email: params.email,
      password: params.password,
    },
    failOnStatusCode: false,
  });

  if (!response.ok()) {
    throw new Error(
      `Unable to login ${params.email}: ${response.status()} ${await response.text()}`,
    );
  }

  const body = await response.json();
  if (!body.token) {
    throw new Error(`Login for ${params.email} did not return a token`);
  }

  return body.token as string;
}

export async function fetchRecordingBytes(params: {
  request: APIRequestContext;
  token: string;
  subdomain: string;
  callStoryId: string;
  fileName: string;
  timeoutMs?: number;
}) {
  const deadline = Date.now() + (params.timeoutMs ?? 45_000);
  let lastError = '';

  while (Date.now() < deadline) {
    const response = await params.request.get(
      `${baseUrl}/api/v2/${params.subdomain}/call-story/${params.callStoryId}/record/${params.fileName}`,
      {
        headers: {
          Authorization: `Bearer ${params.token}`,
        },
        maxRedirects: 5,
        failOnStatusCode: false,
      },
    );

    if (response.ok()) {
      return response.body();
    }

    lastError = `${response.status()} ${await response.text()}`;

    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }

  throw new Error(`Unable to fetch recording ${params.fileName}: ${lastError}`);
}

export async function createQueueViaApi(params: {
  page: Page;
  subdomain: string;
  name: string;
  extension?: string;
  wrapUpTime?: number;
  rejectDelayTime?: number;
  maxNoAnswers?: number;
}) {
  const response = await params.page
    .context()
    .request.post(`${baseUrl}/api/v2/${params.subdomain}/queues`, {
      data: {
        name: params.name,
        extension: params.extension ?? '',
        wrapUpTime: params.wrapUpTime ?? 30,
        rejectDelayTime: params.rejectDelayTime ?? 30,
        maxNoAnswers: params.maxNoAnswers ?? 2,
      },
      failOnStatusCode: false,
    });

  if (!response.ok()) {
    throw new Error(
      `Failed to create queue: ${response.status()} ${await response.text()}`,
    );
  }

  return response.json();
}

export async function addQueueMemberViaApi(params: {
  page: Page;
  subdomain: string;
  queueId: string;
  userId: string;
}) {
  const response = await params.page
    .context()
    .request.post(
      `${baseUrl}/api/v2/${params.subdomain}/queues/${params.queueId}/members`,
      {
        data: { userId: params.userId },
        failOnStatusCode: false,
      },
    );

  if (!response.ok()) {
    throw new Error(
      `Failed to add queue member: ${response.status()} ${await response.text()}`,
    );
  }

  return response.json();
}
