# frozen_string_literal: true

# Pages in site/ and templates in templates/ are plain HTML with no templating
# engine, so what they must share is checked here.
RSpec.describe 'Site pages' do
  def page_paths
    %w[site/index.html site/today.html site/yesterday.html site/calendar/index.html
       site/selections.html site/mountweazel.html templates/selection.html templates/404.html]
  end

  def page(path)
    path = "site/#{path}" unless path.start_with?('site/', 'templates/')
    File.read(File.join(ROOT, path))
  end

  # The marked layout block, with page-specific parts normalized: the root
  # prefix ("../", and "../" for "./" on the home link) and which nav item is active.
  def layout(html, block)
    section = html[%r{<!-- layout:#{block} -->.*<!-- /layout:#{block} -->}m]
    section&.gsub('href="../"', 'href="./"')&.gsub('href="../', 'href="')&.gsub(/class="(in)?active"/, 'class="NAV"')
  end

  describe 'layout' do
    it 'is the same navbar and footer on every page and template' do
      pages = page_paths.to_h { |path| [path, page(path)] }
      %w[navbar footer].each do |block|
        layouts = pages.transform_values { |html| layout(html, block) }
        expect(layouts.values).to all(be_a(String))
        expect(layouts.values.uniq.size).to eq(1), "#{block} differs: #{layouts.keys.join(', ')}"
      end
    end
  end

  describe 'body' do
    it 'tells the scripts what the page shows and where the site root is' do
      expect(page('index.html')).to include('data-page="today" data-root="."')
      expect(page('today.html')).to include('data-page="today" data-root="."')
      expect(page('yesterday.html')).to include('data-page="yesterday" data-root="."')
      expect(page('calendar/index.html')).to include('data-page="today" data-root=".."')
      expect(page('selections.html')).to include('data-page="selections" data-root="."')
      expect(page('templates/selection.html')).to include('data-page="selection" data-root=".."')
      expect(page('mountweazel.html')).to include('data-page="mountweazel" data-root="."')
      expect(page('templates/404.html')).to include('data-page="not-found" data-root="."')
    end
  end

  describe 'navbar' do
    it 'highlights Today, Yesterday or Selections on its own page only' do
      expect(page('today.html')).to include('<li class="active"><a href="today">Today</a></li>')
      expect(page('yesterday.html')).to include('<li class="active"><a href="yesterday">Yesterday</a></li>')
      expect(page('selections.html')).to include('<li class="active"><a href="selections">Selections</a></li>')
      %w[index.html calendar/index.html mountweazel.html templates/selection.html templates/404.html].each do |path|
        expect(page(path)).not_to include('class="active"'), path
      end
    end
  end

  describe 'links' do
    it 'stay relative, so the site works under /sweepers-publisher/ and at a domain root' do
      expect(page('calendar/index.html')).to include('href="../assets/stylesheets/sweepers.css"',
                                                     'src="../assets/javascripts/calendar.js"')
      expect(page('today.html')).to include('href="assets/stylesheets/sweepers.css"', 'src="assets/javascripts/pages.js"')
      expect(page('templates/selection.html')).to include('href="../assets/stylesheets/sweepers.css"', 'href="../selections"')
      expect(pages_with_root_absolute_links).to be_empty
    end
  end

  describe 'navbar links' do
    it "link only to the site's own pages, not the old blog or Twitter (sweepers-editor#84)" do
      offsite = page_paths.select { |path| page(path).match?(/blogspot|twitter\.com|navbar-right/) }
      expect(offsite).to be_empty
    end
  end

  describe 'scripts' do
    it 'loads calendar.js before pages.js, which needs it' do
      page_paths.each do |path|
        html = page(path)
        expect(html.index('calendar.js')).to be < html.index('pages.js'), path
      end
    end
  end

  describe 'CDN assets' do
    it 'carry an integrity hash and crossorigin, except Google Fonts (sweepers-editor#87)' do
      tags = cdn_asset_tags
      expect(tags.size).to eq(24) # 3 on each of the 8 pages and templates
      expect(tags.reject { |_, tag| tag.match?(/ integrity="sha384-[A-Za-z0-9+\/]{64}" crossorigin="anonymous"/) }).to be_empty
    end
  end

  describe 'templates' do
    it 'live outside site/, so they are never published as is' do
      %w[selection.html 404.html].each do |name|
        expect(File.exist?(File.join(ROOT, 'site', name))).to be(false), name
        expect(File.exist?(File.join(ROOT, 'templates', name))).to be(true), name
      end
    end
  end

  describe '404 template' do
    it 'resolves its links from the site root, wherever Pages serves it' do
      expect(page('templates/404.html')).to include('<base href="{{base_path}}/">', '<title>Page Not Found</title>')
    end
  end

  describe 'calendar mountweazel page' do
    it 'redirects to /mountweazel, with a link if the redirect fails (sweepers-editor#85)' do
      expect(page('calendar/mountweazel.html')).to include(
        '<meta http-equiv="refresh" content="0; url=../mountweazel">', '<link rel="canonical" href="../mountweazel">',
        '<meta name="robots" content="noindex">', "window.location.replace('../mountweazel'",
        '<a href="../mountweazel">'
      )
    end
  end

  # Every <script> and stylesheet <link> loaded from another host, as [path, tag]. Google Fonts
  # is left out: it varies its CSS by browser, so it can't have a fixed hash.
  def cdn_asset_tags
    Dir[File.join(ROOT, '{site,templates}', '**', '*.html')].flat_map do |path|
      File.read(path).scan(%r{<(?:script|link)\b[^>]*(?:src|href)="https://[^"]+"[^>]*>})
          .select { |tag| tag.start_with?('<script') || tag.include?('rel="stylesheet"') }
          .reject { |tag| tag.include?('fonts.googleapis.com') }
          .map { |tag| [path.delete_prefix("#{ROOT}/"), tag] }
    end
  end

  def pages_with_root_absolute_links
    Dir[File.join(ROOT, '{site,templates}', '**', '*.html')].select { |path| File.read(path).match?(%r{(href|src)="/(?!/)}) }
  end
end
