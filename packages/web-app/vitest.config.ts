import { defineConfig } from 'vitest/config';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { resolve } from 'path';

export default defineConfig({
  plugins: [svelte()],
  test: {
    include: ['src/**/*.{test,spec}.{js,mjs,cjs,ts,mts,cts,jsx,tsx}'],
    globals: true,
    environment: 'jsdom',
    // src/lib/server/dialUtils.ts derives the SIP domain from PUBLIC_BASE_URL
    // when it is imported and throws without it, so its test file failed to
    // load on any machine, CI included, that had not exported one. No test
    // asserts on the value.
    env: {
      PUBLIC_BASE_URL: process.env.PUBLIC_BASE_URL || 'https://example.com',
    },
  },
  resolve: {
    alias: {
      $lib: resolve(__dirname, 'src/lib'),
    },
  },
});
