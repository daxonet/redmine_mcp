import { test } from "@playwright/test";

test.describe("Initialize", () => {
  test("initialize admin password", async ({ page }) => {
    await page.goto("http://localhost:3000/");
    await page.click("a:text('Sign in')");
    await page.fill("input[name='username']", "admin");
    await page.fill("input[name='password']", "admin");
    await page.click("input[type='submit']");

    // Change password on first login if prompted
    if (await page.locator("input[name='password']").isVisible()) {
      await page.fill("input[name='password']", "redmineadmin");
      await page.fill(
        "input[name='new_password_confirmation']",
        "redmineadmin",
      );
      await page.click("input[type='submit']");
    }

    await page.screenshot({
      path: "artifacts/e2e/initialize.png",
      fullPage: true,
    });
  });
});
