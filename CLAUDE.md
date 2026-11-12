# Sweepers Publisher

## Ground rules

- **This repo is public.** Never commit or post an age private key (other than the fixture
  identity), a decrypted queue, release output, or any real leaf dated after today. See the
  README's hygiene rules.
- **Ruby standard library only** in `lib/` and `bin/`. The Gemfile is for test gems.

## Tests

- **RSpec, following [Even Better Specs](https://evenbetterspecs.github.io/).** This is the project standard. In short:
  - `describe` the class (`RSpec.describe Sweepers::Release`), then its methods: `.class_method` and `#instance_method`.
  - Start every `context` with "when". Keep each description to one line of 100 characters or fewer.
  - Use `described_class`, never the class name, inside examples. Use `subject` when the initializer takes no arguments.
  - **No `let`, `let!`, `before` hooks or shared examples.** Each example builds its own data, with helpers from `spec/support/` (`build_leaf`) in place of factories.
  - Group expectations that share a setup into one example. Failures are aggregated globally (`spec_helper.rb`).
  - Always `expect`, never `should`. Use `instance_double` over `double`. Mock only external dependencies.
  - No `require` in spec files: `.rspec` loads `spec_helper`.
  - Cover valid, edge and invalid cases.
- Run with `bundle exec rspec`. Specs that need the `age` CLI call `skip_without_age`; CI installs it.
- **The page script** (`site/assets/javascripts/sweepers.js`) keeps its date logic in pure functions, specced with Node's built-in runner (`node --test spec/javascripts/`), with no npm packages. Follow the same Even Better Specs rules where they apply. Set `process.env.TZ` per example to test time zones.
- **Page shells** in `site/` are plain HTML with no templating. Their shared navbar and footer sit between `<!-- layout:… -->` markers, and `spec/site/pages_spec.rb` checks they stay identical.
- **Issues live in `newpoete/sweepers-editor`**, in the Sweepers GitHub Project. A PR here
  closes its issue with `Closes newpoete/sweepers-editor#N`, and no other closing keyword may appear in the body.

## GitHub

- **Sign every PR comment, review reply and issue comment you post.** They go out under
  the owner's GitHub account, so without a signature your replies look like theirs. End each
  one with this footer, after a blank line:

  ```
  ---
  🤖 *Written by Claude (Claude Code), posted from this account.*
  ```

  PR descriptions and commit messages already carry their own attribution lines.
