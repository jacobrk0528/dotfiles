You are picking up an in-progress project from an earlier session. Read all of this, absorb it, and reply with exactly "ok" and nothing else. Do not run tools, do not start work, do not summarise. I will give you instructions in my next message.

# What I want built next

A program that keeps my "Checkbook" Google Sheet in sync with my bank and card accounts automatically, using **Plaid** for transaction data and the **Google Sheets API with a service account** for reading and writing the sheet. It replaces the browser-driving approach described below. I have Plaid credentials and will create a service account and share the sheet with it.

Hard rules: never move money, never pay anything, never do anything that costs me money, never expose or print secrets. Secrets live in `~/dotfiles/.env` and are loaded through `~/dotfiles/scripts/dotenv.sh`; never read or print their values and never add per-tool token files. Use Bun, not Node or npm.

# The existing code: artoo

`~/dotfiles/artoo` is my personal computer-use agent (Bun + TypeScript, CLI `artoo`, run from a Quickshell dock prompt on Hyprland). It drives Brave over the DevTools protocol on port 9222. Nothing from this work is committed yet. `bun test` passes 83 tests; `bun run typecheck` is clean.

The relevant part is `src/workflows/ledger.ts`, the "checkbook workflow" (`artoo ledger [--dry-run] "<account>"`, also reachable from the dock: requests about entering an account's transactions route to it). It:
1. picks the sheet tab and the bank page from the request (one quick model call);
2. reads the tab as CSV from inside the sheet page (`/gviz/tq?tqx=out:csv&headers=1&sheet=<name>`);
3. reads the bank page text from the DOM, clicking through to the account and widening the date range if needed (each click checked by a policy judge so it can only navigate);
4. makes one model call for the rows to add, in the tab's own format and wording;
5. asks me once, types the rows through the browser, then re-reads and compares cell by cell.

Pure, tested helpers there that are worth reusing: `parseCsv`, `toSheet`, `lastFilledRow`, `layoutOf` (finds the gap and the pending section), `assemble`, `regionMismatches`, `sameCell`, `tomorrowLike`, `ownerColumns`, `checkboxColumns`, `rowKeys`, `sheetBrief`. Tests are in `tests/ledger.test.ts`. `README.md` has a "Checkbook workflow" section.

Lessons that the new design should make impossible:
- The gviz CSV export **omits completely empty rows and hidden rows**, so "CSV line N = sheet row N" is false on some tabs. This caused a real overwrite of one row (since restored). The Sheets API avoids this.
- Claude Code's permission classifier intermittently blocks browser-driven edits to the sheet ("Modify Shared Resources"). API writes from a proper program I run myself avoid this.
- Bank web pages are unreliable sources: Capital One's transaction list silently omitted a whole week (Jul 3 to 9, 2026) that its own CSV export contains.

# The sheet

Google Sheet "Checkbook", id `1lkyybaYNABGwCZnTt60oGNPlrLO1i6L6qHof5yZAsmA`.

Ledger tabs all share the columns: `Date | Description | Category | Withdrawl | Deposit | Ignore` (Withdrawl is spelled that way; Ignore is a checkbox).

| Tab | Account |
|---|---|
| Checking - Sofi | SoFi checking, ends 0628 |
| Savings - Sofi | SoFi savings, ends 4995 |
| Emergency Fund - Sofi | SoFi vault "Emergency Fund" |
| Splurge - Sofi | SoFi vault "Splurge" (current vault only has history from 9/1/26) |
| Car Insurance - Sofi | SoFi vault "Car Insurance" |
| IRA Vault - Sofi | SoFi vault "Roth IRA" |
| Car Fund - Sofi | SoFi vault "Car" |
| House - Sofi | SoFi vault "House", closed; the tab is hidden |
| Credit Card - Chase | Chase Freedom Unlimited, ends 8988 |
| Credit Card - Discover | Capital One card ends 8691. It was a Discover card until about 7/2/25, when it moved to Capital One. Capital One has no data before that. |

Other tabs (Dashboard, Transactions Pivot, Combind Data, Totals, Settings, IRA, Roth IRA, Brokerage, Market Caps, Sectors, Diocese, Wish List, Life, Checking - SS, Investment Projections, Master Dashboard) are mine or derived; leave them alone. "Combind Data" aggregates the ledger tabs by formula.

## My conventions

- **Layout of a tab:** settled transactions in one block, then exactly one blank row, then transactions that were pending when entered. On each update: pending rows that have posted move up into the settled block with their real date and amount (the gap closes), all newly posted transactions are added, then one blank row, then all currently pending transactions **dated tomorrow**.
- **Category:** I fill it in myself. Never invent one. A row that continues an existing row keeps the category it had. In the vault tabs Category is a formula column (`=IF(B="Interest","Income","Transfer")`).
- **Ignore checkbox:** mine. Never change it.
- **Descriptions use my wording, per tab**, not the bank's: "Chick Fil A", "Quick Trip" (Discover tab) but "QT" (Chase tab), "Youtube TV", "Payment", "Discover" for "DISCOVER CAP ONE", "Chase" for "CHASE CREDIT CRD", "From Savings" / "To Checking" for SoFi transfers, "Interest", "To Splurge Vault", "To Roth IRA Vault", "To Car Insurance Vault". New merchants get a short clean name: no store numbers, no codes, no shouting capitals. My sheet has a few typos of its own ("UPSP", "Wayfaire", "Intereset") that got copied.
- **Amounts:** plain positive numbers; purchases in Withdrawl, payments and credits in Deposit on the card tabs.
- **Splits:** I sometimes split one bank transaction into two or three rows that sum to it, e.g. "Sams (broken up)" 225.54 + 49.48 = 275.02, "Cantian (mine)" 82.82 + "Cantian (jordan + alli)" 80.00 = 162.82. These are correct and must be preserved.
- **Dates:** in the Discover tab my rows use the **purchase (transaction) date**, not the posted date. Chase and SoFi lists only show one date, which my rows match. Scheduled future transfers (SoFi month-end) are not pending and are left out.
- SoFi names some transfers vaguely ("To Vault", "To Account - 0628", "From your balance"); the transaction's detail ("On statement as") names the real vault or account.

# What was verified today (2026-10-04)

Each tab was compared against everything its bank would show:

- **SoFi Checking:** 502 bank transactions back to 10/3/24. All match after fixes, except the duplicates listed below.
- **SoFi Savings:** 330 back to 12/26/23. All match. Row 2 "Start $2,935.31" is my summary of the first three deposits (200.00 + 235.31 + 2,500.00).
- **Chase:** all 156 transactions back to 7/11/25 match, including one split.
- **IRA Vault, Car Fund, Car Insurance:** full history matches.
- **Splurge:** the 4 transactions SoFi still has match; older rows cannot be checked.
- **Emergency Fund:** 31 visible rows match. 21 rows are hidden, and SoFi shows 21 transfers in exactly those positions, but hidden cells were never read.
- **Discover:** compared against Capital One's CSV export (628 transactions, 7/2/25 to 10/2/26, with both Transaction Date and Posted Date). Rows before 7/2/25 are Discover-era and unverifiable at Capital One.

Edits already made and verified today: Chase rows 146 to 158 (gap closed, missing weeks filled); Discover rows 914 to 958 added plus a blank row 959 and pending rows 960 to 968 dated 10/5/26; vault tabs updated through 10/2/26; Emergency Fund row 33 restored to 7/31/25 / $38.98 and September interest added at row 53; 14 date corrections (Chase A2, A3, A4, A50, A60; Checking A391, A571, A572; Savings A4, A5, A46, A153, A268; Car Insurance A2).

# Still wrong in the sheet (not yet fixed)

1. **Discover, 106 date cells** in rows 665 to 958 hold the posted date and should hold the purchase date. This includes the 45 rows added today. The exact list was computed (see scratch files).
2. **Discover, missing rows:** Twitch $12.71 on 3/23/26; Walmart $130.66 on 7/28/25; DoorDash $30.50 on 7/27/25.
3. **Discover rows 508 and 509:** "Clutch" −$25 and +$25 on 12/19/25, both Ignore=TRUE, not on the card at all. I said to make everything match the bank, so these go unless I say otherwise.
4. **Checking rows 744 and 745** (9/1/26 Venmo $50, Rent $1,722) duplicate rows 748 and 749 (9/2/26 Bilt, Venmo). SoFi has each once, on 9/2. Remove 744 and 745.
5. **Emergency Fund:** unhide the 21 hidden rows and verify them against SoFi; there is a stray backtick in the Category column near the end.
6. **House tab and Splurge before 9/1/26:** no bank history online. SoFi monthly statement PDFs might cover them.
7. Checking rows 759 and 766 say "Chase Credit Card" (I usually write "Chase") and row 761 says "Interest Earned" (I write "Interest").

I have authorised fixing all of this, including unhiding rows and downloading statements.

# Scratch files from the last session (may be gone; in `/tmp/claude-1000/-home-jkrebs-dotfiles/0e078166-9e2e-4e6b-bcdd-773bd3d39e97/scratchpad/`)

- `dl/cap_a.csv`, `dl/cap_2025-09-05_2026-09-04.csv`, `dl/cap_c.csv`: Capital One exports (columns: Transaction Date, Posted Date, Card No., Description, Category, Debit, Credit).
- `discover_fixes.json`: the 106 date fixes (`row`, `from`, `to`), the missing transactions, and the extra rows.
- `ops_discover_dates.json`: the same fixes as guarded edit operations.
- `recon_lib.ts`: reconciliation (exact date and amount, then same amount within 7 days, then 2 to 3 row splits) and a SoFi text parser. `sofi_recon.ts`, `capone_csv_recon.ts`, `chase_recon.ts`: per-bank runs. `apply.ts`: guarded browser edits (set a cell only if it holds the expected value; delete or insert whole rows).
- `sofi_*.txt`, `chase_full.txt`, `capone_full.txt`: saved page text of full account history.

# Notes for the Plaid and Sheets design

- Plaid transactions carry a stable `transaction_id`, `date` (posted), `authorized_date` (purchase), `pending`, and `pending_transaction_id`, which maps directly onto my gap-then-pending layout. Use `/transactions/sync`. History is at most 24 months and is set when an institution is linked.
- Storing the Plaid transaction id in a hidden column would make syncing idempotent and let split rows share one id.
- Open questions: which Plaid environment my credentials are for and whether it is free at my usage; whether Plaid exposes SoFi vaults as separate accounts; each institution needs a one-time Plaid Link login by me.
- Enable only the Transactions product, so nothing can move money.
- The browser workflow in artoo can remain as a fallback for anything Plaid cannot see.

# How I like to work

I am usually doing something else while you work, so do not stop to ask permission for reversible steps; make sensible calls and tell me what you did. Be fast. Short, plain updates. Verify changes against the source before saying they are right, and say plainly what you could not verify. My homelab rule: AI may touch wheeljack, perceptor and similar boxes, never dagobah, alderaan or bespin.

Reply with exactly: ok
