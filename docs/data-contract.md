# Data contract

This is how Sweepers Editor hands leaves to the publisher, and what the daily release gives the browser. Epic: [newpoete/sweepers-editor#67](https://github.com/newpoete/sweepers-editor/issues/67).

```
editor ──encrypt each leaf──▶ data/queue/<id>.age ──daily release (bin/release)──▶ site: release.json, leaves/, selections.json, …
```

## The calendar

Every leaf is filed under a **day of year from 1 to 366 in a canonical leap year (2000)**, as in the Flask app and the editor:
- 1 January is day 1, 29 February is day 60, and 31 December is day 366, in every year.
- A real date maps to a day with `Date.new(2000, month, day).yday`.
- A leaf's real date is its `year` plus its `day_of_year`. It only decides when the leaf is **due**.
- **Day 60 in a non-leap year** has no real date. It counts as **1 March**, so it's never released early. It's never "today", because no date in a non-leap year maps to day 60. Flask behaved the same way.

**A leaf, once due, serves its day every year until a newer one replaces it.** Pages show it under the current date, whatever year it was published for, as Flask did. The live site has had no new publishes for years and still shows a leaf every day; this contract keeps that.

## The queue (editor → publisher)

| | |
|---|---|
| Path | `data/queue/<16 hex chars>.age`, **one file per published leaf**, committed by the editor (Epic 3) |
| Encryption | [age](https://age-encryption.org) v1, X25519 recipient, ASCII-armored (`age --encrypt --armor --recipients-file <file>`) |
| Public key | Committed in `config/recipients.txt` (Epic 3). The editor only ever needs this key. The fixture key is `spec/fixtures/fixture-recipient.txt` |
| Private key | Only in the `AGE_SECRET_KEY` Actions secret, plus an offline backup. Never in the repo, the editor, issues or logs |
| Plaintext | One UTF-8 JSON object per file, as below |

```json
{
  "version": 1,
  "aphorism_id": 1234,
  "draft_id": 5678,
  "year": 2026,
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
| `year` | integer | The year the leaf was published for. It sets when the leaf is first due, and it's never released |
| `day_of_year` | integer 1–366 | Canonical day (see above) |
| `html` | non-empty string | Rendered leaf HTML. It's trusted and shown as is, as Flask did with `\| safe` |
| `snippet` | string or null | Optional selections text. If it's null, the release derives it from `html` |
| `score` | integer or null | The editor's score (it replaces Flask's `tenweight`). It only ranks selections, and it's never released |
| `published_at` | ISO 8601 UTC | When the editor published. It breaks ties between two leaves for the same year and day |

**Why one file per leaf:** age output is different every time, so one big queue file would add a whole new copy to git history on every publish. One file per leaf adds about 1 KB per publish.
- **File names are random**, so they reveal only how many leaves exist, not which days.
- **Files are never edited.** Republishing a day adds a new file, and the newest due leaf wins.
- **Backfill:** the editor writes one file for each row of `published_aphorisms` (Epic 3).

**The release fails loudly, and deploys nothing, if:**
- any file fails to decrypt (wrong key or a tampered file);
- a file isn't valid JSON;
- the version is unknown;
- any field breaks the rules above.

The error names the file.

## The release (`bin/release`)

```
AGE_SECRET_KEY=<secret> bin/release data/queue _site [--date YYYY-MM-DD] [--base-url URL]
```

- The date defaults to today in UTC. **A leaf is due when its real date is on or before the release date.** A leaf that isn't due appears in no output file.
- **For each day of year, the newest due leaf** is the one from the latest year, and within that year the latest `published_at`. This is Flask's `Leaf.by_day_of_year`.
- **The output directory must not already exist.** The site is built in `<out>.partial`, then renamed, so a failed run leaves nothing half-written.

### Released files

| Path | Contents |
|---|---|
| `release.json` | `{"date": "2026-11-12", "day_of_year": 317, "yesterday": {"date": "2026-11-11", "day_of_year": 316}, "released_at": "…Z"}`. **Pages take "today" from this file, not the visitor's clock**, so a late run leaves yesterday's leaf showing |
| `leaves/<day>.json` | `{"day_of_year": 317, "html": "…"}` for each day that has a due leaf. A day with no leaf has no file, and the page shows an empty leaf |
| `selections.json` | Up to 7 entries, newest first: `[{"day_of_year": 314, "date": "2026-11-09", "snippet": "…"}]`. `date` is the most recent occurrence of that day before the release date, for display |
| `selection/<day>.html` | A copy of `site/selection.html` for each current selection (Pages can't route paths dynamically) |
| `sitemap.txt` | `https://` URLs for `/today`, `/yesterday`, `/selections` and each `/selection/<day>` |
| `mountweazel.json` | `{"html": "…"}`, copied from `data/mountweazel.json` |
| everything in `site/` | The static pages and assets |

### Selections

These follow Flask's `Leaf.selections`:
1. Go back over the 90 days before the release date; today is left out.
2. For each day, take that day of year's current leaf, **from any year**. That's Flask's day-of-year window, so old leaves still make selections when nothing new has been published.
3. Keep those scoring 8 or more.
4. Keep the best 7 by score, the more recent day first on a tie.
5. List them newest first.

**Snippets** use `snippet` when it's set. Otherwise they reproduce Jinja2 2.8's `striptags|truncate(300)`: tags removed, entities decoded, whitespace collapsed, then cut at a word boundary and finished with ` ...`.

## The mountweazel

The fictitious entry was hard-coded in Flask (`Leaf.mountweazel`), not published by the editor. It lives here as `data/mountweazel.json`, copied from the live site's `/mountweazel.json`. It's not part of the queue.

## Fixtures

`bin/fixtures` writes `spec/fixtures/queue/`, encrypted to the **fixture** key. The fixture identity (`spec/fixtures/fixture-identity.txt`) is committed on purpose: it protects nothing, and it lets anyone run a release locally. **Never encrypt real leaves to it.**

The fixtures model the real situation, where nothing new has been published for years:
- a synthetic 2019 leaf for every day, with scores 0–7;
- the leaves the live site showed on 2026-11-12 (today, yesterday and the 7 selections), from the parity snapshot (`spec/fixtures/parity-leaves.json`), filed as 2019 leaves. They were already public, and the scores for days 316 and 317 are made up;
- one recent leaf (2026, day 310), and future leaves (2026 days 318–330, and January 2027), which must stay unreleased.

A release for **2026-11-12 reproduces the live site exactly**, and `spec/fixture_queue_spec.rb` checks this.

## How the editor will encrypt (Epic 3)

For each leaf, the editor writes the JSON above through the same CLI:

```ruby
require 'open3'
ciphertext, err, status = Open3.capture3('age', '--encrypt', '--armor', '--recipients-file', recipients_path,
                                         stdin_data: leaf.to_json)
raise "age failed: #{err}" unless status.success?
File.write(File.join(queue_dir, "#{SecureRandom.hex(8)}.age"), ciphertext)
```

`Sweepers::Queue.add` does exactly this, and the specs run it on Ruby 3.3 locally and 3.4 in CI. The editor will need the `age` package in its Docker image (`ruby:3.4-trixie`, Debian). Epic 3 checks the version available there.
