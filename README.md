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

## Publish on GitHub Pages

A deployment workflow runs on pushes to `main` and can be run manually under Actions. In the repository's Settings → Pages, select **GitHub Actions** as the source once. The workflow deploys the production bundle to GitHub Pages. The relative Vite base supports both GitHub Pages subpaths and Netlify.

## DevOps and AWS platform

The repository now includes an AWS delivery platform in code:

- Terraform for private S3 + CloudFront/OAC, encrypted/versioned state, GitHub OIDC, scoped IAM, security headers, access logs, CloudWatch alarms/dashboard, SNS, and cost-budget notifications.
- CI with production-browser tests, release/rollback tests, dependency auditing, secret scanning, and Terraform configuration/security tests. Actions are pinned; Dependabot tracks updates.
- Serialized AWS deployments with immutable release prefixes, checksummed stored artifacts, live HTTP/browser checks, and automatic restoration of prior HTML on post-switch failure.
- Manual rollback to a completed Git SHA without rebuilding.

Start with **[Connect GitHub to AWS](docs/aws-setup.md)**. It uses AWS CloudShell and OIDC; no AWS keys are pasted into chat or GitHub. Provisioning creates billable resources. AWS deployment stays skipped until repository variables are supplied. This repository's configuration is not evidence of a running AWS site.

- [Training sandbox requirements](docs/sandbox.md)
- [Architecture and tradeoffs](docs/architecture.md)
- [Operations and recovery](docs/operations.md)
- [Portfolio claims and deployment evidence](docs/evidence.md)

### Local quality checks

```bash
npm ci
npm audit --audit-level=high
npm run test:release
npm run build
npx playwright install --with-deps chromium
npm test

# Terraform 1.12.2; tests use mock providers and create no AWS resources.
terraform fmt -check -recursive infra
terraform -chdir=infra/bootstrap init -backend=false -lockfile=readonly
terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/terraform init -backend=false -lockfile=readonly
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform test
```

On a machine with an existing system Chromium, use `CHROMIUM_PATH=/path/to/chromium npm test` instead of downloading Playwright's browser. To test a live deployment, set `PLAYWRIGHT_BASE_URL=https://YOUR_SITE` and `EXPECTED_RELEASE=FULL_COMMIT_SHA`.
