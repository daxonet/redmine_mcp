import { test, expect } from "@playwright/test";

async function loginAsAdmin(page: import("@playwright/test").Page) {
  await page.goto("http://localhost:3000/login");
  await page.fill("input[name='username']", "admin");
  await page.fill("input[name='password']", "redmineadmin");
  await page.click("input[type='submit']");
  await expect(page.locator("#loggedas")).toContainText("admin");
}

test.describe("MCP Admin", () => {
  test("admin page loads", async ({ page, browserName }) => {
    await loginAsAdmin(page);
    await page.goto("http://localhost:3000/admin/mcp/tokens");
    await expect(page.locator("h2")).toContainText("MCP Authorizations");
    await page.screenshot({
      path: `artifacts/e2e/mcp_admin_${browserName}.png`,
      fullPage: true,
    });
  });

  test("trusted URI section visible", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("http://localhost:3000/admin/mcp/tokens");
    await expect(page.locator("h3").first()).toContainText(
      "Trusted Redirect URIs",
    );
  });

  test("non-admin cannot access admin page", async ({ page }) => {
    await page.goto("http://localhost:3000/login");
    await page.fill("input[name='username']", "jsmith");
    await page.fill("input[name='password']", "jsmith");
    await page.click("input[type='submit']");
    await page.goto("http://localhost:3000/admin/mcp/tokens");
    await expect(page).not.toHaveURL(/admin\/mcp\/tokens/);
  });
});
