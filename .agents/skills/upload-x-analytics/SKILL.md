---
name: upload-x-analytics
description: Download one year of account-overview analytics CSV data from X using the user's existing signed-in Chrome session, switch among Build Canada X accounts, and upload each export to the York Factory metrics import API. Use when an agent needs to collect, refresh, backfill, or upload X/Twitter analytics for build_canada, build_toronto, canada_spends, or lucyhargreaves4 without extracting cookies or creating a separate browser profile.
---

# Upload X Analytics

Use the user's running Chrome browser and its existing X session. Never inspect or copy cookies, local storage, passwords, or Chrome profile files.

## Preconditions

- Load and follow the available `chrome:control-chrome` skill before any browser action.
- Require `YORK_FACTORY_API_KEY`. Never print it or place its value in logs.
- Use `YORK_FACTORY_URL` when set; otherwise use `https://yorkfactory.buildcanada.com`.
- Use `X_ANALYTICS_DOWNLOAD_DIR` when set; otherwise use the user's `Downloads` directory.
- Treat invoking this skill as authorization to download the requested X CSVs and upload only those new files to the York Factory endpoint.

## Accounts

Process these warehouse keys and X handles in order unless the user requests a subset:

| Warehouse account | X handle |
|---|---|
| `build_canada` | `@buildcanada` |
| `build_toronto` | `@build_toronto` |
| `canada_spends` | `@canada_spends` |
| `lucyhargreaves4` | `@lucyhargreaves4` |

An account may be absent from X's account switcher. Record it as skipped and continue. In particular, do not fail the run when `@lucyhargreaves4` is absent.

## Workflow

1. Confirm `YORK_FACTORY_API_KEY` is present without displaying it. Confirm the download directory exists.
2. Connect to Chrome through the Chrome-control skill and open a fresh agent-controlled tab at `https://x.com/i/account_analytics`. The tab shares the user's signed-in Chrome session. Do not claim an existing user tab: input on claimed tabs can time out. If an input call on the fresh tab times out once, discard that tab and open another fresh tab instead of retrying the same action repeatedly.
3. If X shows a login screen, leave the tab open as a handoff and ask the user to sign in. Do not request credentials in chat.
4. For each requested account:
   1. Navigate to `https://x.com/i/account_analytics`.
   2. Read the current handle from the `SideNav_AccountSwitcher_Button` account control.
   3. When the handle differs, open that control, choose the single visible **Manage accounts** action by accessible role/name, and inspect the visible account choices. Prefer visible accessible names and exact handle text; X's test IDs may be absent or duplicated.
   4. Select the account choice containing the exact target handle. For a delegated account, expect an intermediate **Switch accounts** confirmation and confirm it once. If the target is absent, record a skip and continue.
   5. Require the side navigation account control to show the exact target handle, then return to the analytics URL. Do not retry or download when this verification fails.
   6. Select the `Overview` analytics tab when it is not already selected.
   7. Select `1Y`. Verify the `1Y` control has the selected styling (currently its class contains `bg-text`) or the URL contains `days=365`. Do not rely on `aria-pressed`, which X may omit, and do not download until the one-year range is verified.
   8. Immediately before clicking `Download CSV`, run the bundled guard and retain the `checkpoint` path from its JSON output:

       ```bash
       ruby .agents/skills/upload-x-analytics/scripts/guard_x_download.rb mark \
         --dir /absolute/path/to/downloads
       ```

   9. Click the unique button whose accessible name is `Download CSV`, then run the guard's wait command using that exact checkpoint:

       ```bash
       ruby .agents/skills/upload-x-analytics/scripts/guard_x_download.rb wait \
         --checkpoint /path/from/mark/output
       ```

      Treat the successful JSON `file` value as the only trusted download path. The guard waits up to 90 seconds, rejects multiple new CSVs, ignores incomplete downloads, requires a non-empty file with a stable size, and removes its checkpoint.
      - If no new completed CSV appears, report an error for that account and warn the user that Chrome may have shown a native Save dialog. Tell them unattended downloads require disabling **Ask where to save each file before downloading** in `chrome://settings/downloads`. Do not try to operate the native dialog, do not upload any pre-existing CSV, and continue with the next account.
      - If more than one candidate appears, report an ambiguous-download error for that account, upload none of them, and continue with the next account.
   10. Run the bundled uploader:

       ```bash
       ruby .agents/skills/upload-x-analytics/scripts/upload_x_csv.rb \
         --account ACCOUNT_KEY \
         --file /absolute/path/to/account_overview_analytics.csv
       ```

   11. Require a successful JSON response and report inserted, updated, and error counts. Treat that response as the normal end-to-end import verification; do not boot Rails separately for per-account database checks unless the user explicitly requests database verification. Continue to the next account after an account-specific failure.
5. Finalize browser tabs according to the Chrome-control skill. Keep a tab only when login or user intervention is required.
6. Report uploaded, skipped, and failed accounts. Include each downloaded file path. Do not delete the exports.

## Guardrails

- Base account switching on the visible account switcher; never guess that an account exists.
- Never use a CSV that existed before the current account's download marker.
- Never treat a browser download event, timeout, or click result as proof that a file was downloaded; require the completed filesystem artifact.
- Never upload a file unless its headers pass the bundled validator.
- Never upload one account's export under another account key.
- Prefer targeted visible-element checks over repeated full-page snapshots. Do not repeat a browser action after it has visibly succeeded.
- Do not use Ferrum, Selenium, Playwright CLI, or a new Chrome profile. The signed-in Chrome extension connection is the required browser surface.
- A CAPTCHA requires explicit user confirmation before solving it.
