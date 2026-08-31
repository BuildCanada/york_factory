#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "uri"

class SanitizeMunicipalReportBatch
  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  YEAR_PATTERN = /(?<!\d)(19[89]\d|20\d{2})(?!\d)/
  PROGRAM_REPORT_PATTERN = /(?:\bccbf\b|\bstp\b|accessibility[\s_-]*(?:advisory|plan)|annual[\s_-]*report[\s_-]*(?:on|of)[\s_-]*building[\s_-]*fees|board[\s_-]*of[\s_-]*health|fraud[\s_-]*and[\s_-]*waste|integrity[\s_-]*commissioner|lobbyist[\s_-]*registrar|municipal[\s_-]*(?:heritage|accessibility)[\s_-]*(?:advisory[\s_-]*)?committee|public[\s_-]*health[\s_-]*(?:services?[\s_-]*)?annual|quality[\s_-]*initiative|sewage[\s_-]*treatment|trust[\s_-]*fund|wastewater[\s_-]*(?:collection|treatment)|lagoon[\s_-]*annual|county[\s_-]*forest[\s_-]*annual|rapport[\s_-]*annuel[\s_-]*(?:sur[\s_-]*(?:l['’])?)?(?:application[\s_-]*(?:du[\s_-]*)?r[èe]glement|gestion[\s_-]*contractuelle|service[\s_-]*(?:de[\s_-]*)?(?:s[ée]curit[ée][\s_-]*incendie|incendie)|station[\s_-]*d['’]?[ée]puration|eaux?[\s_-]*us[ée]es?))/i
  SUBSIDIARY_FINANCIAL_PATTERN = /(?:(?:cemetery|trust[\s_-]*fund|police[\s_-]*(?:services?|board)|public[\s_-]*library|waterworks|utilities[\s_-]*[.,]?[\s_-]*(?:inc(?:orporated)?|corp(?:oration)?|ltd|limited|commission)\b)[\s\S]{0,240}financial[\s_-]*statements?|financial[\s_-]*statements?[\s\S]{0,240}(?:cemetery|trust[\s_-]*fund|police[\s_-]*(?:services?|board)|public[\s_-]*library|waterworks|utilities[\s_-]*[.,]?[\s_-]*(?:inc(?:orporated)?|corp(?:oration)?|ltd|limited|commission)\b)|trust[\s_-]*(?:fund[\s_-]*)?(?:(?:financial[\s_-]*)?statements?|\bfs\b)|(?:arrondissement|caisse[\s_-]*commune|commission[\s_-]*du[\s_-]*r[ée]gime|office[\s_-]*municipal[\s_-]*d['’]habitation|r[ée]gime[\s_-]*de[\s_-]*retraite)[\s\S]{0,1_500}(?:[ée]tats?[\s_-]*financiers?|rapport[\s_-]*financier)|(?:[ée]tats?[\s_-]*financiers?|rapport[\s_-]*financier)[\s\S]{0,1_500}(?:arrondissement|caisse[\s_-]*commune|commission[\s_-]*du[\s_-]*r[ée]gime|office[\s_-]*municipal[\s_-]*d['’]habitation|r[ée]gime[\s_-]*de[\s_-]*retraite))/i
  FINANCIAL_HIGHLIGHTS_PATTERN = /(?:faits?[\s_-]*saillants?[\s_-]*(?:du|des)[\s_-]*rapport[\s_-]*financier|rapport[\s_-]*(?:du|de[\s_-]*la)[\s_-]*(?:mairesse?|maire)[\s_-]*sur[\s_-]*la[\s_-]*situation[\s_-]*financi.{0,2}re)/i
  NON_REPORT_ARTIFACT_PATTERN = /(?:\b(?:odj|pv)[\s_-]*(?:19|20)\d{2}\b|ordre[\s_-]*du[\s_-]*jour|proc[èe]?[\s_-]*s?[\s_-]*verb(?:al|aux)|s[ée]ance[\s_-]*(?:ordinaire|extraordinaire)|transcription[\s_-]*(?:de[\s_-]*la[\s_-]*)?s[ée]ance|journal[\s_-]*municipal|\bhansard\b|legislative[\s_-]*assembly|\bunaudited\b|non[\s_-]*audit[ée]s?|\binformateur\b|\binfo[\s_-]*b\b|bulletin[\s_-]*municipal)/i
  FINANCIAL_NOTICE_PATTERN = /(?:avis[\s_-]*public|avis[\s_-]*(?:de[\s_-]*)?d[ée]p[oô]t|d[ée]p[oô]t[\s_-]*(?:du[\s_-]*)?(?:rapport|[ée]tats?)|communiqu[ée]|sommaire[\s_-]*(?:des[\s_-]*)?[ée]tats?[\s_-]*financiers?|extrait[\s_-]*(?:du[\s_-]*)?rapport[\s_-]*financier|pr[ée]sentation[\s_-]*(?:du[\s_-]*)?rapport[\s_-]*financier|rapport[\s_-]*financier[\s_-]*(?:explications?|pr[ée]sentation)|contrats?[\s_-]*(?:de[\s_-]*)?2[\s._-]*000|liste[\s_-]*des[\s_-]*contrats)/i
  PROGRAM_LOCATOR_PATTERN = /(?:gestion[\s_-]*contractuelle|application.{0,80}r[èe]glement.{0,80}gestion|charte.{0,80}langue[\s_-]*fran[çc]aise|service[\s_-]*(?:de[\s_-]*)?(?:police|s[ée]curit[ée][\s_-]*incendie|incendie)|s[ée]curit[ée][\s_-]*incendie|station[\s_-]*d['’]?[ée]puration|eaux?[\s_-]*us[ée]es?|\bspl[\s_-]*rapport[\s_-]*annuel|\bspvsj\b|r[èe]glement[\s_-]*(?:d['’]?)?emprunt)/i
  MEETING_LOCATOR_PATTERN = /(?:ordres?[\s_-]*du[\s_-]*jour|\bordo[\s_-]*(?:19|20)\d{2}\b|proj[\s_-]*(?:19|20)\d{2})/i
  SUMMARY_LOCATOR_PATTERN = /(?:\bsommaire\b|faits?[\s_-]*saillants?)/i
  PROGRAM_LOCATOR_ASCII_PATTERN = /(?:gestion contractuelle|application.{0,80}reglement.{0,80}gestion|rgc|charte.{0,80}langue francaise|service (?:de )?(?:police|securite incendie|incendie)|securite incendie|incendies?|station d epuration|eaux? usees?|spl rapport annuel|spvsj|reglement d emprunt)/
  ANNUAL_PROGRAM_ASCII_PATTERN = /(?:\bfrr\b|fonds regions|\bccl\b|\bcce\b|\bccu\b|\bc c [elu]\b|\bpgmr\b|\bbipa\b|rapport annuel sq|surete du quebec|securite publique|police|incendie|airport|historical ?society|\bssi\b|faits saillants|rapport annuel du maire|rapport maire|situation financiere|credit de taxes|logements? locatifs?|(?:article|art) 93|habitation|entente de developpement|directive relative|langue officielle|developpement economique|corporation de developpement|laval economique|protecteur du citoyen|verificateur general|\bvg\b|communique|contrats? de 2 000|\bvolet [123]\b|\bfdt\b|\bdel\b|dev eco|mlf|tac rapport annuel|\b0\d{3} c\b)/
  MEETING_LOCATOR_ASCII_PATTERN = /(?:ordres? du jour|\bordo (?:19|20)\d{2}\b|proj (?:19|20)\d{2})/

  def initialize(input_path:, output_path:, asset_root: DEFAULT_ASSET_ROOT)
    @input_path = Pathname(input_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @asset_root = Pathname(asset_root).expand_path
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    batch = JSON.parse(@input_path.read)
    rejection_count = 0
    batch.fetch("institutions").each do |institution|
      accepted = []
      rejections = []
      institution.fetch("reports").each do |report|
        text = first_pages(report)
        reason = rejection_reason(report, text)
        if reason
          rejection_count += 1
          rejections << report.slice("document_type", "year", "title", "download_url", "content_sha256").merge("reason" => reason)
        else
          accepted << report.merge("year" => corrected_year(report, text))
        end
      end
      institution["reports"] = accepted.uniq do |report|
        [ report.fetch("document_type"), report.fetch("year"), report.fetch("content_sha256") ]
      end
      institution["validated_report_count"] = institution.fetch("reports").length
      institution["review_rejections"] = rejections
    end
    recompute_summary!(batch)
    batch["review"] = {
      "input_path" => @input_path.to_s,
      "input_sha256" => Digest::SHA256.file(@input_path).hexdigest,
      "method" => "program/subsidiary title-page exclusion and reporting-year normalization",
      "rejected_report_count" => rejection_count
    }
    @output_path.write(JSON.pretty_generate(batch) << "\n")
    puts JSON.pretty_generate(
      batch.slice("institution_count", "institutions_with_reports", "validated_report_count", "financial_statement_count", "annual_report_count", "sofi_count").merge(
        "rejected_report_count" => rejection_count,
        "output" => @output_path.to_s,
        "sha256" => Digest::SHA256.file(@output_path).hexdigest
      )
    )
  end

  private

  def rejection_reason(report, text = first_pages(report))
    locator_scope = CGI.unescape("#{report['title']} #{report['download_url']} #{report['source_page_url']}")
    normalized_locator = normalize_locator(locator_scope)
    scope = "#{locator_scope} #{text}"
    if locator_scope.match?(PROGRAM_LOCATOR_PATTERN) || normalized_locator.match?(PROGRAM_LOCATOR_ASCII_PATTERN)
      return "program, service, or regulatory report, not the reporting institution's annual or financial report"
    end
    if report.fetch("document_type") == "annual-report" && normalized_locator.match?(ANNUAL_PROGRAM_ASCII_PATTERN)
      return "program-level annual report, not the reporting institution's annual report"
    end
    return "program-level annual report, not the reporting institution's annual report" if report.fetch("document_type") == "annual-report" && scope.match?(PROGRAM_REPORT_PATTERN)
    if locator_scope.match?(NON_REPORT_ARTIFACT_PATTERN) || locator_scope.match?(MEETING_LOCATOR_PATTERN) ||
        normalized_locator.match?(MEETING_LOCATOR_ASCII_PATTERN)
      return "meeting record or municipal bulletin, not an institutional report"
    end
    return "subsidiary or trust financial statements, not the reporting institution's statements" if report.fetch("document_type") == "financial-statements" && scope.match?(SUBSIDIARY_FINANCIAL_PATTERN)
    if report.fetch("document_type") == "financial-statements" && scope.match?(FINANCIAL_HIGHLIGHTS_PATTERN) && !strong_financial_statement?(text)
      return "financial highlights, not complete financial statements"
    end
    financial_notice = locator_scope.match?(FINANCIAL_NOTICE_PATTERN) || locator_scope.match?(SUMMARY_LOCATOR_PATTERN)
    if report.fetch("document_type") == "financial-statements" && financial_notice && !strong_financial_statement?(text)
      return "notice, summary, or presentation about financial results, not complete financial statements"
    end

    nil
  end

  def strong_financial_statement?(text)
    normalized = text.downcase
    english = normalized.match?(/independent\s+auditor(?:'s|s)?\s+report/i) &&
      normalized.match?(/(?:consolidated\s+)?financial\s+statements?|statement\s+of\s+financial\s+(?:position|operations)/i)
    french = normalized.match?(/rapport\s+de\s+l['’]auditeur\s+ind[ée]pendant/i) &&
      normalized.match?(/[ée]tats?\s+financiers?|[ée]tat\s+de\s+la\s+situation\s+financi.{0,2}re|[ée]tat\s+des\s+r[ée]sultats/i)
    english || french
  end

  def normalize_locator(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def first_pages(report)
    path = @asset_root.join(report.fetch("archive_path"))
    stdout, = Open3.capture3("pdftotext", "-f", "1", "-l", "8", "-layout", path.to_s, "-")
    stdout.byteslice(0, 16_000).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
  rescue StandardError
    ""
  end

  def corrected_year(report, text = first_pages(report))
    if report.dig("verification", "split_page_range_verified")
      return Integer(report.fetch("year"))
    end

    content_year = financial_statement_fiscal_year(text)
    return content_year if content_year

    [ url_basename(report["download_url"]), url_basename(report["source_page_url"]), report["title"] ].each do |source|
      years = source.to_s.scan(YEAR_PATTERN).flatten.map(&:to_i).select { |year| year.between?(1980, 2100) }
      return years.first if years.any?

      short_year = source.to_s[/annual[^0-9]{0,20}(\d{2})(?!\d)/i, 1]&.to_i
      return 2000 + short_year if short_year&.between?(0, 29)
      return 1900 + short_year if short_year&.between?(80, 99)
    end
    Integer(report.fetch("year"))
  end

  def financial_statement_fiscal_year(text)
    scope = text.to_s.gsub(/[\u00a0\s]+/, " ")
    patterns = [
      /(?:consolidated\s+)?financial\s+statements?\b.{0,220}?\b((?:19|20)\d{2})\b/i,
      /(?:for\s+the\s+)?(?:fiscal\s+)?(?:year|period)\s+ended\b.{0,160}?\b((?:19|20)\d{2})\b/i,
      /\bas\s+at\b.{0,100}?\b((?:19|20)\d{2})\b/i,
      /(?:pour\s+)?l['’]\s*exercice(?:\s+financier)?\s+(?:termin[ée]|clos)\b.{0,160}?\b((?:19|20)\d{2})\b/i,
      /[ée]tats?\s+financiers?\b.{0,220}?\b((?:19|20)\d{2})\b/i,
      /\bau\s+(?:\d{1,2}(?:er)?\s+)?(?:janvier|f[ée]vrier|mars|avril|mai|juin|juillet|ao[uû]t|septembre|octobre|novembre|d[ée]cembre)\s+((?:19|20)\d{2})\b/i
    ]
    patterns.each_with_index.filter_map do |pattern, pattern_index|
      match = pattern.match(scope)
      year = match&.captures&.first&.to_i
      next unless year&.between?(1980, 2100)

      [ match.begin(0), pattern_index, year ]
    end.min_by { |position, pattern_index, _year| [ position, pattern_index ] }&.last
  end

  def url_basename(url)
    CGI.unescape(File.basename(URI(url).path))
  rescue URI::InvalidURIError, TypeError
    ""
  end

  def recompute_summary!(batch)
    reports = batch.fetch("institutions").flat_map { |institution| institution.fetch("reports") }
    batch["institutions_with_reports"] = batch.fetch("institutions").count { |institution| institution.fetch("reports").any? }
    batch["validated_report_count"] = reports.length
    batch["financial_statement_count"] = reports.count { |report| report.fetch("document_type") == "financial-statements" }
    batch["annual_report_count"] = reports.count { |report| report.fetch("document_type") == "annual-report" }
    batch["sofi_count"] = reports.count { |report| report.fetch("document_type") == "statement-of-financial-information" }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: sanitize_municipal_report_batch.rb --input PATH --output PATH [--asset-root PATH]"
    parser.on("--input PATH") { |value| options[:input_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--asset-root PATH") { |value| options[:asset_root] = Pathname(value) }
  end.parse!

  missing = %i[input_path output_path].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  SanitizeMunicipalReportBatch.new(**options).run
end
