import { expect, test } from "bun:test";
import { goalLiterals } from "../src/uiloop.ts";

test("goal literals: numbers and quoted text, deduped", () => {
  expect(goalLiterals("change the default from last 7 days to last 30 days")).toEqual(["7", "30"]);
  expect(goalLiterals(`rename the page to "Q3 Overview" and set 30`)).toEqual(["Q3 Overview", "30"]);
});
