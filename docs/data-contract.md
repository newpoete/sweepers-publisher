# Data contract

This is how Sweepers Editor hands leaves to the publisher, and what the daily release gives the browser. Epic: [newpoete/sweepers-editor#67](https://github.com/newpoete/sweepers-editor/issues/67).

```
editor ──encrypt──▶ data/queue/001.age … 366.age ──daily release (bin/release)──▶ site: release.json, leaves/, selections.json, …
```

## The calendar

**A leaf belongs to a date, not to a year.** Every leaf is filed under a day of year from 1 to 366 in a canonical leap year (2000), as in the Flask app and the editor:
- 1 January is day 1, 29 February is day 60, and 31 December is day 366, in every year.
- A real date maps to a day with `Date.new(2000, month, day).yday`.
- A day's leaf serves that date every year until the editor publishes a new leaf for it.
- **Day 60** is "today" only on 29 February. In other years, 28 February is followed by day 61 (1 March), as in Flask.

Neither Flask nor the editor has holiday handling: the editor's `holidays` table and `holiday_code` columns are unused leftovers. A holiday that moves would be republished by the editor, if that's ever wanted.

## The queue (editor → publisher)

| | |
|---|---|
| Path | `data/queue/<ddd>.age`: **one file per day of year**, `001.age` to `366.age`, committed by the editor. All 366 were backfilled on 2026-11-14 (sweepers-editor#95), and the daily release has read them since sweepers-editor#96, so the staged site shows real data |
| Publishing | Writing a day's leaf **overwrites** that day's file. The queue never holds more than 366 files |
| Encryption | [age](https://age-encryption.org) v1, X25519 recipient, ASCII-armored (`age --encrypt --armor --recipients-file <file>`) |
| Public key | Committed in `config/recipients.txt` (2026-11-13, sweepers-editor#93). The editor only ever needs this key. The fixture key is `spec/fixtures/fixture-recipient.txt` |
| Private key | Only in the `AGE_SECRET_KEY` Actions secret, plus an offline backup. Never in the repo, the editor, issues or logs |
| Plaintext | One UTF-8 JSON object per file, as below |

```json
{
  "version": 1,
  "aphorism_id": 1234,
  "draft_id": 5678,
  "day_of_year": 317,
  "html": "<p>Every cliff is a historical timeline…</p>\n",
  "snippet": null,
  "score": 9,
  "published_at": "2026-11-01T17:30:00Z"
}
```

| Field | Type | Notes |
|---|---|---|
| `version` | integer | `1`. The release rejects any other value |
| `aphorism_id`, `draft_id` | integer | Editor IDs, from `published_aphorisms`. Never released |
| `day_of_year` | integer 1–366 | Must match the file name |
| `html` | non-empty string | Rendered leaf HTML. It's trusted and shown as is, as Flask did with `\| safe` |
| `snippet` | string or null | Optional selections text. If it's null, the release derives it from `html` |
| `score` | integer or null | The editor's score (it replaces Flask's `tenweight`). It only ranks selections, and it's never released |
| `published_at` | ISO 8601 UTC | When the editor published. A record only, not used by the release |

**Backfill (Epic 3):** the editor writes each day's current leaf, the newest row in `published_aphorisms` for that day, into its file.

**What the public repo shows:** git history shows **which day's file changed and when**, so anyone watching can tell that a day was republished. It can't show what the leaf says.

**The release fails loudly, and deploys nothing, if:**
- any file fails to decrypt (wrong key or a tampered file);
- a file isn't named `001.age` to `366.age`;
- a file holds another day's leaf;
- a file isn't valid JSON;
- the version is unknown;
- any field breaks the rules above.

The error names the file.

## The release (`bin/release`)

```
AGE_SECRET_KEY=<secret> bin/release data/queue _site [--date YYYY-MM-DD] [--base-url URL]
```

- The date defaults to today in UTC.
- **The release writes only the days the site can show:** today, yesterday, the day before yesterday and the current selections. That's at most 10 leaves.
  - A reader west of UTC can be a day behind the release (see [Pages and the reader's date](#pages-and-the-readers-date)), so their yesterday is the release's day before yesterday.
  - Selections only look back, so **no day after the release date is ever released**. That's what keeps tomorrow's leaf a surprise.
- **Republishing a day that has already passed takes effect at the next release** wherever that day is shown (yesterday or selections).
- **The output directory must not already exist.** The site is built in `<out>.partial`, then renamed, so a failed run leaves nothing half-written.

### Released files

| Path | Contents |
|---|---|
| `release.json` | `{"date": "2026-11-12", "day_of_year": 317, "yesterday": {"date": "2026-11-11", "day_of_year": 316}, "released_at": "…Z"}`. Pages use `date` as the cap on the reader's date (see below) |
| `leaves/<day>.json` | `{"day_of_year": 317, "html": "…"}` for today, yesterday, the day before yesterday and each selection that has a leaf. A day with no leaf has no file. Its page shows the date over the owner's chosen line, "Whereof one cannot speak, thereof one must be silent." (Ludwig Wittgenstein, *Tractatus Logico-Philosophicus*), not an empty card. A file that fails to load shows "The leaf could not be loaded" instead |
| `selections.json` | Up to 7 entries, newest first: `[{"day_of_year": 314, "date": "2026-11-09", "snippet": "…"}]`. `date` is the most recent date that day fell on, for display |
| `selection/<day>.html` | A copy of `templates/selection.html` for each current selection (Pages can't route paths dynamically) |
| `sitemap.txt` | `https://` URLs for `/today`, `/yesterday`, `/selections` and each `/selection/<day>`, under `--base-url` |
| `robots.txt` | Allows all crawlers, with a `Sitemap:` line pointing to `sitemap.txt` |
| `404.html` | `templates/404.html`, with its `<base href>` set to the path of `--base-url` (`/sweepers-publisher/` on staging, `/` at a domain root). Pages serves it for a missing path at any depth, so its relative links must resolve from the site root, not from the missing path. It shows "Page **<path>** not found." |
| `mountweazel.json` | `{"html": "…"}`, copied from `data/mountweazel.json` |
| everything in `site/` | The static pages and assets |

### Pages and the reader's date

Pages show **the reader's local date, capped at `release.json`'s date** (`site/assets/javascripts/calendar.js`, decided in #70):
- **West of UTC (the Americas):** the reader's own date, all day. It's never after the release date.
- **East of UTC (Europe, Asia, Australia):** their new day starts before the release runs. Until it does, pages show the release date and its leaf.
- **A late release** keeps everyone on the last released date.
- **Yesterday** is the day before the date the Today page shows. The leaf's heading always shows the leaf's own date.

The live site shows the UTC date to everyone, so a reader in California sees tomorrow's leaf from 4 pm. That's the one intended difference from it.

### Selections

These follow Flask's `Leaf.selections`:
1. Go back over the 90 days before the release date; today is left out.
2. Take each day's leaf.
3. Keep those scoring 8 or more.
4. Keep the best 7 by score, the more recent day first on a tie.
5. List them newest first.

**Snippets** use `snippet` when it's set. Otherwise they reproduce Jinja2 2.8's `striptags|truncate(300)`: tags removed, entities decoded, whitespace collapsed, then cut at a word boundary and finished with ` ...`.

## The mountweazel

The fictitious entry was hard-coded in Flask (`Leaf.mountweazel`), not published by the editor. It lives here as `data/mountweazel.json`, copied from the live site's `/mountweazel.json`. It's not part of the queue.

- `/mountweazel.json` serves it as is.
- `/mountweazel` (`site/mountweazel.html`) shows it like any leaf, dated **22 May of the reader's current year**. That's Flask's stored day (`datetime(2004, 5, 22)`), shown in the current year as Flask did, so the live site showed "Friday, 22 May 2026".
- `/calendar/mountweazel` redirects to `/mountweazel` (#85). The live site served the same page at both, and GitHub Pages can't send a 301. So `site/calendar/mountweazel.html` is a small page with a meta refresh, `location.replace()` (which keeps it out of the history), a canonical link, `noindex`, and a plain link as a fallback.

## The base URL

`--base-url` (default `Sweepers::Release::DEFAULT_BASE_URL`, the staging URL `https://newpoete.github.io/sweepers-publisher`) is the one place the site's address is set. It goes into `sitemap.txt`, `robots.txt` and the 404 page's `<base>`. The cutover (Epic 4) changes it to the final domain.

Crawlers only read `robots.txt` at a domain's root, so on staging (under `/sweepers-publisher/`) it has no effect until the custom domain.

## Fixtures

`bin/fixtures` writes `spec/fixtures/queue/`, encrypted to the **fixture** key. The fixture identity (`spec/fixtures/fixture-identity.txt`) is committed on purpose: it protects nothing, and it lets anyone run a release locally. **Never encrypt real leaves to it.**

The queue holds only the 14 leaves the specs need, around the parity date, 2026-11-12 (day 317). It held one leaf for every day until the release switched to the real queue (sweepers-editor#96); it was trimmed in sweepers-editor#86.

- **The 9 leaves the live site showed on 2026-11-12** (today, yesterday and the 7 selections). They come from the parity snapshot (`spec/fixtures/parity-leaves.json`) and were already public.
  - The 7 selections keep the scores the live site gave them, 9 or 10, which it exposed as `score-N` classes.
  - The scores for today and yesterday (days 316 and 317) are made up, at 5, since the live site doesn't expose them.
- **5 synthetic leaves** ("Fixture leaf for …"), each testing one rule of a release on 2026-11-12:

  | Day | Date | Score | Tests |
  |---|---|---|---|
  | 200 | 18 July | 10 | Outside the 90-day window, so never a selection |
  | 300 | 26 October | 8 | Meets the threshold, but the 7 parity selections outrank it |
  | 310 | 5 November | 7 | Inside the window, below the threshold of 8 |
  | 315 | 10 November | 5 | The day before yesterday, which the release also writes |
  | 318 | 13 November | 10 | After the release date, so never released |

- **Every other day has no leaf**, like a day the editor never published, so the site shows its empty-day line there.

A release for **2026-11-12 reproduces the live site exactly**: the same today, yesterday and 7 selections, and it releases those 9 leaves plus day 315. `spec/fixture_queue_spec.rb` checks this.

## How the editor will encrypt (Epic 3)

For each published leaf, the editor overwrites that day's file through the same CLI:

```ruby
require 'open3'
ciphertext, err, status = Open3.capture3('age', '--encrypt', '--armor', '--recipients-file', recipients_path,
                                         stdin_data: leaf.to_json)
raise "age failed: #{err}" unless status.success?
File.write(File.join(queue_dir, format('%03d.age', leaf[:day_of_year])), ciphertext)
```

`Sweepers::Queue.write` does exactly this, and the specs run it on Ruby 3.3 locally and 3.4 in CI. The editor will need the `age` package in its Docker image (`ruby:3.4-trixie`, Debian). Epic 3 checks the version available there.
