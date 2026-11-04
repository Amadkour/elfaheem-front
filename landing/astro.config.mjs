import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://nextbrain.site',
  output: 'static',
  trailingSlash: 'always',
  compressHTML: true,
  build: { format: 'directory', inlineStylesheets: 'always' },
  devToolbar: { enabled: false },
});
