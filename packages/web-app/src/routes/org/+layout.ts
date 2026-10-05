import { loadSignedInUser } from '$lib/signedIn';
import type { LayoutLoad } from './$types';

// The organization list and create page. The API is only reachable from the
// browser, so they render there.
export const ssr = false;

export const load: LayoutLoad = ({ fetch }) => loadSignedInUser(fetch);
