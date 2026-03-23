class RawIngestion::CorporateNormalizer < ActiveRecord::AssociatedObject
  include CorporateNormalization

  performs :normalize

  # ISED Open Data XML format (OPEN_DATA_SPLIT.zip contains multiple OPEN_DATA_N.xml files)
  # Real XML structure uses attributes and nested elements:
  #   <corporation corporationId="1007">
  #     <names><name code="1" current="true">Corp Name</name></names>
  #     <statuses><status code="1" current="true"/></statuses>
  #     <acts><act code="6" current="true"/></acts>
  #     <activities><activity code="1" date="1947-01-10T00:00:00"/></activities>
  #     <addresses><address code="2" current="true">
  #       <addressLine>123 MAIN ST</addressLine><city>OTTAWA</city>
  #       <province code="ON"/><postalCode>K1A 0B1</postalCode>
  #     </address></addresses>
  #     <businessNumbers><businessNumber>123456789</businessNumber></businessNumbers>
  #   </corporation>

  # Code lookups from codes.xml
  STATUS_CODES = {
    "1" => "Active", "2" => "Active - Intent to Dissolve",
    "3" => "Active - Dissolution Pending", "4" => "Active - Discontinuance Pending",
    "9" => "Inactive - Amalgamated", "10" => "Inactive - Discontinued",
    "11" => "Dissolved", "19" => "Inactive"
  }.freeze

  ACT_CODES = {
    "1" => "CCA Part I", "2" => "CCA Part I", "3" => "CCA Part II",
    "4" => "CCAA", "5" => "PFSA", "6" => "CBCA",
    "7" => "BOTA Part I", "8" => "BOTA Part II", "9" => "Special Act",
    "10" => "Multiple Acts", "11" => "Bank Act", "12" => "Canada Cooperatives",
    "13" => "Other", "14" => "NFP Act"
  }.freeze

  ACTIVITY_CODES = {
    "1" => "Incorporation", "2" => "Continuance (Import)", "3" => "Discontinuance",
    "4" => "Amalgamation", "7" => "Continuance (Act)", "14" => "Intent to Dissolve",
    "15" => "Revocation of Intent", "21" => "Amendment", "101" => "Dissolution",
    "104" => "Revival", "108" => "Restated Articles", "110" => "Arrangement",
    "114" => "By-Laws Filing", "120" => "Continuance (Transition)"
  }.freeze

  def normalize(file_content:)
    records = []
    rows_processed = 0

    # Handle ZIP containing XML files
    if file_content.start_with?("PK")
      Zip::InputStream.open(StringIO.new(file_content)) do |zip|
        while (entry = zip.get_next_entry)
          next unless entry.name.end_with?(".xml") && !entry.name.include?("codes")
          parse_xml(zip.read, records) { |batch| flush_batch(batch); rows_processed += batch.size }
        end
      end
    else
      parse_xml(file_content, records) { |batch| flush_batch(batch); rows_processed += batch.size }
    end

    # Flush remaining records
    if records.any?
      flush_batch(records)
      rows_processed += records.size
    end

    raw_ingestion.update!(status: :complete)
    Rails.logger.info "[CorporateNormalizer] Processed #{rows_processed} federal corps for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def parse_xml(xml_content, records, &on_batch)
    handler = IsedSaxHandler.new(records, raw_ingestion) do |batch|
      on_batch.call(batch)
    end

    parser = Nokogiri::XML::SAX::Parser.new(handler)
    parser.parse(xml_content)
  end

  def flush_batch(records)
    now = Time.current
    batch = records.map do |r|
      r.merge(created_at: now, updated_at: now)
    end
    batch_upsert!(batch)
    records.clear
  end

  # SAX handler for ISED corporate data XML
  # Handles the attribute-heavy, nested-element structure of the real ISED data
  class IsedSaxHandler < Nokogiri::XML::SAX::Document
    def initialize(records, raw_ingestion, &on_batch_full)
      @records = records
      @raw_ingestion = raw_ingestion
      @on_batch_full = on_batch_full
      @current_corp = {}
      @element_stack = []
      @text_buffer = +""
      @in_corp = false
      @current_address_is_current = false
      @current_name_is_current = false
    end

    def start_element(name, attrs = [])
      attrs_hash = attrs.is_a?(Array) ? attrs.to_h : attrs
      @element_stack.push(name)
      @text_buffer = +""

      case name
      when "corporation"
        @in_corp = true
        @current_corp = { names: [], activities: [] }
        @current_corp[:registry_id] = attrs_hash["corporationId"]

      when "status"
        if @in_corp && attrs_hash["current"] == "true"
          code = attrs_hash["code"]
          @current_corp[:status] = STATUS_CODES[code] || "Unknown (#{code})"
          @current_corp[:status_effective_date] = parse_date(attrs_hash["effectiveDate"])
        end

      when "act"
        if @in_corp && attrs_hash["current"] == "true"
          code = attrs_hash["code"]
          @current_corp[:governing_act] = ACT_CODES[code] || "Unknown Act (#{code})"
        end

      when "activity"
        if @in_corp
          code = attrs_hash["code"]
          date = parse_date(attrs_hash["date"])
          @current_corp[:activities] << { code: code, type: ACTIVITY_CODES[code], date: date }
        end

      when "name"
        if @in_corp && parent_element == "names"
          @current_name_is_current = (attrs_hash["current"] == "true")
        end

      when "address"
        if @in_corp && parent_element == "addresses"
          @current_address_is_current = (attrs_hash["current"] == "true")
        end

      when "province"
        if @in_corp && @current_address_is_current
          @current_corp[:registered_office_province] = attrs_hash["code"]
        end
      end
    end

    def characters(string)
      @text_buffer << string if @in_corp
    end

    def end_element(name)
      text = @text_buffer.strip

      case name
      when "corporation"
        emit_record if @in_corp
        @in_corp = false

      when "name"
        if @in_corp && parent_element == "names" && text.present?
          if @current_name_is_current
            @current_corp[:legal_name] = text
          else
            @current_corp[:names] << text
          end
          @current_name_is_current = false
        end

      when "businessNumber"
        if @in_corp && text.present?
          @current_corp[:business_number] = text
        end

      when "addressLine"
        if @in_corp && @current_address_is_current && text.present?
          existing = @current_corp[:registered_office_address]
          @current_corp[:registered_office_address] = [existing, text].compact.join(", ")
        end

      when "city"
        if @in_corp && @current_address_is_current && text.present?
          @current_corp[:registered_office_city] = text
        end

      when "postalCode"
        if @in_corp && @current_address_is_current && text.present?
          @current_corp[:registered_office_postal_code] = text
        end

      when "address"
        @current_address_is_current = false
      end

      @element_stack.pop
      @text_buffer = +""
    end

    private

    def parent_element
      @element_stack[-2]
    end

    def emit_record
      return unless @current_corp[:registry_id].present? && @current_corp[:legal_name].present?

      # Derive incorporation date from first "Incorporation" activity (code "1")
      incorp = @current_corp[:activities].find { |a| a[:code] == "1" }
      # Derive dissolution date from "Dissolution" activity (code "101")
      dissolution = @current_corp[:activities].find { |a| a[:code] == "101" }

      @records << {
        jurisdiction: "federal",
        registry_id: @current_corp[:registry_id],
        business_number: @current_corp[:business_number],
        legal_name: @current_corp[:legal_name],
        corporation_type: nil, # Not directly in XML; derivable from act type
        status: @current_corp[:status],
        governing_act: @current_corp[:governing_act],
        registered_office_address: @current_corp[:registered_office_address],
        registered_office_province: @current_corp[:registered_office_province],
        registered_office_postal_code: @current_corp[:registered_office_postal_code],
        incorporation_date: incorp&.dig(:date),
        dissolution_date: dissolution&.dig(:date),
        business_activity: nil,
        source_system: "ised_xml",
        raw_ingestion_id: @raw_ingestion.id
      }

      if @records.size >= CorporateNormalization::BATCH_SIZE
        @on_batch_full.call(@records.dup)
        @records.clear
      end
    end

    def parse_date(text)
      return nil if text.blank?
      Date.parse(text)
    rescue Date::Error, ArgumentError
      nil
    end
  end
end
