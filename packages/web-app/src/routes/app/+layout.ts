import { loadSignedInUser } from '$lib/signedIn';
import type { LayoutLoad } from './$types';

// Everything under /app reads from the API, which is only reachable from the
// browser, so these pages render there.
export const ssr = false;

export const load: LayoutLoad = ({ fetch }) => loadSignedInUser(fetch);
