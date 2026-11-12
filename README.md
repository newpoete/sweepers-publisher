# Sweepers Publisher

The static site for **The Sweepers Calendar** (sweeperscalendar.com): one aphorism a day. It's served by GitHub Pages and replaces the old Flask app on Google App Engine.

This repo holds no editorial state. [Sweepers Editor](https://github.com/newpoete/sweepers-editor) is the source of truth, and the publisher only turns what the editor publishes into the site. See the [Sweepers Publisher charter](https://github.com/newpoete/sweepers-editor/blob/main/docs/roadmap/20261111-sweepers-publisher-charter.md) and the build epic, [newpoete/sweepers-editor#67](https://github.com/newpoete/sweepers-editor/issues/67).

> **Status:** under construction. The site is staged at `newpoete.github.io/sweepers-publisher` from fixture data, and sweeperscalendar.com still serves from App Engine.

## How it works

```
Sweepers Editor ──(one age-encrypted file per leaf, committed here)──▶ sweepers-publisher
                                                                │
                              daily GitHub Action, just after 00:00 UTC
                                                                │
                     decrypt ─▶ keep only leaves due by today ─▶ write JSON
                                                                │
                                         GitHub Pages ◀── static HTML + JS
```

1. **The editor publishes** by committing each leaf as its own encrypted file in `data/queue/`. It encrypts to an [age](https://age-encryption.org) public key, so it can't decrypt the queue itself.
2. **A daily release** (a GitHub Action) decrypts the queue with the private key, which is stored only as an Actions secret. It writes plain JSON for the leaves that are due by the release date (UTC) and deploys the site to Pages. Released data exists only in the deployed site, never in a commit.
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
bundle exec rspec                           # all specs (CI runs them on every push and PR)

# Release the fixture queue for any date into a new folder, then serve it.
bin/release spec/fixtures/queue tmp/site --date 2026-11-12 \
  --identity spec/fixtures/fixture-identity.txt
ruby -run -e httpd tmp/site -p 8000         # http://localhost:8000

bin/fixtures                                # regenerate spec/fixtures/queue/
```

The fixture key is committed on purpose because it protects nothing. A real release reads its key from `AGE_SECRET_KEY` instead. See [`docs/data-contract.md`](docs/data-contract.md) for the queue format and every released file.

## Licenses

- **Content** (the aphorisms and site text): [Creative Commons Attribution-NonCommercial-ShareAlike 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/), as on the original site. See `LICENSE-CONTENT`.
- **Code** (everything else): [MIT](LICENSE).

Issues for this repo are tracked in [Sweepers Editor](https://github.com/newpoete/sweepers-editor/issues) and its [GitHub Project](https://github.com/users/newpoete/projects/1).
