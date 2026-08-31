class Warehouse::FinancialStatementExtraction::PageLocator
  class LocationError < StandardError; end

  Result = Data.define(:page_count, :page_texts, :position_page, :operations_page, :candidate_pages, :ocr_pages)

  TITLE_PATTERNS = {
    position: [
      /\b(?:consolidated\s+)?statement\s+of\s+financial\s+position\b/i,
      /\b(?:consolidated\s+)?statement\s+of\s+financial\s+[a-z]{1,3}\s+position\b/i,
      /\b(?:état|etat)\s+(?:consolidé|consolide)?\s*(?:de la|de)\s+situation financi(?:è|e)re\b/i
    ],
    operations: [
      /\b(?:consolidated\s+)?statement\s+of\s+operations(?:\s+and\s+accumulated\s+surplus)?\b/i,
      /\b(?:consolidated\s+)?statement\s+of\s+financial\s+activities\b/i,
      /\b(?:état|etat)\s+(?:consolidé|consolide)?\s*(?:des|de l['’])\s*(?:résultats|resultats|activités financières|activites financieres)\b/i
    ]
  }.freeze
  EXPLICIT_NON_PRIMARY = /\b(?:schedule|appendix|note|annexe|cédule|cedule|exhibit|by fund)\b/i
  CONTENTS = /\b(?:table of contents|contents|index to (?:the )?(?:consolidated )?financial statements|table des mati(?:è|e)res|sommaire)\b/i
  NOTES_HEADING = /\b(?:notes? to (?:the )?(?:consolidated )?financial statements|notes? aux (?:états|etats) financiers)\b/i
  AUDITOR_HEADING = /\b(?:independent auditors?|auditeurs? ind(?:é|e)pendants?|rapport de l['’]auditeur)\b/i
  MALFORMED_OCR_NUMBER = /\d[\d,.]*\.\d{2}[\]\}]/
  OCR_CACHE_POLICY_VERSION = 1

  def initialize(pdf_path, pdftotext: "pdftotext", pdfinfo: "pdfinfo", pdftoppm: "pdftoppm", tesseract: "tesseract",
    pdfseparate: "pdfseparate", pdfunite: "pdfunite", ghostscript: "gs", max_ocr_pages: 20,
    ocr_concurrency: ENV.fetch("MUNICIPAL_FINANCIAL_OCR_CONCURRENCY", 4).to_i, imagemagick: "magick",
    ocr_cache_root: ENV["MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT"], ocr_cache_reporter: nil)
    @pdf_path = Pathname(pdf_path)
    @pdftotext = pdftotext
    @pdfinfo = pdfinfo
    @pdftoppm = pdftoppm
    @tesseract = tesseract
    @pdfseparate = pdfseparate
    @pdfunite = pdfunite
    @ghostscript = ghostscript
    @imagemagick = imagemagick
    @max_ocr_pages = max_ocr_pages
    @ocr_concurrency = [ Integer(ocr_concurrency), 1 ].max
    @ocr_dpi = ENV.fetch("MUNICIPAL_FINANCIAL_OCR_DPI", 300).to_i
    @page_rotation = 0
    @source_page_landscape = false
    @ocr_cache = Warehouse::FinancialStatementExtraction::OcrTextCache.new(
      root: ocr_cache_root, source_path: @pdf_path, reporter: ocr_cache_reporter
    )
  end

  def locate
    validate_pdf!
    page_count = read_page_count
    page_texts = extract_page_texts(page_count)
    ocr_pages = []
    if needs_ocr?(page_texts)
      page_texts, ocr_pages = fill_blank_pages_with_bounded_ocr(page_texts)
    end

    position_page = locate_page(page_texts, :position)
    operations_page = locate_page(page_texts, :operations)
    raise LocationError, "statement of financial position not found" unless position_page
    raise LocationError, "statement of operations not found" unless operations_page

    candidates = [ position_page, operations_page ].flat_map { |page| [ page - 1, page, page + 1 ] }
      .select { |page| page.between?(1, page_count) }.uniq.sort
    Result.new(page_count:, page_texts:, position_page:, operations_page:, candidate_pages: candidates, ocr_pages:)
  end

  def with_excerpt(pages)
    pages = pages.map { |page| Integer(page) }.uniq.sort
    raise ArgumentError, "at least one page is required" if pages.empty?

    Dir.mktmpdir("financial-statement-excerpt") do |directory|
      parts = pages.map do |page|
        pattern = File.join(directory, "source-page-%d.pdf")
        stdout, stderr, status = Open3.capture3(@pdfseparate, "-f", page.to_s, "-l", page.to_s, @pdf_path.to_s, pattern)
        raise LocationError, "pdfseparate page #{page} failed: #{stderr.presence || stdout}" unless status.success?
        File.join(directory, "source-page-#{page}.pdf")
      end
      excerpt = File.join(directory, "statement-pages.pdf")
      stdout, stderr, status = Open3.capture3(@pdfunite, *parts, excerpt)
      if status.success?
        normalized_excerpt = File.join(directory, "normalized-statement-pages.pdf")
        normalized = normalize_excerpt_with_ghostscript(excerpt, normalized_excerpt)
        yield Pathname(normalized ? normalized_excerpt : excerpt)
      else
        render_excerpt_with_ghostscript(pages, excerpt)
        yield Pathname(excerpt)
      end
    end
  end

  def ocr_table_page(page)
    page = Integer(page)
    @table_ocr_text ||= {}
    return @table_ocr_text.fetch(page) if @table_ocr_text.key?(page)

    @table_ocr_text[page] = @ocr_cache.fetch(
      page:, mode: "table", options: ocr_cache_options("table")
    ) { perform_table_ocr(page) }
  end

  private

  def perform_table_ocr(page)
    Dir.mktmpdir("financial-statement-table-ocr") do |directory|
      image = render_ocr_image(page, directory:, name: "page", dpi: @ocr_dpi)
      thresholded = File.join(directory, "page-thresholded.png")
      _stdout, _stderr, status = Open3.capture3(
        @imagemagick, image, "-colorspace", "Gray", "-threshold", "45%", thresholded
      )
      return ocr_page(page) unless status.success?

      text = run_tesseract(tesseract_args(thresholded, psm: 6, preserve_interword_spaces: true), page:)
      normalize_table_ocr_digit_fragments(text)
    end
  rescue Errno::ENOENT
    ocr_page(page)
  end

  def needs_ocr?(page_texts)
    %i[position operations].any? do |kind|
      page = locate_page(page_texts, kind)
      page.nil? || !primary_heading?(page_texts.fetch(page).lines.first(12).join, kind:)
    end
  end

  def normalize_excerpt_with_ghostscript(excerpt, normalized_excerpt)
    _stdout, _stderr, status = Open3.capture3(
      @ghostscript, "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pdfwrite",
      "-sOutputFile=#{normalized_excerpt}", excerpt
    )
    status.success?
  rescue Errno::ENOENT
    false
  end

  def render_excerpt_with_ghostscript(pages, excerpt)
    stdout, stderr, status = Open3.capture3(
      @ghostscript, "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pdfwrite",
      "-sPageList=#{pages.join(',')}", "-sOutputFile=#{excerpt}", @pdf_path.to_s
    )
    raise LocationError, "encrypted PDF excerpt failed: #{stderr.presence || stdout}" unless status.success?
  rescue Errno::ENOENT
    raise LocationError, "encrypted PDF requires Ghostscript to create a statement excerpt"
  end

  def validate_pdf!
    raise LocationError, "missing PDF #{@pdf_path}" unless @pdf_path.file?
    raise LocationError, "source is not a PDF" unless @pdf_path.binread(5) == "%PDF-"
  end

  def read_page_count
    stdout, stderr, status = Open3.capture3(@pdfinfo, @pdf_path.to_s)
    raise LocationError, "pdfinfo failed: #{stderr}" unless status.success?
    match = stdout.match(/^Pages:\s+(\d+)$/)
    raise LocationError, "pdfinfo did not report a page count" unless match

    @page_rotation = stdout[/^Page rot:\s+(\d+)$/, 1].to_i % 360
    if (size = stdout.match(/^Page size:\s+([\d.]+) x ([\d.]+) pts/))
      @source_page_landscape = size[1].to_f > size[2].to_f
    end
    Integer(match[1])
  end

  def extract_page_texts(page_count)
    stdout, stderr, status = Open3.capture3(@pdftotext, "-layout", "-enc", "UTF-8", @pdf_path.to_s, "-")
    raise LocationError, "pdftotext failed: #{stderr}" unless status.success?

    pages = stdout.force_encoding(Encoding::UTF_8).scrub.split("\f", -1)
    pages.pop while pages.length > page_count && pages.last.to_s.empty?
    pages.fill("", pages.length...page_count)
    pages.first(page_count).map.with_index(1) { |text, page| [ page, text ] }.to_h
  end

  def locate_page(page_texts, kind)
    matches = page_texts.filter_map do |page, text|
      matches = TITLE_PATTERNS.fetch(kind).any? { |pattern| text.match?(pattern) }
      next unless matches

      heading = text.lines.first(12).join
      [ score(text), page, primary_heading?(heading, kind:), heading ]
    end
    auditor_page = page_texts.filter_map do |page, text|
      page if text.lines.first(12).join.match?(AUDITOR_HEADING)
    end.min
    primary_after_auditor = matches.select do |score, page, primary, heading|
      primary && score.positive? && !heading.match?(NOTES_HEADING) &&
        !heading.match?(AUDITOR_HEADING) &&
        (auditor_page.nil? || page > auditor_page)
    end
    return primary_after_auditor.min_by { |_, page, _, _| page }&.at(1) if primary_after_auditor.any?

    matches.max_by { |score, page, _, _| [ score, -page ] }&.at(1)
  end

  def score(text)
    score = text.scan(/(?:\(?\d[\d ,.\u00A0\u202F]*\)?)/).count { |token| token.scan(/\d/).length >= 3 }
    heading = text.lines.first(12).join
    primary_title = primary_heading?(heading)
    score += 120 if primary_title
    score -= 200 if text.match?(CONTENTS)
    score -= 180 if heading.match?(NOTES_HEADING)
    score -= 120 if heading.match?(AUDITOR_HEADING)
    score -= 100 if !primary_title && heading.match?(EXPLICIT_NON_PRIMARY)
    score
  end

  def primary_heading?(heading, kind: nil)
    return false if heading.lines.first(4).join.match?(EXPLICIT_NON_PRIMARY)

    patterns = kind ? TITLE_PATTERNS.fetch(kind) : TITLE_PATTERNS.values.flatten
    title = Regexp.union(patterns)
    heading.lines.any? do |line|
      stripped = line.strip
      stripped.match?(/\A(?:consolidated\s+statement|statement|état|etat)\b/i) && stripped.match?(title)
    end
  end

  def fill_blank_pages_with_bounded_ocr(page_texts)
    pages = page_texts.select { |_, text| text.gsub(/\s/, "").length < 40 }.keys.first(@max_ocr_pages)
    queue = Queue.new
    pages.each { queue << _1 }
    results = {}
    results_mutex = Mutex.new
    errors = Queue.new
    workers = [ @ocr_concurrency, pages.length ].min.times.map do
      Thread.new do
        loop do
          page = queue.pop(true)
          text = ocr_page(page)
          results_mutex.synchronize { results[page] = text }
        rescue ThreadError
          break
        rescue => error
          errors << error
          break
        end
      end
    end
    workers.each(&:join)
    raise errors.pop unless errors.empty?

    results.each { |page, text| page_texts[page] = text }
    [ page_texts, pages ]
  end

  def ocr_page(page)
    @ocr_cache.fetch(page:, mode: "plain", options: ocr_cache_options("plain")) do
      perform_page_ocr(page)
    end
  end

  def perform_page_ocr(page)
    Dir.mktmpdir("financial-statement-ocr") do |directory|
      image = render_ocr_image(page, directory:, name: "page", dpi: @ocr_dpi)
      text = run_tesseract(tesseract_args(image), page:)
      if text.match?(MALFORMED_OCR_NUMBER)
        dense_image = render_ocr_image(
          page, directory:, name: "page-dense", dpi: [ @ocr_dpi, 400 ].max
        )
        dense_text = run_tesseract(tesseract_args(dense_image, psm: 6), page:)
        text = dense_text if malformed_ocr_number_count(dense_text) < malformed_ocr_number_count(text)
      end
      text
    end
  end

  def ocr_cache_options(mode)
    @ocr_cache_options ||= {}
    orientation_key = [ mode, @page_rotation, @source_page_landscape ]
    @ocr_cache_options[orientation_key] ||= {
      policy_version: OCR_CACHE_POLICY_VERSION,
      dpi: @ocr_dpi,
      page_rotation: @page_rotation,
      source_page_landscape: @source_page_landscape,
      pdftoppm: executable_signature(@pdftoppm),
      tesseract: executable_signature(@tesseract),
      tessdata: tessdata_signature,
      language: "eng+fra",
      mode_options: mode == "table" ? {
        imagemagick: executable_signature(@imagemagick), threshold: "45%", psm: 6,
        preserve_interword_spaces: true, digit_fragment_normalizer: 1
      } : {
        psm: nil, dense_retry_dpi: [ @ocr_dpi, 400 ].max,
        dense_retry_psm: 6, malformed_number_pattern: MALFORMED_OCR_NUMBER.source
      }
    }
  end

  def executable_signature(command)
    path = if Pathname(command).absolute?
      Pathname(command)
    else
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
        .map { Pathname(_1).join(command) }.find(&:executable?)
    end
    return { command:, resolved: nil } unless path&.file?

    stat = path.stat
    { command:, resolved: path.realpath.to_s, size: stat.size, mtime_ns: stat.mtime.nsec,
      mtime: stat.mtime.to_i }
  rescue SystemCallError
    { command:, resolved: nil }
  end

  def tessdata_signature
    root = Pathname("/Volumes/floppy/york_factory/ocr/tessdata")
    %w[eng fra].to_h do |language|
      path = root.join("#{language}.traineddata")
      next [ language, nil ] unless path.file?

      stat = path.stat
      [ language, { path: path.to_s, size: stat.size, mtime: stat.mtime.to_i, mtime_ns: stat.mtime.nsec } ]
    end
  end

  def render_ocr_image(page, directory:, name:, dpi:)
    output = File.join(directory, name)
    stdout, stderr, status = Open3.capture3(
      @pdftoppm, "-f", page.to_s, "-l", page.to_s, "-singlefile",
      "-r", dpi.to_s, "-png", @pdf_path.to_s, output
    )
    raise LocationError, "pdftoppm page #{page} failed: #{stderr.presence || stdout}" unless status.success?

    correct_ocr_orientation("#{output}.png", directory:, name:)
  end

  def correct_ocr_orientation(image, directory:, name:)
    correction = (360 - @page_rotation) % 360
    return image unless correction.in?([ 90, 270 ])
    return image if @source_page_landscape

    oriented = File.join(directory, "#{name}-oriented.png")
    _stdout, _stderr, status = Open3.capture3(
      @imagemagick, image, "-rotate", correction.to_s, oriented
    )
    status.success? ? oriented : image
  rescue Errno::ENOENT
    image
  end

  def tesseract_args(image, psm: nil, preserve_interword_spaces: false)
    args = [ @tesseract, image, "stdout", "-l", "eng+fra" ]
    tessdata = Pathname("/Volumes/floppy/york_factory/ocr/tessdata")
    args += [ "--tessdata-dir", tessdata.to_s ] if tessdata.directory?
    args += [ "--psm", psm.to_s ] if psm
    args += [ "-c", "preserve_interword_spaces=1" ] if preserve_interword_spaces
    args
  end

  def run_tesseract(args, page:)
    stdout, stderr, status = Open3.capture3(*args)
    raise LocationError, "tesseract page #{page} failed: #{stderr}" unless status.success?

    stdout.force_encoding(Encoding::UTF_8).scrub
  end

  def malformed_ocr_number_count(text)
    text.scan(MALFORMED_OCR_NUMBER).length
  end

  def normalize_table_ocr_digit_fragments(text)
    text.gsub(/(?<![A-Za-z0-9.,])[LlI](?=(?:,\d{3}){2,}(?!\d))/, "1")
      .gsub(/(?<=\d) (?=\d)/, "")
  end
end
