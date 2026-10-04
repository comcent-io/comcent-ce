import { sequence } from '@sveltejs/kit/hooks';
import * as Sentry from '@sentry/sveltekit';
import 'dotenv/config';
import { env } from '$env/dynamic/public';

Sentry.init({
  dsn: env.PUBLIC_SENTRY_DSN,
  // The image's tag, set in docker/Dockerfile-web-app.
  release: env.PUBLIC_APP_VERSION || undefined,
  tracesSampleRate: 1,
});

export const handle = sequence(Sentry.sentryHandle());
export const handleError = Sentry.handleErrorWithSentry();
