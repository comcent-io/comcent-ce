import { env } from '$env/dynamic/private';
import { getJson, postJson, type JsonResult } from '$lib/http';

const INTERNAL_API_BASE_URL = env.INTERNAL_API_BASE_URL || 'http://server:4000';

function toInternalUrl(path: string) {
  return new URL(path, INTERNAL_API_BASE_URL).toString();
}

function withAuthorization(idToken: string, headers?: HeadersInit) {
  const merged = new Headers(headers);
  merged.set('authorization', `Bearer ${idToken}`);
  return merged;
}

export function getAuthedJson<T>(
  path: string,
  idToken: string,
  fetchFn: typeof fetch = fetch,
): Promise<JsonResult<T>> {
  return getJson<T>(toInternalUrl(path), {
    fetchFn,
    headers: withAuthorization(idToken),
  });
}

export function getInternalJson<T>(
  path: string,
  fetchFn: typeof fetch = fetch,
): Promise<JsonResult<T>> {
  return getJson<T>(toInternalUrl(path), { fetchFn });
}

export function postAuthedJson<T>(
  path: string,
  idToken: string,
  body: unknown,
  fetchFn: typeof fetch = fetch,
): Promise<JsonResult<T>> {
  return postJson<T>(toInternalUrl(path), body, {
    fetchFn,
    headers: withAuthorization(idToken),
  });
}

export function postBearerJson<T>(
  path: string,
  bearerToken: string,
  body: unknown,
  fetchFn: typeof fetch = fetch,
): Promise<JsonResult<T>> {
  return postJson<T>(toInternalUrl(path), body, {
    fetchFn,
    headers: withAuthorization(bearerToken),
  });
}

export function postInternalJson<T>(
  path: string,
  body: unknown,
  fetchFn: typeof fetch = fetch,
): Promise<JsonResult<T>> {
  return postJson<T>(toInternalUrl(path), body, {
    fetchFn,
  });
}
