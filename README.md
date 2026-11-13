# Sweepers Publisher

The static site for **The Sweepers Calendar** (sweeperscalendar.com): one aphorism a day. It's served by GitHub Pages and replaces the old Flask app on Google App Engine.

This repo holds no editorial state. [Sweepers Editor](https://github.com/newpoete/sweepers-editor) is the source of truth, and the publisher only turns what the editor publishes into the site. See the [Sweepers Publisher charter](https://github.com/newpoete/sweepers-editor/blob/main/docs/roadmap/20261111-sweepers-publisher-charter.md) and the build epic, [newpoete/sweepers-editor#67](https://github.com/newpoete/sweepers-editor/issues/67).

> **Status:** under construction. The site is staged at `newpoete.github.io/sweepers-publisher` from fixture data, and sweeperscalendar.com still serves from App Engine.

## How it works

```
Sweepers Editor ──(one age-encrypted file per day, committed here)──▶ sweepers-publisher
                                                                │
                              daily GitHub Action, just after 00:00 UTC
                                                                │
                 decrypt ─▶ keep only today, yesterday, selections ─▶ write JSON
                                                                │
                                         GitHub Pages ◀── static HTML + JS
```

1. **The editor publishes** by writing each day's leaf to its own encrypted file, `data/queue/001.age` to `366.age`, overwriting that day's previous leaf. It encrypts to an [age](https://age-encryption.org) public key, so it can't decrypt the queue itself.
2. **A daily release** (a GitHub Action) decrypts the queue with the private key, which is stored only as an Actions secret. It writes plain JSON for only the days the site shows (today, yesterday and the current selections, by the release date in UTC) and deploys the site to Pages. Released data exists only in the deployed site, never in a commit.
3. **The pages are static HTML.** A small script reads the release date from `release.json`, fetches the leaf for the page, and displays it.

A public repo can't keep a secret, so this is how tomorrow's leaf stays a surprise: anything committed here in readable form is public at once.

## Hygiene rules

This repo is **public**. Never commit, or paste into issues, PRs or logs:
- an age private key (`AGE-SECRET-KEY-…`), except the throwaway **fixture** identity, which protects nothing;
- a decrypted queue, or any real leaf dated after today;
- release output (it's built in the Action);
- personal names, email addresses or other credentials.

The age **public** key isn't secret. `.gitignore` covers the usual file names, but check `git status` before committing anyway.

## Local development

You need Ruby (`.ruby-version` says 3.4, and 3.3 works), Bundler, and the [age](https://age-encryption.org) CLI (`sudo apt install age` on Ubuntu or Debian). The publisher itself uses only Ruby's standard library; the Gemfile is for RSpec.

```bash
bundle install
bundle exec rspec                           # Ruby specs (CI runs both on every push and PR)
node --test spec/javascripts/*.test.js               # page script specs (Node 18+, no packages)

# Release the fixture queue for any date into a new folder, then serve it.
bin/release spec/fixtures/queue tmp/site --date 2026-11-12 \
  --identity spec/fixtures/fixture-identity.txt
bundle exec bin/serve tmp/site              # http://localhost:8000, served like GitHub Pages

bin/fixtures                                # regenerate spec/fixtures/queue/
```

The fixture key is committed on purpose because it protects nothing. A real release reads its key from `AGE_SECRET_KEY` instead. See [`docs/data-contract.md`](docs/data-contract.md) for the queue format and every released file.

## Daily release

`.github/workflows/release.yml` releases the queue for today's date (UTC) and deploys the site to GitHub Pages. It runs:
- **every day at 00:07 UTC**, off the top of the hour, when GitHub's schedules are busiest;
- **on every push to `main`**;
- **by hand**, with no inputs.

Until a release runs, the previous release stays deployed, so the previous day's leaf stays up. **Scheduled runs can start late:** often by minutes, and sometimes by an hour or more under load.

The private key is the `AGE_SECRET_KEY` Actions secret. Until Epic 3, the workflow releases the fixture queue (`spec/fixtures/queue/`), so the secret holds the **fixture** identity. Epic 3 replaces it with a real key and switches `QUEUE_DIR` to `data/queue`.

```bash
gh workflow run release.yml                              # release and deploy now
gh run list --workflow release.yml --limit 5             # recent runs and their status
gh run view --log-failed <run-id>                        # why a run failed
gh secret set AGE_SECRET_KEY < <identity-file>           # set or replace the key, never echoed
```

You can also run it from the repo's **Actions** tab: **Release**, then **Run workflow**.

**When a release fails,** the run turns red. GitHub emails the account that last changed the workflow's `cron` line. Nothing is deployed, and the previous release stays up. There's deliberately no date input, since releasing a later date would publish tomorrow's leaf.

### Keep-alive

GitHub disables scheduled workflows in a public repo after **60 days with no repository activity**. The scheduled run's `keepalive` job checks the date of the last commit. If it's 50 days or more, the job pushes an empty commit ("Keep the daily release schedule alive") to `main`. Pushes made with the workflow's own token don't trigger workflows, so this doesn't start a second release.

- **Once the editor publishes (Epic 3),** its commits keep the repo active, and the job does nothing.
- **Why a commit and not the API:** GitHub's docs don't say whether re-enabling a workflow through the API resets the 60 days, but a commit is unambiguous activity.
- **If schedules are disabled anyway,** the Actions tab shows a banner. Re-enable with `gh workflow enable release.yml`.

## Licenses

- **Content** (the aphorisms and site text): [Creative Commons Attribution-NonCommercial-ShareAlike 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/), as on the original site. See `LICENSE-CONTENT`.
- **Code** (everything else): [MIT](LICENSE).

Issues for this repo are tracked in [Sweepers Editor](https://github.com/newpoete/sweepers-editor/issues) and its [GitHub Project](https://github.com/users/newpoete/projects/1).
