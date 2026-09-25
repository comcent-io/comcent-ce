import adapter from '@sveltejs/adapter-node';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  // Consult https://kit.svelte.dev/docs/integrations#preprocessors
  // for more information about preprocessors
  preprocess: vitePreprocess(),

  // Svelte 5 runes everywhere in our code, so a component written the old
  // way fails to compile. Libraries in node_modules keep their own mode.
  vitePlugin: {
    dynamicCompileOptions({ filename }) {
      if (!filename.includes('node_modules')) {
        return { runes: true };
      }
    },
  },

  kit: {
    // adapter-auto only supports some environments, see https://kit.svelte.dev/docs/adapter-auto for a list.
    // If your environment is not supported or you settled on a specific environment, switch out the adapter.
    // See https://kit.svelte.dev/docs/adapters for more information about adapters.
    adapter: adapter(),
    // The app is served behind Traefik on several hosts (custom domains), so
    // the origin check stays off. '*' is the SvelteKit 2 form of the old
    // `checkOrigin: false`.
    csrf: {
      trustedOrigins: ['*'],
    },
  },
};

export default config;
