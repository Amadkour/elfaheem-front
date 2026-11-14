import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://alfheemacademy.com',
  output: 'static',
  trailingSlash: 'always',
  compressHTML: true,
  build: { format: 'directory', inlineStylesheets: 'always' },
  devToolbar: { enabled: false },
});
