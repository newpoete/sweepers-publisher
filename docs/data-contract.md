# Data contract

How Sweepers Editor hands leaves to the publisher, and what the daily release gives the browser. Epic: [newpoete/sweepers-editor#67](https://github.com/newpoete/sweepers-editor/issues/67).

```
editor ──encrypt──▶ data/queue.age ──daily release (bin/release)──▶ site: release.json, leaves/, selections.json, …
```

## The calendar

Every leaf is filed under a **day of year from 1 to 366 in a canonical leap year (2000)**, as in the Flask app and the editor:
- 1 January is day 1, 29 February is day 60, and 31 December is day 366, in every year.
- A real date maps to a day with `Date.new(2000, month, day).yday`.
- A leaf's real date is its `year` plus its `day_of_year`.
- **Day 60 in a non-leap year** has no real date. It counts as **1 March**, so it's never released early. It's never "today", because no date in a non-leap year maps to day 60. Flask behaved the same way.

## The queue (editor → publisher)

| | |
|---|---|
| Path | `data/queue.age` in this repo, committed by the editor (Epic 3) |
| Encryption | [age](https://age-encryption.org) v1, X25519 recipient, ASCII-armored (`age --encrypt --armor --recipients-file <file>`) |
| Public key | Committed in `config/recipients.txt` (Epic 3). The editor only ever needs this key. The fixture key is in `test/fixtures/fixture-recipient.txt` |
| Private key | Only in the `AGE_SECRET_KEY` Actions secret, plus an offline backup. Never in the repo, the editor, issues or logs |
| Plaintext | UTF-8 JSON, as shown below |

```json
{
  "version": 1,
  "generated_at": "2026-11-12T18:00:00Z",
  "leaves": [
    {
      "aphorism_id": 1234,
      "draft_id": 5678,
      "year": 2026,
      "day_of_year": 317,
      "html": "<p>Every cliff is a historical timeline…</p>\n",
      "snippet": null,
      "score": 9,
      "published_at": "2026-11-01T17:30:00Z"
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `version` | integer | `1`. The release rejects any other value |
| `aphorism_id`, `draft_id` | integer | Editor IDs, from `published_aphorisms`. Never released |
| `year` | integer | The year the leaf runs |
| `day_of_year` | integer 1–366 | Canonical day (see above) |
| `html` | non-empty string | Rendered leaf HTML. It's trusted and shown as is, as Flask did with `\| safe` |
| `snippet` | string or null | Optional selections text. If it's null, the release derives it from `html` |
| `score` | integer or null | The editor's score (it replaces Flask's `tenweight`). It only ranks selections, and it's never released |
| `published_at` | ISO 8601 UTC | When the editor published. It breaks ties between two leaves for the same year and day |

**The queue is the whole published calendar**, past leaves included. The editor rewrites and re-encrypts all of it on each publish, so the newest commit is always complete. Republishing a day adds a leaf, and the newest due one wins.

**The release fails loudly, and deploys nothing, if:**
- decryption fails (wrong key or a tampered file);
- the JSON is invalid;
- the version is unknown;
- any leaf breaks the rules above.

## The release (`bin/release`)

```
AGE_SECRET_KEY=<secret> bin/release data/queue.age _site [--date YYYY-MM-DD] [--base-url URL]
```

- The date defaults to today in UTC. **A leaf is due when its real date is on or before the release date.** A leaf that isn't due appears in no output file.
- **For each day of year, the newest due leaf** is the one from the latest year, and within that year the latest `published_at`. This is Flask's `Leaf.by_day_of_year`, so last year's leaf stands in until this year's is due.
- **The output directory must not already exist.** The site is built in `<out>.partial`, then renamed, so a failed run leaves nothing half-written.

### Released files

| Path | Contents |
|---|---|
| `release.json` | `{"date": "2026-11-12", "day_of_year": 317, "yesterday": {"date": "2026-11-11", "day_of_year": 316}, "released_at": "…Z"}`. **Pages take "today" from this file, not the visitor's clock**, so a late run leaves yesterday's leaf showing |
| `leaves/<day>.json` | `{"day_of_year": 317, "year": 2026, "html": "…"}` for each day that has a due leaf. A day with no leaf has no file, and the page shows an empty leaf |
| `selections.json` | Up to 7 entries, newest first: `[{"day_of_year": 314, "date": "2026-11-09", "snippet": "…"}]` |
| `selection/<day>.html` | A copy of `site/selection.html` for each current selection (Pages can't route paths dynamically) |
| `sitemap.txt` | `https://` URLs for `/today`, `/yesterday`, `/selections` and each `/selection/<day>` |
| `mountweazel.json` | `{"html": "…"}`, copied from `data/mountweazel.json` |
| everything in `site/` | The static pages and assets |

### Selections

These follow Flask's `Leaf.selections`:
1. Take the leaves dated 1 to 90 days before the release date. Today's leaf is left out.
2. Keep those scoring 8 or more.
3. Keep the best 7 by score, the newer first on a tie.
4. List them newest first.

**One intended difference: the window uses real dates.** Flask matched on day of year alone, so a past year's leaf could slip in.

**Snippets** use `snippet` when it's set. Otherwise they reproduce Jinja2 2.8's `striptags|truncate(300)`: tags removed, entities decoded, whitespace collapsed, then cut at a word boundary and finished with ` ...`.

## The mountweazel

The fictitious entry was hard-coded in Flask (`Leaf.mountweazel`), not published by the editor. It lives here as `data/mountweazel.json`, copied from the live site's `/mountweazel.json`. It's not part of the queue.

## Fixtures

`bin/fixtures` writes `test/fixtures/queue.age`, encrypted to the **fixture** key. The fixture identity (`test/fixtures/fixture-identity.txt`) is committed on purpose: it protects nothing, and it lets anyone run a release locally. **Never encrypt real unreleased leaves to it.**

The fixture queue contains:
- a synthetic leaf for every day of 2025 and 2026, and for January 2027 (future leaves);
- the leaves the live site showed on 2026-11-12 (today, yesterday and the 7 selections) from the parity snapshot (`test/fixtures/parity-leaves.json`). They were already public. The scores for days 316 and 317 are made up;
- high scores only on 2025 synthetic leaves, so a release for **2026-11-12 reproduces the live site's selections exactly**. `test/fixtures_test.rb` checks this.

## How the editor will encrypt (Epic 3)

The editor writes the queue JSON and pipes it through the same CLI:

```ruby
require 'open3'
ciphertext, err, status = Open3.capture3('age', '--encrypt', '--armor', '--recipients-file', recipients_path,
                                         stdin_data: queue.to_json)
raise "age failed: #{err}" unless status.success?
```

`Sweepers::Crypto.encrypt` is the same call, and the tests run it on Ruby 3.3 locally and 3.4 in CI. The editor will need the `age` package in its Docker image (`ruby:3.4-trixie`, Debian). Epic 3 checks the version available there.
