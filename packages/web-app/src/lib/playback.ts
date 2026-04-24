export function getPlaybackUrl(subdomain: string, fileName: string) {
  return `/api/v2/${subdomain}/playback/${fileName}`;
}
