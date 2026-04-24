import { svelte, vitePreprocess } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/lib/widgetLoader.ts'),
      name: 'Index',
      fileName: 'index',
    },
    outDir: 'static/widget',
  },
  resolve: {
    alias: {
      $lib: resolve(__dirname, 'src/lib'),
    },
  },
  plugins: [
    svelte({
      preprocess: vitePreprocess(),
    }),
  ],
});
