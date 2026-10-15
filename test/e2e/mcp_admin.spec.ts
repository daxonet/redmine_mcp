import { test, expect } from "@playwright/test";

async function loginAsAdmin(page: import("@playwright/test").Page) {
  await page.goto("http://localhost:3000/login");
  await page.fill("input[name='username']", "admin");
  await page.fill("input[name='password']", "redmineadmin");
  await page.click("input[type='submit']");
  await page.waitForURL("**/my/page");
}

test.describe("MCP Admin", () => {
  test("admin page loads", async ({ page, browserName }) => {
    await loginAsAdmin(page);
    await page.goto("http://localhost:3000/admin/mcp/tokens");
    await expect(page.locator("h2")).toContainText("Applications");
    await page.screenshot({
      path: `artifacts/e2e/mcp_admin_${browserName}.png`,
      fullPage: true,
    });
  });

  test("trusted URLs live in plugin settings", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("http://localhost:3000/settings/plugin/redmine_mcp");
    await expect(page.locator("textarea[name='settings[allowed_redirect_uris]']")).toBeVisible();
  });

  test("non-admin cannot access admin page", async ({ page }) => {
    await page.goto("http://localhost:3000/login");
    await page.fill("input[name='username']", "jsmith");
    await page.fill("input[name='password']", "jsmith");
    await page.click("input[type='submit']");
    await page.goto("http://localhost:3000/admin/mcp/tokens");
    await expect(page.locator("#content")).toContainText("not authorized");
  });
});
