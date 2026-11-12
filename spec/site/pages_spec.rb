# frozen_string_literal: true

# The page shells in site/ and shells/ are plain HTML with no templating, so
# their shared layout (navbar and footer) is checked here instead.
RSpec.describe 'site page shells' do
  def shell_paths
    %w[site/index.html site/today.html site/yesterday.html site/calendar/index.html
       site/selections.html shells/selection.html]
  end

  def shell(path)
    path = "site/#{path}" unless path.start_with?('site/', 'shells/')
    File.read(File.join(ROOT, path))
  end

  # The marked layout block, with page-specific parts normalized: the root
  # prefix ("../", and "../" for "./" on the home link) and which nav item is active.
  def layout(html, block)
    section = html[%r{<!-- layout:#{block} -->.*<!-- /layout:#{block} -->}m]
    section&.gsub('href="../"', 'href="./"')&.gsub('href="../', 'href="')&.gsub(/class="(in)?active"/, 'class="NAV"')
  end

  it 'share one navbar and one footer' do
    pages = shell_paths.to_h { |path| [path, shell(path)] }
    %w[navbar footer].each do |block|
      layouts = pages.transform_values { |html| layout(html, block) }
      expect(layouts.values).to all(be_a(String))
      expect(layouts.values.uniq.size).to eq(1), "#{block} differs: #{layouts.keys.join(', ')}"
    end
  end

  it 'mark which leaf each page shows and where the site root is' do
    expect(shell('index.html')).to include('data-page="today" data-root="."')
    expect(shell('today.html')).to include('data-page="today" data-root="."')
    expect(shell('yesterday.html')).to include('data-page="yesterday" data-root="."')
    expect(shell('calendar/index.html')).to include('data-page="today" data-root=".."')
    expect(shell('selections.html')).to include('data-page="selections" data-root="."')
    expect(shell('shells/selection.html')).to include('data-page="selection" data-root=".."')
  end

  it 'highlight Today on /today and Yesterday on /yesterday only' do
    expect(shell('today.html')).to include('<li class="active"><a href="today">Today</a></li>')
    expect(shell('yesterday.html')).to include('<li class="active"><a href="yesterday">Yesterday</a></li>')
    expect(shell('selections.html')).to include('<li class="active"><a href="selections">Selections</a></li>')
    expect(shell('index.html')).not_to include('class="active"')
    expect(shell('calendar/index.html')).not_to include('class="active"')
    expect(shell('shells/selection.html')).not_to include('class="active"')
  end

  it 'keep the selection shell out of site/, so the bare shell is never published' do
    expect(File.exist?(File.join(ROOT, 'site', 'selection.html'))).to be(false)
    expect(shell('shells/selection.html')).to include('href="../assets/stylesheets/sweepers.css"', 'href="../selections"')
  end

  it 'load assets relative to the root, so the site works under /sweepers-publisher/ and at /' do
    expect(shell('calendar/index.html')).to include('href="../assets/stylesheets/sweepers.css"', 'src="../assets/javascripts/sweepers.js"')
    expect(shell('today.html')).to include('href="assets/stylesheets/sweepers.css"', 'src="assets/javascripts/sweepers.js"')
    expect(pages_with_root_absolute_links).to be_empty
  end

  def pages_with_root_absolute_links
    Dir[File.join(ROOT, '{site,shells}', '**', '*.html')].select { |path| File.read(path).match?(/(href|src)="\/(?!\/)/) }
  end
end
