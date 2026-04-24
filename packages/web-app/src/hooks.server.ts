import { sequence } from '@sveltejs/kit/hooks';
import * as Sentry from '@sentry/sveltekit';
import type { Handle } from '@sveltejs/kit';
import 'dotenv/config';
import { env } from '$env/dynamic/public';
import { ensureIsOrgMemberWithRole } from '$lib/auth';
import { ensureAuthenticated } from '$lib/auth';

Sentry.init({
  dsn: env.PUBLIC_SENTRY_DSN,
  tracesSampleRate: 1,
});

const handle: Handle = sequence(Sentry.sentryHandle(), async ({ event, resolve }) => {
  // List of routes that require authentication
  const protectedRoutes = [
    'call-story',
    'campaign-groups',
    'campaign-scripts',
    'members',
    'numbers',
    'payments',
    'sip-trunks',
    'presence',
    'settings',
    'voice-bots',
    'queues',
  ];

  // Check if the current route needs protection
  const pathParts = event.url.pathname.split('/').filter(Boolean);
  const isAppRoute = pathParts[0] === 'app';
  const routeName = pathParts[2]; // The route name comes after /app/[subdomain]

  // If it's a protected route under /app/[subdomain], check for authentication
  if (isAppRoute && routeName && protectedRoutes.includes(routeName)) {
    const subdomain = pathParts[1]; // The subdomain is the second part after /app/

    if (subdomain) {
      const user = await ensureAuthenticated(event.cookies);
      await ensureIsOrgMemberWithRole(user, subdomain, 'ADMIN');
    }
  }

  return resolve(event);
});

export { handle };
export const handleError = Sentry.handleErrorWithSentry();
