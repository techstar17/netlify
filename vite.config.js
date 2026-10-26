import { defineConfig } from 'vite';

export default defineConfig({
  base: process.env.ASSET_BASE || './',
  plugins: [{
    name: 'frame-release-identity',
    transformIndexHtml() {
      return [{
        tag: 'meta',
        attrs: { name: 'frame-release', content: process.env.RELEASE_ID || 'development' },
        injectTo: 'head',
      }];
    },
  }],
});
