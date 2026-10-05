import { loadSignedInUser } from '$lib/signedIn';
import type { LayoutLoad } from './$types';

// An invitation is opened signed in, as the address it was sent to. The API
// is only reachable from the browser, so the page renders there.
export const ssr = false;

export const load: LayoutLoad = ({ fetch }) => loadSignedInUser(fetch);
