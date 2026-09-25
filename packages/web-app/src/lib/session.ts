// The browser owns the session cookie: the API returns a session token on
// login, and every later /api/v2 request carries it back as the `idToken`
// cookie. SameSite=Lax keeps other sites from riding the cookie on a
// cross-site POST, which matters because the API accepts the cookie as a
// credential.

import { goto } from '$app/navigation';

const COOKIE_NAME = 'idToken';

function cookieAttributes() {
  const secure = window.location.protocol === 'https:' ? '; Secure' : '';
  return `Path=/; SameSite=Lax${secure}`;
}

export function setSessionToken(token: string) {
  document.cookie = `${COOKIE_NAME}=${token}; ${cookieAttributes()}`;
}

export function clearSessionToken() {
  document.cookie = `${COOKIE_NAME}=; Max-Age=0; ${cookieAttributes()}`;
}

export function hasSessionToken() {
  return document.cookie.split('; ').some((row) => row.startsWith(`${COOKIE_NAME}=`));
}

// Logout is a button handler rather than a /logout URL, so no other site can
// sign a user out by sending them to a link.
export async function logout() {
  clearSessionToken();
  await goto('/login', { invalidateAll: true });
}
