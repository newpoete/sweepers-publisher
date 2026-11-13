# Parity check of the staged site

The staged site at `https://newpoete.github.io/sweepers-publisher/` compared, route by route, with the parity snapshot of the live Flask site (sweeperscalendar.com, captured 2026-11-12 00:53 UTC). This is the go/no-go for Epic 3, real data ([newpoete/sweepers-editor#74](https://github.com/newpoete/sweepers-editor/issues/74)).

**Verdict: go.** Every route returns the same status and the same content, and the pages look the same at both widths. Each difference is intended, or it can only be settled at cutover and is filed.

## How it was checked

- **Checked:** 2026-11-13 04:40 UTC (12 November, 8:40 pm Pacific), against the release from merge commit `adf9d14` (`release.json`: date 2026-11-13, released 03:00:41 UTC).
- **Requests:** `bash docs/parity-check/capture.sh tmp/parity https://newpoete.github.io/sweepers-publisher`. It's the snapshot's `capture.sh` with the base URL as an argument, plus the rendered DOM of each page from headless Chrome, since the pages fill themselves in with script. Public GET requests only.
- **Live side:** the snapshot in `sweepers-flask/parity/`, a private repo (`responses/`, `screenshots/`, `README.md`).
- **The data:** the fixture queue holds the live site's own leaves for the 9 days the snapshot shows (days 272–317), so content compares exactly, not just in shape.
- **Reader's zone:** the browser ran in Pacific time, where it was still 12 November. So the staged pages showed 12 November, the same date as the snapshot.

## Routes

| Route | Live | Staged | Result |
|---|---|---|---|
| `http://…/` | 302 → `https://` | 301 → `https://` | Same. Pages uses 301 |
| `/` | 200, leaf for Thu 12 Nov 2026 | 200, same leaf and heading | Same |
| `/today` | 200, Today active | 200, Today active | Same |
| `/yesterday` | 200, leaf for Wed 11 Nov | 200, same leaf, Yesterday active | Same |
| `/calendar/` | 200, same as `/` | 200, same as `/` | Same |
| `/calendar` | 301 → `/calendar/` | 301 → `/calendar/` | Same |
| `/selections` | 200, 7 selections, days 314 … 272, newest first | 200, the same 7, same order, snippets and dates | Same, without the `score-N` classes (intended, see below) |
| `/selection/314` | 200, Mon 9 Nov leaf | 200, same | Same |
| `/selection/999` | 404 page | 404 page | Same |
| `/mountweazel` | 200, Fri 22 May 2026 | 200, same text and date | Same |
| `/calendar/mountweazel` | 200, same page | 200, redirects to `/mountweazel` | Intended ([#85](https://github.com/newpoete/sweepers-editor/issues/85)) |
| `/mountweazel.json` | 200, `application/json` | 200, `application/json`, identical `html` | Same |
| `/sitemap.txt` | 10 `http://` URLs | the same 10 paths, `https://` | Intended ([#72](https://github.com/newpoete/sweepers-editor/issues/72)) |
| `/robots.txt` | allow all, `SITEMAP: http://…` | allow all, `Sitemap: https://…` | Intended |
| `/no-such-page-parity-check` | 404, "Page **/no-such-page-parity-check** not found." | 404, "Page **/sweepers-publisher/no-such-page-parity-check** not found." | Path prefix only on staging ([#88](https://github.com/newpoete/sweepers-editor/issues/88)) |
| `https://www.sweeperscalendar.com/` | 200, served directly | not applicable until cutover | [#88](https://github.com/newpoete/sweepers-editor/issues/88) |
| `https://sweepers-flask.appspot.com/` | 200, served directly | not applicable | [#88](https://github.com/newpoete/sweepers-editor/issues/88) |

Page titles match on every page ("Sweepers Calendar for 12th of November", "… Selected Aphorisms", "… for 22nd of May", "Page Not Found").

## Look

Screenshots of the staged pages are in [`parity-check/screenshots/`](parity-check/screenshots/), at 1280 px and at 390 px (`-mobile`), next to the snapshot's in `sweepers-flask/parity/screenshots/`. They were taken the same way: `google-chrome --headless=new --window-size=1280,1000 --virtual-time-budget=8000` (1280,1500 for selections).

A pixel diff (`compare -metric AE -fuzz 2%`) of each pair the snapshot has:

| Page | Differing pixels | What differs |
|---|---|---|
| today | 1,196 of 1.28 M | Blog and Twitter links; the clock |
| today, phone | 1,993 of 0.33 M | The clock |
| yesterday | 1,200 | Blog and Twitter; the clock |
| selections | 1,176 | Blog and Twitter; the clock |
| selection/314 | 1,180 | Blog and Twitter; the clock |
| mountweazel | 1,171 | Blog and Twitter; the clock |
| 404 | 4,255 | Blog and Twitter; the clock; the `/sweepers-publisher` path |

Fonts, colors, the card, spacing and the phone layout are identical.

## Differences

| Difference | Decision |
|---|---|
| **The reader's local date.** Pages show the reader's own date, capped at the release date. Live, "today" was UTC | Intended ([#70](https://github.com/newpoete/sweepers-editor/issues/70)) |
| **The footer clock** shows local time and zone ("PST"), not GMT, and "PST" isn't a link to Wikipedia | Intended ([#70](https://github.com/newpoete/sweepers-editor/issues/70)) |
| **No Blog or Twitter** in the navbar | Intended ([#84](https://github.com/newpoete/sweepers-editor/issues/84)) |
| **`/calendar/mountweazel` redirects** to `/mountweazel` | Intended ([#85](https://github.com/newpoete/sweepers-editor/issues/85)) |
| **A day with no leaf** shows the Wittgenstein line. Live, it never happened | Intended ([#83](https://github.com/newpoete/sweepers-editor/issues/83)) |
| **No `score-N` classes** on selections. They had no style, so nothing showed | Intended (parity README, point 3) |
| **`https://` sitemap and robots** | Intended ([#72](https://github.com/newpoete/sweepers-editor/issues/72)) |
| **No analytics.** The live Universal Analytics property is dead | Intended. Decided at cutover ([#88](https://github.com/newpoete/sweepers-editor/issues/88)) |
| **The `/sweepers-publisher/` prefix** in URLs and the 404 message | Staging only. Gone at the domain root ([#88](https://github.com/newpoete/sweepers-editor/issues/88)) |
| **`http://` redirects with 301**, not 302 | Accepted: Pages' own redirect, and the better code for a permanent move |
| **Every file is cached for 10 minutes** (`Cache-Control: max-age=600`), pages and `release.json` included. Live, only robots.txt was | Accepted: a reader who loaded the site in the 10 minutes before a release may see the previous day for up to 10 more minutes. Re-checked at cutover ([#88](https://github.com/newpoete/sweepers-editor/issues/88)) |
| **CDN assets have no integrity hashes** (live didn't either) | Hardening, filed ([#87](https://github.com/newpoete/sweepers-editor/issues/87)) |

## The day boundary

The first scheduled release runs at 00:07 UTC on 14 November (4:07 pm Pacific on 13 November).

| Check | Result |
|---|---|
| The scheduled run starts, and when | _Pending_ |
| `release.json` turns to 2026-11-14 | _Pending_ |
| A reader east of UTC (Tokyo) sees 14 November after the release, not before | _Pending_ |

## Leaks

The repo is public, so every commit was checked. That's 26 commits on all branches, including `publisher-site-repo`, on 2026-11-13.

| Check | Result |
|---|---|
| Age private keys (`AGE-SECRET-KEY-1…`) | One key, ever: the fixture identity (`test/fixtures/`, then `spec/fixtures/`) |
| Real leaves readable with that key | Only the 9 parity leaves (days 272, 274, 275, 280, 298, 301, 314, 316, 317), all shown on the live site by 2026-11-12. The other 357 days in the queue, and every version of the older `test/fixtures/queue.age`, are synthetic ("Fixture leaf for …") |
| Plaintext leaves | `parity-leaves.json` (every version: the same 9 days) and `data/mountweazel.json` (identical to the live `/mountweazel.json`) |
| Released or decrypted files (`release.json`, `selections.json`, `leaves/`, `queue.json`, `_site/`, `tmp/`) | None ever committed |
| Email addresses | Only GitHub noreply addresses (`…@users.noreply.github.com`, `noreply@github.com`, `noreply@anthropic.com`) |
| Actions logs | The `AGE_SECRET_KEY` value doesn't appear (checked in [#73](https://github.com/newpoete/sweepers-editor/issues/73)) |

## Who can write to the repo

The queue is encrypted to a public key, so anyone can make a valid `.age` file. Encryption keeps tomorrow's leaf secret, but it can't say who wrote a file. What decides what gets published is **who can push to `main`**. See the README's hygiene rules.

Checked on 2026-11-13:

| Check | Result |
|---|---|
| Collaborators | `newpoete` (admin) only. No pending invitations |
| Deploy keys | None |
| Webhooks | None |
| Branch protection and rulesets | None. With one writer, there's nothing to enforce yet |
| Actions token | Read-only by default. Only the `deploy` job (Pages) and the `keepalive` job (one empty commit after 50 quiet days) ask for more |
| Pull requests from forks | `test.yml` runs with a read-only token and no secrets. `release.yml` doesn't run on pull requests. First-time contributors need approval to run any workflow |
| Secrets | `AGE_SECRET_KEY` only, holding the fixture identity until Epic 3 |
| `github-pages` environment | Deploys from `main` only |
| GitHub Apps and OAuth apps | Checked by the owner at <https://github.com/settings/installations> and the authorized apps list: no installed GitHub Apps. The only authorized app is **GitHub CLI**, an OAuth app. It's the owner's own `gh` login on the owner's machine, so it acts as the owner, with the owner's access, not as a separate writer. Revoking it would only log `gh` out. The API doesn't list these for this token, so the check is manual |

In Epic 3, the editor publishes by pushing from the owner's machine. A deploy key that can write to this repo only is the suggested credential. Add it to this table when it exists.
