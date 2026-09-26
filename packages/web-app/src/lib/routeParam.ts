import { page } from '$app/state';

/**
 * A parameter of the current route that is always there, like `subdomain`
 * anywhere under /app/[subdomain]. SvelteKit 2 types every route parameter as
 * possibly undefined, since `page` is shared by all routes.
 */
export function routeParam(name: string): string {
  const value = (page.params as Record<string, string | undefined>)[name];
  if (value === undefined) {
    throw new Error(`Route parameter "${name}" is missing`);
  }
  return value;
}
