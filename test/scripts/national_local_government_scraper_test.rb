require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../../script/scrape_national_local_governments"

class NationalLocalGovernmentScraperTest < Minitest::Test
  def setup
    @scraper = NationalLocalGovernmentScraper.new(
      root: Dir.mktmpdir,
      jurisdictions: [ "on" ],
      download_assets: false
    )
  end

  def teardown
    FileUtils.rm_rf(@scraper.instance_variable_get(:@root))
  end

  def test_ontario_anchors_retain_legal_style_tier_and_website
    csv = <<~CSV
      Municipality,Municipal status,Geographic area
      "<a title=""Markham, City of"" href=""https://www.markham.ca/"">Markham, City of</a>",Lower Tier,York
    CSV

    rows = @scraper.parse_ontario_csv(csv)
    assert_equal 1, rows.length
    row = rows.first

    assert_equal "Markham, City of", row.fetch("name")
    assert_equal "https://www.markham.ca/", row.fetch("website_url")
    assert_equal "Lower Tier", row.fetch("tier_label")
    assert_equal "York", row.fetch("geographic_area")
  end

  def test_new_brunswick_row_numbers_are_not_identifiers
    text = <<~TEXT
       1 Acadian Peninsula Rural District / District Rural Péninsule Acadienne      Rural District / District rural       Acadian Peninsula RSC
       2 Alnwick                                                                   Rural Community / Communauté rurale   Greater Miramichi RSC
       3 Bathurst                                                                  City / Cité                            Chaleur RSC
    TEXT

    rows = @scraper.parse_nb_population_table(text)

    assert_equal 3, rows.length
    assert_equal "1", rows.first.fetch("row_number")
    assert_equal "Rural District / District rural", rows.first.fetch("type_label")
    refute rows.first.key?("identifier")
  end

  def test_manitoba_parser_retains_numbers_and_nil_website_gaps
    text = <<~TEXT
      MANITOBA MUNICIPALITIES
      ALEXANDER, RM
      Website: www.rmalexander.com
      Municipal #: 600

      SAMPLE,
      MUNICIPALITY
      Website :
      Municipal #: 123
      THE CITY OF WINNIPEG
    TEXT

    rows = @scraper.parse_manitoba_directory(text)

    assert_equal 3, rows.length
    assert_equal "https://www.rmalexander.com", rows.first.fetch("website_url")
    assert_equal "600", rows.first.fetch("municipal_number")
    assert_nil rows[1].fetch("website_url")
    assert_equal "CHARTER CITY", rows.last.fetch("type_label")
  end

  def test_newfoundland_and_labrador_parser_separates_region
    text = <<~TEXT
      Community Name         Region       Mayor
      Admirals Beach         Eastern      Michelle Dalton
      Nain                   Labrador     AngajukKak
    TEXT

    assert_equal [
      { "name" => "Admirals Beach", "region" => "Eastern" },
      { "name" => "Nain", "region" => "Labrador" }
    ], @scraper.parse_nl_directory(text)
  end

  def test_statscan_associations_are_geography_links_not_identifiers
    @scraper.instance_variable_set(:@statcan_candidates, {
      "on" => [ { "uid" => "3519036", "name" => "Markham" } ]
    })
    institution = {
      "canonical_id" => "ca/on/markham",
      "official_name_en" => "Markham, City of",
      "official_name_fr" => nil,
      "source_url" => "https://example.test/official-roster",
      "identifiers" => [],
      "geography_associations" => []
    }

    @scraper.match_statscan([ institution ], "on")

    assert_empty institution.fetch("identifiers")
    associations = institution.fetch("geography_associations")
    assert_equal 1, associations.length
    association = associations.first
    assert_equal "ca/geography/csd-2021/3519036", association.fetch("geography_id")
    assert_equal "exact_unique_normalized_name", association.fetch("match_method")
  end

  def test_validation_rejects_statscan_institution_identifiers
    institution = @scraper.send(
      :institution_record,
      code: "on", name_en: "Markham", legal_form: "city", tier: "lower_tier",
      kind: "municipal_government", source_url: "https://example.test",
      website_url: nil, website_source_url: nil, website_gap: "not supplied"
    )
    institution.fetch("identifiers") << {
      "scheme" => "statscan.sgc2021.csd", "value" => "3519036"
    }

    error = assert_raises(NationalLocalGovernmentScraper::ScrapeError) do
      @scraper.send(:validate_payload!, [ institution ])
    end
    assert_match "incorrectly emitted as institution identifier", error.message
  end

  def test_financial_returns_and_audited_statements_use_different_types
    aggregate = {
      "document_type" => "financial-data-return",
      "title" => "Quebec actual data 2025"
    }
    statement = {
      "document_type" => "audited-financial-statements",
      "mime_type" => "application/pdf"
    }

    refute_equal aggregate.fetch("document_type"), statement.fetch("document_type")
  end

  def test_release_coverage_distinguishes_search_statuses
    normalized = {
      "jurisdiction" => "pe",
      "institutions" => [ {
        "website_url" => nil, "geography_associations" => [], "relationships" => [], "documents" => []
      } ],
      "aggregate_documents" => []
    }

    rows = @scraper.send(:release_coverage, normalized, @scraper.send(:province_metadata_for, "pe"))
    statuses = rows.to_h { |row| [ row.fetch("subject"), row.fetch("status") ] }

    assert_equal "partial", statuses.fetch("institutions")
    assert_equal "partial", statuses.fetch("websites")
    assert_equal "not-found", statuses.fetch("geographies")
    assert_equal "unavailable", statuses.fetch("financial-statements")
    assert_equal "not-searched", statuses.fetch("annual-reports")
    assert_equal "unavailable", statuses.fetch("document-assets")
  end

  def test_cached_antibot_response_is_not_reported_as_success
    context = NationalLocalGovernmentScraper::Context.new(
      code: "yt", output_dir: Pathname(@scraper.instance_variable_get(:@root)),
      raw_dir: Pathname(@scraper.instance_variable_get(:@root)).join("raw"),
      raw_manifest: [], failures: [], gaps: [], mutex: Mutex.new
    )
    FileUtils.mkdir_p(context.raw_dir)
    context.raw_dir.join("blocked.html").write("<title>Just a moment...</title><script>_cf_chl_opt={}</script>")

    assert_raises(NationalLocalGovernmentScraper::ScrapeError) do
      @scraper.send(:archive_get, context, "https://example.test", "blocked.html")
    end
    assert_equal 403, context.raw_manifest.fetch(0).fetch("http_status")
  end

  def test_saskatchewan_statement_number_typo_retains_semantic_municipality_stem
    current = @scraper.send(:saskatchewan_name_stem, "Meota, Rural Municipality No. 468")
    source_typo = @scraper.send(:saskatchewan_name_stem, "RM of Meota, No. 68")

    assert_equal "meota", current
    assert_equal current, source_typo
  end

  def test_saskatchewan_statement_number_without_no_retains_semantic_municipality_stem
    current = @scraper.send(:saskatchewan_name_stem, "Enfield, Rural Municipality No. 194")
    source_typo = @scraper.send(:saskatchewan_name_stem, "RM of Enfield,\t194")

    assert_equal "enfield", current
    assert_equal current, source_typo
  end

  def test_cached_upstream_not_found_body_retains_failure_status
    context = NationalLocalGovernmentScraper::Context.new(
      code: "sk", output_dir: Pathname(@scraper.instance_variable_get(:@root)),
      raw_dir: Pathname(@scraper.instance_variable_get(:@root)).join("raw"),
      raw_manifest: [], failures: [], gaps: [], mutex: Mutex.new
    )
    FileUtils.mkdir_p(context.raw_dir)
    context.raw_dir.join("missing.pdf").write('{"error":"Could not find the requested resource."}')

    assert_raises(NationalLocalGovernmentScraper::ScrapeError) do
      @scraper.send(:archive_get, context, "https://example.test/missing.pdf", "missing.pdf")
    end
    assert_equal 404, context.raw_manifest.fetch(0).fetch("http_status")
  end

  def test_nwt_semantic_ids_drop_nbsp_and_legal_type_prefixes
    assert_equal "Yellowknife", @scraper.send(:nwt_semantic_name, "\u00a0City of Yellowknife")
    assert_equal "Behchokǫ̀", @scraper.send(:nwt_semantic_name, "\u00a0Community Government of Behchokǫ̀")
    assert_equal "Fort Smith", @scraper.send(:nwt_semantic_name, "\u00a0Town of Fort Smith")
    assert_equal "Deline Gotine Government",
      @scraper.send(:nwt_semantic_name, "Délı̨nę Got’ı̨nę Government")
  end

  def test_nwt_legal_forms_preserve_distinct_statutory_governments
    assert_equal "tlicho_community_government",
      @scraper.send(:nwt_legal_form, "Community Government of Whatì", "Self Government")
    assert_equal "self_government_community_government",
      @scraper.send(:nwt_legal_form, "Délı̨nę Got’ı̨nę Government", "Self Government")
    assert_equal "charter_community",
      @scraper.send(:nwt_legal_form, "Charter Community of K’asho Got’ine", "Charter Community")
  end

  def test_quebec_geography_forms_do_not_include_actual_local_government_forms
    excluded = NationalLocalGovernmentScraper::QUEBEC_NON_INSTITUTIONAL_LEGAL_FORMS

    assert_includes excluded, "reserve_indienne"
    assert_includes excluded, "terre_de_la_categorie_ia_n"
    assert_includes excluded, "territoire_non_organise"
    refute_includes excluded, "village_cri_terre_de_la_categorie"
    refute_includes excluded, "village_naskapi_terre_de_la_catego"
    refute_includes excluded, "administration_regionale"
  end

  def test_quebec_aggregate_returns_do_not_claim_complete_institution_document_coverage
    normalized = {
      "jurisdiction" => "qc",
      "institutions" => [ {
        "status" => "active", "website_url" => nil, "geography_associations" => [],
        "relationships" => [], "documents" => []
      } ],
      "aggregate_documents" => Array.new(4) { { "document_type" => "financial-data-return", "asset_path" => "/tmp/source" } }
    }

    rows = @scraper.send(:release_coverage, normalized, @scraper.send(:province_metadata_for, "qc"))
    by_subject = rows.to_h { |row| [ row.fetch("subject"), row ] }

    assert_equal "partial", by_subject.fetch("financial-data-return").fetch("status")
    assert_match "not emitted as institution document rows", by_subject.fetch("financial-data-return").fetch("notes")
    assert_equal "partial", by_subject.fetch("document-assets").fetch("status")
  end
end
