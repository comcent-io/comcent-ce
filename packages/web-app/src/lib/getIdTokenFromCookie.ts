export function getIdTokenFromCookie() {
  const cookie = document.cookie.split('; ').find((row) => row.startsWith('idToken'));
  if (cookie) {
    return cookie.split('=')[1];
  }
}
