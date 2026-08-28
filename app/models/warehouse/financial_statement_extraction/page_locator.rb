class Warehouse::FinancialStatementExtraction::PageLocator
  class LocationError < StandardError; end

  Result = Data.define(:page_count, :page_texts, :position_page, :operations_page, :candidate_pages, :ocr_pages)

  TITLE_PATTERNS = {
    position: [
      /\b(?:consolidated\s+)?statement\s+of\s+financial\s+position\b/i,
      /\b(?:état|etat)\s+(?:consolidé|consolide)?\s*(?:de la|de)\s+situation financi(?:è|e)re\b/i
    ],
    operations: [
      /\b(?:consolidated\s+)?statement\s+of\s+operations(?:\s+and\s+accumulated\s+surplus)?\b/i,
      /\b(?:état|etat)\s+(?:consolidé|consolide)?\s*(?:des|de l['’])\s*(?:résultats|resultats|activités financières|activites financieres)\b/i
    ]
  }.freeze
  EXPLICIT_NON_PRIMARY = /\b(?:schedule|appendix|note|annexe|cédule|cedule)\b/i
  CONTENTS = /\b(?:table of contents|contents|table des mati(?:è|e)res|sommaire)\b/i
  NOTES_HEADING = /\b(?:notes? to (?:the )?(?:consolidated )?financial statements|notes? aux (?:états|etats) financiers)\b/i
  AUDITOR_HEADING = /\b(?:independent auditors?|auditeurs? ind(?:é|e)pendants?|rapport de l['’]auditeur)\b/i

  def initialize(pdf_path, pdftotext: "pdftotext", pdfinfo: "pdfinfo", pdftoppm: "pdftoppm", tesseract: "tesseract",
    pdfseparate: "pdfseparate", pdfunite: "pdfunite", ghostscript: "gs", max_ocr_pages: 20)
    @pdf_path = Pathname(pdf_path)
    @pdftotext = pdftotext
    @pdfinfo = pdfinfo
    @pdftoppm = pdftoppm
    @tesseract = tesseract
    @pdfseparate = pdfseparate
    @pdfunite = pdfunite
    @ghostscript = ghostscript
    @max_ocr_pages = max_ocr_pages
  end

  def locate
    validate_pdf!
    page_count = read_page_count
    page_texts = extract_page_texts(page_count)
    ocr_pages = []
    if locate_page(page_texts, :position).nil? || locate_page(page_texts, :operations).nil?
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
      render_excerpt_with_ghostscript(pages, excerpt) unless status.success?
      yield Pathname(excerpt)
    end
  end

  private

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
      [ score(text), page, primary_heading?(heading), heading ]
    end
    auditor_page = page_texts.filter_map do |page, text|
      page if text.lines.first(12).join.match?(AUDITOR_HEADING)
    end.min
    primary_after_auditor = matches.select do |score, page, primary, heading|
      primary && score.positive? && !heading.match?(NOTES_HEADING) &&
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

  def primary_heading?(heading)
    heading.match?(TITLE_PATTERNS.values.flatten.then { |patterns| Regexp.union(patterns) })
  end

  def fill_blank_pages_with_bounded_ocr(page_texts)
    pages = page_texts.select { |_, text| text.gsub(/\s/, "").length < 40 }.keys.first(@max_ocr_pages)
    pages.each { |page| page_texts[page] = ocr_page(page) }
    [ page_texts, pages ]
  end

  def ocr_page(page)
    Dir.mktmpdir("financial-statement-ocr") do |directory|
      output = File.join(directory, "page")
      stdout, stderr, status = Open3.capture3(@pdftoppm, "-f", page.to_s, "-l", page.to_s, "-singlefile", "-r", "180", "-png", @pdf_path.to_s, output)
      raise LocationError, "pdftoppm page #{page} failed: #{stderr.presence || stdout}" unless status.success?
      image = "#{output}.png"
      tessdata = Pathname("/Volumes/floppy/york_factory/ocr/tessdata")
      args = [ @tesseract, image, "stdout", "-l", "eng+fra" ]
      args += [ "--tessdata-dir", tessdata.to_s ] if tessdata.directory?
      stdout, stderr, status = Open3.capture3(*args)
      raise LocationError, "tesseract page #{page} failed: #{stderr}" unless status.success?
      stdout.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
