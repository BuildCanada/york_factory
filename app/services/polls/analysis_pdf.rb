require "base64"
require "timeout"

module Polls
  class AnalysisPdf
    def initialize(poll, locale)
      @poll, @locale = poll, locale
    end

    def render
      html = document_html
      options = { headless: true, timeout: 60, process_timeout: 30 }
      options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
      # Container deployments can opt out of Chromium's sandbox if their runtime
      # disables unprivileged user namespaces. Local Chromium keeps its sandbox.
      options[:browser_options] = { "no-sandbox" => nil } if ENV["CHROME_NO_SANDBOX"] == "1"
      browser = Ferrum::Browser.new(**options)
      browser.network.intercept
      browser.on(:request) { |request| request.abort }
      browser.page.content = html
      loaded = browser.evaluate_async("Promise.all([document.fonts.ready, ...Array.from(document.images, image => image.decode())]).then(() => arguments[0](true), () => arguments[0](false))", 30)
      raise "A report image could not be rendered" unless loaded
      pdf = Base64.decode64(browser.pdf(format: :letter, print_background: true, prefer_css_page_size: true,
        display_header_footer: false))
      raise "Chromium returned an invalid PDF" unless pdf.start_with?("%PDF-")
      pdf
    ensure
      browser&.quit
    end

    def document_html
      @title = @poll.public_send("title_#{@locale}").presence || @poll.title_en
      @date = @poll.published_at&.strftime("%B %-d, %Y") || (@locale == "fr" ? "Ébauche" : "Draft")
      @body = render_markdown(@poll.public_send("body_#{@locale}"))
      @appendix = render_markdown(@poll.public_send("appendix_#{@locale}"))
      @methodology = render_markdown(@poll.public_send("methodology_#{@locale}"))
      @takeaways = @poll.public_send("key_messages_#{@locale}").presence || @poll.key_messages_en
      ERB.new(Rails.root.join("app/views/polls/reports/analysis.html.erb").read).result(binding)
    end

    private

    def e(value) = ERB::Util.html_escape(value)

    def css_string(value)
      '"' + value.to_s.codepoints.map { |code| "\\#{code.to_s(16)} " }.join + '"'
    end

    def font(name)
      "data:font/woff2;base64,#{Base64.strict_encode64(Rails.root.join('vendor/poll_reports/fonts', name).binread)}"
    end

    def cover_logo
      "data:image/svg+xml;base64,#{Base64.strict_encode64(Rails.root.join('vendor/poll_reports/logo-square.svg').binread)}"
    end

    def logo(size = 256.3077)
      svg = Nokogiri::XML(Rails.root.join("vendor/poll_reports/logo-polling.svg").read)
      svg.root["width"] = size.to_s
      svg.root["height"] = (size * 60.0 / 190.4).to_s
      style = Nokogiri::XML::Node.new("style", svg)
      style.content = "@font-face { font-family: Soehne; src: url(#{font('soehne-kraftig.woff2')}); font-weight: 500; }"
      svg.root.children.first.add_previous_sibling(style)
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg.to_xml)}"
    end

    def survey_scope_label
      return "#{@poll.survey_scope.capitalize} poll" unless @locale == "fr"
      { "national" => "Sondage national", "provincial" => "Sondage provincial", "municipal" => "Sondage municipal" }.fetch(@poll.survey_scope)
    end

    def poll_url
      "https://buildcanada.com/polls/#{ERB::Util.url_encode(@poll.slug)}"
    end

    def render_markdown(markdown)
      return "" if markdown.blank?
      safe = Rails::HTML5::SafeListSanitizer.new.sanitize(Markdown::Renderer.call(markdown),
        tags: %w[p h1 h2 h3 h4 h5 h6 ul ol li strong em b i a blockquote pre code span table thead tbody tr th td hr br figure img sup sub del],
        attributes: %w[href src alt title colspan rowspan start class lang])
      doc = Nokogiri::HTML.fragment(safe)
      doc.css("pre").each do |pre|
        code = pre.at_css("code")
        next unless pre["lang"] == "buildcanada-chart" || code&.[]("class").to_s.split.include?("language-buildcanada-chart")
        definition = JSON.parse(code ? code.text : pre.text)
        svg = render_chart(definition)
        figure = Nokogiri::XML::Node.new("figure", doc)
        image = Nokogiri::XML::Node.new("img", doc)
        image["src"] = "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
        image["alt"] = definition.dig("definition", "title").to_s
        figure.add_child(image)
        pre.replace(figure)
      end
      doc.css("img").each do |image|
        next if image["src"].to_s.match?(%r{\Adata:image/(?:png|jpeg|webp|svg\+xml);base64,})
        match = image["src"].to_s.match(HasLocalizedMarkdown::BLOB_PATH_PATTERN)
        blob = match && ActiveStorage::Blob.find_signed(match[:signed_id])
        unless blob && @poll.content_images.blobs.exists?(id: blob.id) && blob.content_type.in?(%w[image/png image/jpeg image/webp])
          raise ArgumentError, "Report images must be uploaded through the CMS editor (#{image['alt']})."
        end
        image["src"] = "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.download)}"
      end
      doc.to_html
    end

    def render_chart(bundle)
      definition = bundle.fetch("definition")
      raise ArgumentError, "Report charts must use inline data" unless definition["data"] == "inline"
      Dir.mktmpdir("poll-chart") do |dir|
        dataset = File.join(dir, "dataset.json")
        input = File.join(dir, "definition.json")
        output = File.join(dir, "chart.svg")
        File.write(dataset, JSON.generate(bundle.fetch("dataset")))
        File.write(input, JSON.generate(definition.merge("data" => dataset)))
        cli = ENV["CHARTS_BIN"].presence || Rails.root.join("reports/node_modules/.bin/charts").to_s
        run_chart(cli, "validate", input)
        run_chart(cli, "render", input, "--width", "960", "--height", "600", "--locale", @locale, "--out", output)
        svg = Nokogiri::XML(File.binread(output))
        style = Nokogiri::XML::Node.new("style", svg)
        style.content = "@font-face { font-family: 'Söhne Kräftig'; src: url(#{font('soehne-kraftig.woff2')}); } @font-face { font-family: 'Founders Grotesk Mono'; src: url(#{font('founders-grotesk-mono-regular.woff2')}); }"
        svg.root.children.first.add_previous_sibling(style)
        svg.to_xml
      end
    end

    def run_chart(*args)
      Tempfile.create("chart-log") do |log|
        pid = Process.spawn(*args, out: log, err: log, pgroup: true)
        begin
          _, status = Timeout.timeout(45) { Process.wait2(pid) }
          raise ArgumentError, "Chart rendering failed: #{File.read(log.path).truncate(1000)}" unless status.success?
        rescue Timeout::Error
          Process.kill("KILL", -pid) rescue nil
          Process.wait(pid) rescue nil
          raise ArgumentError, "Chart rendering exceeded 45 seconds"
        end
      end
    end
  end
end
