type FetchLike = typeof fetch;

type RequestOptions = RequestInit & {
  fetchFn?: FetchLike;
};

export type JsonResult<T> =
  | {
      ok: true;
      status: number;
      data: T;
      response: Response;
    }
  | {
      ok: false;
      status: number;
      error: string;
      data: unknown;
      response?: Response;
    };

function getErrorMessage(data: unknown, fallback: string) {
  if (!data || typeof data !== 'object') return fallback;

  const record = data as Record<string, unknown>;
  const candidates = [record.error, record.errorMessage, record.message];

  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.trim() !== '') {
      return candidate;
    }
  }

  if (Array.isArray(record.errors) && typeof record.errors[0] === 'string') {
    return record.errors[0];
  }

  return fallback;
}

async function parseJson(response: Response) {
  const contentType = response.headers.get('content-type') ?? '';
  if (!contentType.includes('application/json')) {
    return null;
  }

  try {
    return await response.json();
  } catch {
    return null;
  }
}

async function requestJson<T>(
  input: RequestInfo | URL,
  options: RequestOptions = {},
): Promise<JsonResult<T>> {
  const { fetchFn = fetch, ...init } = options;

  try {
    const response = await fetchFn(input, init);
    const data = await parseJson(response);

    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        error: getErrorMessage(data, response.statusText || 'Request failed'),
        data,
        response,
      };
    }

    return {
      ok: true,
      status: response.status,
      data: (data ?? {}) as T,
      response,
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      error: error instanceof Error ? error.message : 'Network request failed',
      data: null,
    };
  }
}

function withJsonHeaders(headers: HeadersInit | undefined) {
  const merged = new Headers(headers);
  if (!merged.has('Content-Type')) {
    merged.set('Content-Type', 'application/json');
  }
  return merged;
}

export function getJson<T>(input: RequestInfo | URL, options: RequestOptions = {}) {
  return requestJson<T>(input, options);
}

export function postJson<T>(input: RequestInfo | URL, body: unknown, options: RequestOptions = {}) {
  return requestJson<T>(input, {
    ...options,
    method: 'POST',
    headers: withJsonHeaders(options.headers),
    body: JSON.stringify(body),
  });
}

export function putJson<T>(input: RequestInfo | URL, body: unknown, options: RequestOptions = {}) {
  return requestJson<T>(input, {
    ...options,
    method: 'PUT',
    headers: withJsonHeaders(options.headers),
    body: JSON.stringify(body),
  });
}

export function deleteJson<T>(input: RequestInfo | URL, options: RequestOptions = {}) {
  return requestJson<T>(input, {
    ...options,
    method: 'DELETE',
  });
}
