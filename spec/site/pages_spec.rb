# frozen_string_literal: true

# Pages in site/ and templates in templates/ are plain HTML with no templating
# engine, so what they must share is checked here.
RSpec.describe 'Site pages' do
  def page_paths
    %w[site/index.html site/today.html site/yesterday.html site/calendar/index.html
       site/selections.html templates/selection.html]
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
    end
  end

  describe 'navbar' do
    it 'highlights Today, Yesterday or Selections on its own page only' do
      expect(page('today.html')).to include('<li class="active"><a href="today">Today</a></li>')
      expect(page('yesterday.html')).to include('<li class="active"><a href="yesterday">Yesterday</a></li>')
      expect(page('selections.html')).to include('<li class="active"><a href="selections">Selections</a></li>')
      %w[index.html calendar/index.html templates/selection.html].each do |path|
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

  describe 'scripts' do
    it 'loads calendar.js before pages.js, which needs it' do
      page_paths.each do |path|
        html = page(path)
        expect(html.index('calendar.js')).to be < html.index('pages.js'), path
      end
    end
  end

  describe 'selection template' do
    it 'lives outside site/, so it is never published as is' do
      expect(File.exist?(File.join(ROOT, 'site', 'selection.html'))).to be(false)
      expect(File.exist?(File.join(ROOT, 'templates', 'selection.html'))).to be(true)
    end
  end

  def pages_with_root_absolute_links
    Dir[File.join(ROOT, '{site,templates}', '**', '*.html')].select { |path| File.read(path).match?(%r{(href|src)="/(?!/)}) }
  end
end
