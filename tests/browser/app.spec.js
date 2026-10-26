import { test, expect } from '@playwright/test';

test('search, details, persistent watchlist, and removal', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /THE LAST FRONTIER/, level: 1 })).toBeVisible();
  if (process.env.EXPECTED_RELEASE) {
    await expect(page.locator('meta[name="frame-release"]')).toHaveAttribute('content', process.env.EXPECTED_RELEASE);
  }
  await page.getByRole('textbox', { name: 'Search titles' }).fill('BLUE');
  await expect(page.getByRole('button', { name: /^View / })).toHaveCount(1);
  await page.getByRole('button', { name: 'View BLUE HORIZON' }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: '+ My List', exact: true }).click();
  await page.keyboard.press('Escape');
  await page.reload();
  await page.getByRole('button', { name: /^My List/ }).click();
  await expect(page.getByRole('button', { name: 'View BLUE HORIZON' })).toHaveCount(1);
  await page.getByRole('button', { name: 'Remove from My List' }).click();
  await expect(page.getByRole('heading', { name: 'Make room for your favorites.' })).toBeVisible();
  expect(errors).toEqual([]);
});

test('genres and empty search results', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Documentary', exact: true }).click();
  await expect(page.getByRole('button', { name: /^View / })).toHaveCount(2);
  await page.getByRole('textbox', { name: 'Search titles' }).fill('does-not-exist');
  await expect(page.getByRole('heading', { name: 'No titles found.' })).toBeVisible();
});

test('sample media actually plays', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: /Play now/ }).click();
  const video = page.locator('video');
  await expect(video).toBeVisible();
  await expect.poll(() => video.evaluate(v => v.currentTime), { timeout: 20000 }).toBeGreaterThan(0.2);
  expect(await video.evaluate(v => v.error)).toBeNull();
});

test('mobile layout and bundled images', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByRole('button', { name: 'Movies', exact: true }).click();
  await expect(page.getByRole('button', { name: /^View / })).toHaveCount(8);
  await expect.poll(() => page.locator('img').evaluateAll(imgs => imgs.every(i => i.complete && i.naturalWidth > 0))).toBe(true);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
