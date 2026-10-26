# FRAME

A responsive Netflix-inspired streaming demo built from scratch with React and Vite. Features a cinematic featured title, movie collections, genre filters, search, movie details, local watchlists, and a working HTML5 sample player.

## Develop

Requires Node.js 22.12+ (Node 24 is supported).

```sh
export npm_config_cache=/workspace/.npm-cache
npm ci
npm run dev
```

`npm run build` produces the deployable `dist/` directory. `npm run preview` serves the production build. Netlify can use build command `npm run build` and publish directory `dist`.

All imagery, fonts, and the sample video are bundled, so normal use does not require third-party requests. Watchlists are stored in the current browser's localStorage. Catalog titles, years, descriptions, and durations are fictional. Each play action shows the same one-minute sample; this is a frontend prototype with no authentication, payments, backend, or real streaming catalog.

## Asset credits

Photography is sourced from Start Bootstrap's Clean Blog, Grayscale, and Landing Page template assets (MIT-licensed template repositories):
- https://github.com/StartBootstrap/startbootstrap-clean-blog
- https://github.com/StartBootstrap/startbootstrap-grayscale
- https://github.com/StartBootstrap/startbootstrap-landing-page

DM Sans and Barlow Condensed are from Google Fonts and distributed under the SIL Open Font License (included in `public/fonts`).

Sample video: Big Buck Bunny by the Blender Foundation, licensed CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/), sourced from https://github.com/mediaelement/mediaelement-files. Original film: https://peach.blender.org/ . This bundled clip is the upstream one-minute sample, unmodified.
