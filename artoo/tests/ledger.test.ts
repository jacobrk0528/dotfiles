import { expect, test } from "bun:test";
import { assemble, columnLetter, fitRow, lastFilledRow, layoutOf, mismatches, ownerColumns, parseCsv, regionMismatches, rowKeys, sameCell, sheetBrief, toSheet, tomorrowLike } from "../src/workflows/ledger.ts";

const csv = [
  '"Date","Description","Category","Withdrawl","Deposit","Ignore","",""',
  '"9/25/24","Circle K","BS","$0.87","","FALSE","",""',
  '"8/31/26","Publix","Food","$50.56","","FALSE","",""',
  '"9/1/26","Payment, ""thanks""","","","$1,291.66","TRUE","",""',
  '"","","","","","FALSE","",""',
  '"","","","","","FALSE","",""',
].join("\n");
const sheet = toSheet("Credit Card - Discover", parseCsv(csv));

test("the CSV grid keeps quoted commas and quotes, and line N is sheet row N", () => {
  expect(sheet.header).toEqual(["Date", "Description", "Category", "Withdrawl", "Deposit", "Ignore"]);
  expect(sheet.rows[2]).toEqual(["9/1/26", 'Payment, "thanks"', "", "", "$1,291.66", "TRUE"]);
  // Header is row 1, so the third data line is row 4. Blank rows with an unticked box don't count.
  expect(lastFilledRow(sheet)).toBe(4);
  expect(lastFilledRow(toSheet("Empty", parseCsv('"Date","Description"\n"",""')))).toBe(1);
});

test("category and checkbox columns are the owner's and are never filled", () => {
  const skip = ownerColumns(sheet);
  expect([...skip].sort()).toEqual([2, 5]);
  const row = fitRow({ cells: [" 9/2/26 ", "Chick Fil A", "Food", "15.82", "", "TRUE", "extra"], source: "x" }, sheet, skip);
  expect(row?.cells).toEqual(["9/2/26", "Chick Fil A", "", "15.82", "", ""]);
  // A row with nothing but a date is not a transaction.
  expect(fitRow({ cells: ["9/2/26", "", "Food"], source: "x" }, sheet, skip)).toBeNull();
});

test("a row is typed as values and tabs, with Enter straight after the last value", () => {
  expect(rowKeys(["9/8/26", "SoFi Plus", "", "10.00", "", ""])).toEqual(["9/8/26", "{tab}", "SoFi Plus", "{tab}", "{tab}", "10.00", "{enter}"]);
  expect(rowKeys(["9/8/26", "From Savings", "", "", "425.00", ""])).toEqual(["9/8/26", "{tab}", "From Savings", "{tab}", "{tab}", "{tab}", "425.00", "{enter}"]);
});

test("what the sheet shows is compared with what was typed, format aside", () => {
  expect(sameCell("1722.00", "$1,722.00")).toBe(true);
  expect(sameCell("10.00", "$10.01")).toBe(false);
  expect(sameCell("9/8/26", "09/08/2026")).toBe(true);
  expect(sameCell("9/8/26", "9/9/26")).toBe(false);
  expect(sameCell("Amazon", "amazon")).toBe(true);
  // Autocomplete finishing a word differently is exactly what the check has to catch.
  expect(sameCell("Amazon", "Amazon Prime")).toBe(false);
});

test("mismatches name the row, the column and both values", () => {
  const typed = [
    { cells: ["8/31/26", "Publix", "", "50.56", "", ""], source: "" },
    { cells: ["9/1/26", "Payment", "", "", "1291.66", ""], source: "" },
  ];
  expect(mismatches(sheet, 3, typed)).toEqual(['row 4 Description: shows "Payment, "thanks"", typed "Payment"']);
  expect(mismatches(sheet, 3, [typed[0]!])).toEqual([]);
  // Typed onto rows that turned out empty: every cell is reported.
  expect(mismatches(sheet, 5, [typed[0]!])).toHaveLength(3);
});

test("the model is shown the end of the settled block, the provisional rows and the sheet's wording", () => {
  const brief = sheetBrief(sheet);
  expect(brief.last_settled_row).toBe(4);
  expect(brief.settled_rows.map((r) => r.row)).toEqual([2, 3, 4]);
  expect(brief.provisional_rows).toEqual([]);
  expect(brief.known_descriptions).toContain("Publix (1)");
});

// Settled rows 2-3, a gap at row 4, then two rows typed while pending (5-6).
const gapped = toSheet("Credit Card - Chase", parseCsv([
  '"Date","Description","Category","Withdrawl","Deposit","Ignore"',
  '"7/20/26","Publix","Food","$20.00","","FALSE"',
  '"7/22/26","QT","Gas","$30.00","","FALSE"',
  '"","","","","","FALSE"',
  '"7/29/26","Payment","Transfer","","$46.53","FALSE"',
  '"7/29/26","Chick Fil A","Food","$12.00","","FALSE"',
  '"","","","","","FALSE"',
].join("\n")));
const found = (cells: string[], from_row = 0) => ({ cells, source: cells.join(" "), from_row });

test("a blank row near the end splits the settled block from the rows typed while pending", () => {
  expect(layoutOf(gapped)).toEqual({
    settledEnd: 3, writeStart: 4, last: 6,
    provisional: [{ row: 5, cells: ["7/29/26", "Payment", "Transfer", "", "$46.53", "FALSE"] }, { row: 6, cells: ["7/29/26", "Chick Fil A", "Food", "$12.00", "", "FALSE"] }],
  });
  // No gap: writing starts on the first empty row.
  expect(layoutOf(sheet)).toEqual({ settledEnd: 4, writeStart: 5, provisional: [], last: 4 });
});

test("posted rows close the gap and keep the owner's category; pending rows follow a blank row, dated tomorrow", () => {
  const lines = assemble(gapped, layoutOf(gapped),
    [found(["7/30/26", "Payment", "", "", "46.53", ""], 5), found(["7/31/26", "Chick Fil A", "Other", "13.50", "", ""], 6), found(["8/2/26", "Walmart", "Groceries", "28.42", "", ""])],
    [found(["Aug 3", "Amazon", "", "9.99", "", ""])], "8/5/26");
  expect(lines.map((l) => l?.cells ?? null)).toEqual([
    ["7/30/26", "Payment", "Transfer", "", "46.53", ""],      // category carried from row 5
    ["7/31/26", "Chick Fil A", "Food", "13.50", "", ""],      // the owner's "Food", not the model's "Other"
    ["8/2/26", "Walmart", "", "28.42", "", ""],               // new: category left for the owner
    null,
    ["8/5/26", "Amazon", "", "9.99", "", ""],                 // pending: tomorrow's date
  ]);
  expect(lines[4]?.pending).toBe(true);
  // Nothing pending: no blank row either.
  expect(assemble(gapped, layoutOf(gapped), [found(["7/30/26", "Payment", "", "", "46.53", ""], 5)], [], "8/5/26")).toHaveLength(1);
});

test("the rewritten region is checked blanks and all, down to the old last row", () => {
  const layout = layoutOf(gapped);
  // Unchanged sheet against a plan that moves the two rows up over the gap: everything from the gap differs.
  const lines = assemble(gapped, layout, [found(["7/29/26", "Payment", "", "", "46.53", ""], 5), found(["7/29/26", "Chick Fil A", "", "12.00", "", ""], 6)], [], "8/5/26");
  const wrong = regionMismatches(gapped, layout.writeStart, lines, layout.last);
  expect(wrong).toContain('row 4 Description: shows "", should be "Payment"');
  expect(wrong).toContain('row 6 Description: shows "Chick Fil A", should be ""');
  // A sheet that already looks like the plan has nothing to report.
  const done = toSheet("x", parseCsv([
    '"Date","Description","Category","Withdrawl","Deposit","Ignore"',
    '"7/20/26","Publix","Food","$20.00","","FALSE"', '"7/22/26","QT","Gas","$30.00","","FALSE"',
    '"7/29/26","Payment","Transfer","","$46.53","FALSE"', '"7/29/26","Chick Fil A","Food","$12.00","","FALSE"', '"","","","","","FALSE"',
  ].join("\n")));
  expect(regionMismatches(done, 4, lines, 6)).toEqual([]);
});

test("tomorrow is written the way the sheet writes dates", () => {
  const now = new Date(2026, 9, 4);
  expect(tomorrowLike("9/8/26", now)).toBe("10/5/26");
  expect(tomorrowLike("09/08/2026", now)).toBe("10/05/2026");
  expect(tomorrowLike("", new Date(2026, 11, 31))).toBe("1/1/27");
});

test("column letters", () => {
  expect([0, 4, 25, 26, 27].map(columnLetter)).toEqual(["A", "E", "Z", "AA", "AB"]);
});

test("stray punctuation on a blank row is not a filled row, and a category the sheet fills itself is not a mismatch", () => {
  const stray = toSheet("Emergency Fund", parseCsv([
    '"Date","Description","Category","Withdrawl","Deposit","Ignore"',
    '"8/31/26","Interest","Income","","$29.94","FALSE"',
    '"","","`","","",""',
  ].join("\n")));
  expect(lastFilledRow(stray)).toBe(2);
  expect(layoutOf(stray).writeStart).toBe(3);
  // Typed 9/30 interest with no category; the sheet's own formula put "Income" there.
  const after = toSheet("Emergency Fund", parseCsv([
    '"Date","Description","Category","Withdrawl","Deposit","Ignore"',
    '"8/31/26","Interest","Income","","$29.94","FALSE"',
    '"9/30/26","Interest","Income","","$28.33","FALSE"',
  ].join("\n")));
  const lines = [{ cells: ["9/30/26", "Interest", "", "", "28.33", ""], source: "" }];
  expect(regionMismatches(after, 3, lines, 2)).toEqual([]);
  // A wrong amount is still caught.
  expect(regionMismatches(after, 3, [{ cells: ["9/30/26", "Interest", "", "", "28.34", ""], source: "" }], 2)).toHaveLength(1);
});
