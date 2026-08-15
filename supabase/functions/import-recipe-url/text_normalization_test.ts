import { cleanText } from "./text_normalization.ts";

Deno.test("cleanText decodes decimal numeric HTML entities", () => {
  assertEqual(cleanText("Remove 2&#32;New York steaks"), "Remove 2 New York steaks");
  assertEqual(cleanText("1 teaspoon&#32;salt"), "1 teaspoon salt");
});

Deno.test("cleanText decodes common named HTML entities", () => {
  assertEqual(cleanText("Tom &amp; Jerry"), "Tom & Jerry");
  assertEqual(cleanText("Chef&#39;s knife"), "Chef's knife");
  assertEqual(cleanText("&quot;Marry Me&quot; Chicken"), "\"Marry Me\" Chicken");
  assertEqual(cleanText("1&nbsp;cup flour"), "1 cup flour");
});

Deno.test("cleanText decodes numeric degree and hexadecimal entities", () => {
  assertEqual(cleanText("375&#176;F"), "375°F");
  assertEqual(cleanText("Chef&#x27;s knife"), "Chef's knife");
});

function assertEqual(actual: string, expected: string): void {
  if (actual !== expected) {
    throw new Error(`Expected "${expected}", got "${actual}"`);
  }
}
