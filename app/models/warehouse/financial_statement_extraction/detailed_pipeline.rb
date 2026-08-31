require "timeout"
require "fileutils"
require "tmpdir"

class Warehouse::FinancialStatementExtraction::DetailedPipeline
  EXTRACTOR_VERSION = "detailed-psas-v1"
  DEFAULT_MODEL = Warehouse::FinancialStatementExtraction::Pipeline::DEFAULT_MODEL
  MODEL_TIMEOUT = ENV.fetch("MUNICIPAL_FINANCIAL_MODEL_TIMEOUT", 300).to_i
  MAX_OUTPUT_TOKENS = ENV.fetch("MUNICIPAL_FINANCIAL_DETAIL_MAX_OUTPUT_TOKENS", 32_768).to_i
  MAX_DETAIL_PAGES_PER_FLOW = 4
  MAX_LINE_ITEMS_PER_FLOW = 100
  FLOW_CONCURRENCIES = [ 1, 2 ].freeze
  Result = Data.define(
    :status, :facts, :line_items, :checks, :prompt, :response,
    :locator_result, :language, :statement_basis
  )
  FlowJob = Data.define(:flow, :pages, :prompt)
  PreparedFlowJob = Data.define(:flow, :pages, :prompt, :pdf_path)

  class ResponseError < StandardError; end

  def initialize(pdf_path:, institution_canonical_id:, institution_name:, document_canonical_id:,
    asset_sha256:, fiscal_year_end:, population: nil, model: DEFAULT_MODEL,
    headline_pipeline: nil, llm_client: nil, llm_client_factory: nil, page_locator: nil,
    flow_concurrency: ENV.fetch("MUNICIPAL_FINANCIAL_DETAIL_FLOW_CONCURRENCY", 1), flow_reporter: nil)
    @pdf_path = Pathname(pdf_path)
    @institution_canonical_id = institution_canonical_id
    @institution_name = institution_name
    @document_canonical_id = document_canonical_id
    @asset_sha256 = asset_sha256
    @fiscal_year_end = fiscal_year_end.to_date
    @population = population
    @model = model
    @page_locator = page_locator || Warehouse::FinancialStatementExtraction::PageLocator.new(@pdf_path)
    @headline_pipeline = headline_pipeline || Warehouse::FinancialStatementExtraction::Pipeline.new(
      pdf_path:, institution_canonical_id:, institution_name:, document_canonical_id:,
      asset_sha256:, fiscal_year_end:, population:, model:, page_locator: @page_locator
    )
    @flow_concurrency = normalize_flow_concurrency(flow_concurrency)
    if llm_client && llm_client_factory
      raise ArgumentError, "provide llm_client or llm_client_factory, not both"
    end
    if @flow_concurrency == 2 && llm_client
      raise ArgumentError, "concurrent flow extraction requires llm_client_factory"
    end
    @llm_client = llm_client || method(:call_ruby_llm)
    @llm_client_factory = llm_client_factory || method(:new_ruby_llm_client)
    @flow_reporter = flow_reporter || ->(event) { warn(event.to_json) }
    @flow_reporter_mutex = Mutex.new
  end

  def run
    headline = @headline_pipeline.run
    locator = headline.locator_result
    jobs = Warehouse::FinancialStatementLineItem::FLOWS.map do |flow|
      pages = select_detail_pages(locator, flow).freeze
      FlowJob.new(flow:, pages:, prompt: build_prompt(pages, locator.page_texts, flow).freeze)
    end.freeze
    flow_responses = extract_flows(jobs)
    prompts = {}
    responses = {}
    line_items = []
    jobs.each do |job|
      response = flow_responses.fetch(job.flow)
      validate_response!(response, job.pages, job.flow)
      prompts[job.flow] = job.prompt
      responses[job.flow] = response
      line_items.concat(normalize_line_items(
        response.fetch("line_items"), job.pages, locator.page_texts
      ))
    end
    flags = headline.response.slice(
      "remeasurement_present", "operations_adjustment_present", "rollforward_adjustment_present"
    ).symbolize_keys
    flags[:single_component_concepts] =
      Warehouse::FinancialStatementExtraction::Pipeline.single_component_concepts(headline.response)
    validator = Warehouse::FinancialStatementExtraction::Validator.new(
      facts: headline.facts, line_items:, fiscal_year: @fiscal_year_end.year,
      population: @population, page_texts: locator.page_texts, flags:
    )
    checks = [ headline.checks.find { |check| check[:id] == "source_identity" }, *validator.validate ].compact
    status = validator.acceptable?(checks) ? "extracted" : "needs_review"
    status = "needs_review" if headline.status == "needs_review"
    Result.new(
      status:, facts: headline.facts, line_items:, checks:,
      prompt: prompts.map { |flow, value| "REQUESTED FLOW: #{flow}\n#{value}" }.join("\n\n"),
      response: { "headline" => headline.response, "details" => responses },
      locator_result: locator, language: headline.language, statement_basis: headline.statement_basis
    )
  rescue JSON::ParserError, KeyError, ArgumentError, ResponseError, Timeout::Error => error
    raise ResponseError, error.message
  end

  private

  def normalize_flow_concurrency(value)
    concurrency = Integer(value)
    return concurrency if concurrency.in?(FLOW_CONCURRENCIES)

    raise ArgumentError, "flow_concurrency must be 1 or 2"
  rescue TypeError, ArgumentError
    raise ArgumentError, "flow_concurrency must be 1 or 2"
  end

  def extract_flows(jobs)
    return jobs.to_h { |job| [ job.flow, extract_serial_flow(job) ] } if @flow_concurrency == 1

    Dir.mktmpdir("financial-statement-detail-flows") do |directory|
      prepared = jobs.map do |job|
        destination = Pathname(directory).join("#{job.flow}.pdf")
        @page_locator.with_excerpt(job.pages) { |excerpt| FileUtils.cp(excerpt, destination) }
        PreparedFlowJob.new(
          flow: job.flow, pages: job.pages, prompt: job.prompt, pdf_path: destination.freeze
        )
      end.freeze
      clients = prepared.map { @llm_client_factory.call }
      unless clients.all? { _1.respond_to?(:call) } && clients.map(&:object_id).uniq.length == clients.length
        raise ArgumentError, "llm_client_factory must return a distinct callable per flow"
      end

      threads = prepared.zip(clients).map do |job, client|
        Thread.new { extract_flow_response(job, client) }.tap { _1.report_on_exception = false }
      end
      threads.each do |thread|
        thread.join
      rescue StandardError
        # Join every worker so its request and temporary excerpt are finished
        # before the first error is re-raised below.
      end
      prepared.map.with_index { |job, index| [ job.flow, threads.fetch(index).value ] }.to_h
    end
  end

  def extract_serial_flow(job)
    @page_locator.with_excerpt(job.pages) do |excerpt|
      extract_flow_response(
        PreparedFlowJob.new(flow: job.flow, pages: job.pages, prompt: job.prompt, pdf_path: excerpt),
        @llm_client
      )
    end
  end

  def extract_flow_response(job, client)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raw = Timeout.timeout(MODEL_TIMEOUT) { client.call(prompt: job.prompt, pdf_path: job.pdf_path.to_s) }
    response = raw.respond_to?(:content) ? raw.content : raw
    response = JSON.parse(response) if response.is_a?(String)
    report_flow(job.flow, "success", started)
    response
  rescue => error
    report_flow(job.flow, "failure", started, error: error)
    raise
  end

  def report_flow(flow, outcome, started, error: nil)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round
    event = {
      financial_statement_detail_flow: outcome, flow:, elapsed_ms: elapsed,
      error_class: error&.class&.name
    }.compact
    @flow_reporter_mutex.synchronize { @flow_reporter.call(event) }
  rescue StandardError
    nil
  end

  # Each invocation constructs a new RubyLLM chat, so concurrent flow requests
  # cannot share message history or adapter state.
  def new_ruby_llm_client
    method(:call_ruby_llm)
  end

  def select_detail_pages(locator, flow)
    operations_text = locator.page_texts.fetch(locator.operations_page)
    return [ locator.operations_page ] if primary_has_detail_rows?(operations_text, flow)

    flow_pattern = flow == "revenue" ? /revenues?|revenus|produits/i : /expenses?|expenditures?|dépenses|depenses|charges/i
    schedule_pattern = /schedule|appendix|annexe|cédule|cedule/i
    supporting = locator.page_texts.filter_map do |page, text|
      next if page == locator.operations_page

      heading = text.lines.first(20).join
      next unless heading.match?(schedule_pattern) && text.match?(flow_pattern)
      next unless text.match?(/(?<!\d)#{@fiscal_year_end.year}(?!\d)/)

      numeric_cells = text.scan(/\(?\d[\d ,.]*/).count { _1.scan(/\d/).length >= 3 }
      [ page, numeric_cells ]
    end
    selected = supporting.sort_by { |page, score| [ -score, page ] }
      .first(MAX_DETAIL_PAGES_PER_FLOW - 1).map(&:first)
    [ locator.operations_page, *selected ].uniq.sort
  end

  def primary_has_detail_rows?(text, flow)
    start_pattern = if flow == "revenue"
      /\A\s*(?:revenues?|revenus|produits)\s*\z/i
    else
      /\A\s*(?:expenses?|expenditures?|d[eé]penses|charges)\s*\z/i
    end
    finish_pattern = if flow == "revenue"
      /\A\s*(?:expenses?|expenditures?|d[eé]penses|charges)\s*\z/i
    else
      /\A\s*(?:total\s+)?(?:expenses?|expenditures?|d[eé]penses|charges)\b|\A\s*(?:annual|excess|exc[eé]dent)/i
    end
    lines = text.lines
    start_index = lines.index { _1.match?(start_pattern) }
    return false unless start_index

    finish_index = lines.each_index.find { _1 > start_index && lines[_1].match?(finish_pattern) } || lines.length
    rows = lines[(start_index + 1)...finish_index].count do |line|
      line.match?(/[[:alpha:]]/) && line.scan(/\(?-?\d[\d,.]*\)?/).count { _1.scan(/\d/).length >= 3 } >= 2
    end
    rows >= 2
  end

  def call_ruby_llm(prompt:, pdf_path:)
    RubyLLM.chat(model: @model)
      .with_temperature(0)
      .with_thinking(effort: :low)
      .with_params(generationConfig: { maxOutputTokens: MAX_OUTPUT_TOKENS })
      .with_schema(Warehouse::FinancialStatementExtraction::DetailedResponseSchema)
      .ask(prompt, with: pdf_path)
  end

  def build_prompt(pages, page_texts, flow)
    page_map = pages.map.with_index(1) { |physical, excerpt| "excerpt page #{excerpt} = archived PDF page #{physical}" }.join("\n")
    source_text = pages.map.with_index(1) do |physical, excerpt|
      "EXCERPT PAGE #{excerpt} (ARCHIVED PDF PAGE #{physical})\n#{page_texts.fetch(physical)}"
    end.join("\n\n")
    <<~PROMPT
      Extract the detailed current-year #{flow} leaf line items from this Canadian municipal financial statement.

      Institution: #{@institution_name} (#{@institution_canonical_id})
      Fiscal year: #{@fiscal_year_end.year}

      PAGE MAP
      #{page_map}

      REQUESTED FLOW: #{flow}

      Rules:
      - Use only the #{@fiscal_year_end.year} actual column, never budget or comparative values.
      - Extract printed leaf line items that add to the consolidated total revenue or total expenses.
      - Do not return totals or subtotals as line items. Preserve negative recoveries or adjustments.
      - Return only #{flow} rows and set flow to #{flow}. category is the nearest printed group, function, segment, or schedule heading.
      - If no group is printed, repeat the label as category. Never invent a program or category.
      - label is the exact printed row label. raw_text is only the exact printed numeric cell for #{@fiscal_year_end.year}
        (for example "$ 2,332,958" or "(45,957)"); never put a row label in raw_text.
      - Copy label punctuation literally, including ampersands, apostrophes, hyphens, and note parentheses; do not expand,
        contract, correct, or paraphrase the printed label.
      - scale is 1, 1000, or 1000000 from the page heading.
      - excerpt_page uses the page map above. column_year preserves the printed column heading.
        When the heading is stacked across lines, combine it (for example "2023 Actual"), so column_year always includes #{@fiscal_year_end.year}.
      - The first excerpt is the primary statement of operations. If it prints leaf rows for this flow, use only those
        primary-statement rows and ignore supporting schedules. Otherwise use exactly one complete supporting schedule.
      - On a primary statement with printed totals, revenue rows must be strictly between the Revenue heading and Total Revenue,
        and expense rows must be strictly between the Expenses heading and Total Expenses or Total Expenditures. Exclude every
        row after those totals, including later Other revenue (expenditure), capital transfers, and disposal gains or losses.
        If the primary statement has no printed flow total, stop at the next flow heading or annual surplus line instead.
      - Never combine duplicate presentations of the same values or mix a primary statement with its supporting schedule.
      - Omit ambiguous values instead of calculating or guessing.
      - Recognize French revenus, produits, charges, and dépenses.

      SOURCE TEXT
      #{source_text}
    PROMPT
  end

  def validate_response!(response, pages, expected_flow)
    raise ResponseError, "response must be an object" unless response.is_a?(Hash)
    raise ResponseError, "response fiscal year does not match" unless Integer(response.fetch("fiscal_year")) == @fiscal_year_end.year
    items = response.fetch("line_items")
    raise ResponseError, "line_items must not be empty" unless items.is_a?(Array) && items.any?
    raise ResponseError, "too many line items" if items.length > MAX_LINE_ITEMS_PER_FLOW
    identities = items.map { |item| item.values_at("flow", "category", "label") }
    raise ResponseError, "duplicate line items" unless identities.uniq.length == identities.length
    items.each do |item|
      raise ResponseError, "invalid flow" unless item.fetch("flow").in?(Warehouse::FinancialStatementLineItem::FLOWS)
      raise ResponseError, "unexpected flow" unless item.fetch("flow") == expected_flow
      raise ResponseError, "blank category or label" if item.fetch("category").blank? || item.fetch("label").blank?
      raise ResponseError, "invalid scale" unless Integer(item.fetch("scale")).in?(Warehouse::FinancialStatementLineItem::SCALES)
      page = Integer(item.fetch("excerpt_page"))
      raise ResponseError, "excerpt page out of range" unless page.between?(1, pages.length)
      confidence = Float(item.fetch("confidence"))
      raise ResponseError, "confidence out of range" unless confidence.between?(0, 1)
    end
  end

  def normalize_line_items(items, pages, page_texts)
    positions = Hash.new(0)
    items.filter_map do |item|
      next if Warehouse::FinancialStatementExtraction::NumberParser.null_marker?(item.fetch("raw_text"))

      flow = item.fetch("flow")
      position = positions[flow]
      positions[flow] += 1
      source_page = pages.fetch(Integer(item.fetch("excerpt_page")) - 1)
      {
        flow:, category: item.fetch("category"), label: item.fetch("label"),
        raw_text: item.fetch("raw_text"),
        value: Warehouse::FinancialStatementExtraction::NumberParser.parse(item.fetch("raw_text")) * Integer(item.fetch("scale")),
        scale: Integer(item.fetch("scale")),
        source_page:,
        column_year: Warehouse::FinancialStatementExtraction::Pipeline.normalize_column_year(
          item.fetch("column_year"), fiscal_year: @fiscal_year_end.year,
          page_text: page_texts.fetch(source_page)
        ),
        position:,
        extraction_confidence: BigDecimal(item.fetch("confidence").to_s)
      }
    end
  end
end
