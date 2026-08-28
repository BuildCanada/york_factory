require "test_helper"

class Warehouse::FirstNationsSourceTest < ActiveSupport::TestCase
  test "adapter preserves band identity while keeping reserves and physical CSDs contextual" do
    Dir.mktmpdir do |directory|
      adapter = Warehouse::InstitutionRelease::FirstNations::SourceAdapter.new(
        release_version: "2099-01-03", output_root: directory,
        http_client: FakeFirstNationsHttp.new, retrieved_at: Time.utc(2099, 1, 3), workers: 2
      )
      manifest_path = adapter.call
      manifest = JSON.parse(manifest_path.read)
      bands = manifest.fetch("bands")

      assert_equal %w[ca/fn/test-nation-band-1 ca/fn/test-nation-band-2], bands.map { |row| row.fetch("canonical_id") }
      first = bands.first
      assert_equal "1", first.dig("identifiers", 0, "value")
      assert_equal "101", first.dig("location", "most_populated_reserve_number")
      assert_equal "headquartered_in", first.dig("statcan_geographies", 0, "role")
      assert_equal "2021A00051234567", first.dig("statcan_geographies", 0, "dguid")
      assert_equal "https://nation-one.example", first.fetch("website_url")
      assert_equal 1, first.fetch("reports").length
      assert_equal "metadata_only", first.dig("reports", 0, "rights_status")
      assert_match(/no downloadable document/, bands.second.fetch("gaps").join(" "))
      assert_equal 2, bands.length
      assert manifest_path.dirname.join("profiles/1-en.html").exist?
      assert manifest_path.dirname.join("fnfta/1-en.html").exist?
    end
  end

  test "previous band-number mapping survives an upstream rename" do
    Dir.mktmpdir do |directory|
      previous = Pathname(directory).join("previous.json")
      previous.write(JSON.generate(bands: [ { band_number: "1", canonical_id: "ca/fn/original-name" } ]))
      adapter = Warehouse::InstitutionRelease::FirstNations::SourceAdapter.new(
        release_version: "2099-01-04", output_root: directory,
        previous_manifest_path: previous, http_client: FakeFirstNationsHttp.new
      )
      mapping = adapter.send(:allocate_canonical_ids, [
        { "BAND_NUMBER" => 1, "BAND_NAME" => "Completely Renamed Nation" }
      ])

      assert_equal "ca/fn/original-name", mapping.fetch("1")
    end
  end

  test "manifest importer creates bands, audited works, headquarters links and band-only hierarchy" do
    Dir.mktmpdir do |directory|
      manifest_path = Warehouse::InstitutionRelease::FirstNations::SourceAdapter.new(
        release_version: "2099-01-05", output_root: directory,
        http_client: FakeFirstNationsHttp.new, retrieved_at: Time.utc(2099, 1, 5), workers: 2
      ).call
      release = Warehouse::InstitutionRelease.create!(
        version: "2099-01-05", effective_on: Date.new(2099, 1, 5), schema_version: "1.0",
        published_at: Time.utc(2099, 1, 5), geography_vintage: 2021, attribution: "Test"
      )

      imported = Warehouse::InstitutionRelease::FirstNations::ManifestImporter.new(
        release: release, path: manifest_path
      ).import!

      assert_equal 2, imported.count
      assert_equal [ "1", "2" ], release.institution_identifiers.where(scheme: "isc.band_number").order(:value).pluck(:value)
      assert_equal [ "headquartered_in" ], release.institution_geographies.distinct.pluck(:role)
      assert_equal 1, release.institution_documents.count
      assert_equal "financial-statements", release.institution_documents.first.document_type
      assert_equal 1, release.institution_relationships.where(relationship_type: "administrative_parent").count
      refute release.institutions.exists?(name_en: "Test Reserve")
      refute release.institution_identifiers.exists?(scheme: "isc.reserve_number")
    end
  end

  test "importer rejects territorial treatment of the containing CSD" do
    Dir.mktmpdir do |directory|
      manifest_path = Warehouse::InstitutionRelease::FirstNations::SourceAdapter.new(
        release_version: "2099-01-06", output_root: directory,
        http_client: FakeFirstNationsHttp.new, workers: 1
      ).call
      payload = JSON.parse(manifest_path.read)
      payload.dig("bands", 0, "statcan_geographies", 0)["role"] = "governs"
      tampered = Pathname(directory).join("tampered.json")
      tampered.write(JSON.generate(payload))
      release = Warehouse::InstitutionRelease.create!(
        version: "2099-01-06", effective_on: Date.new(2099, 1, 6), schema_version: "1.0",
        published_at: Time.utc(2099, 1, 6), geography_vintage: 2021, attribution: "Test"
      )

      error = assert_raises(Warehouse::InstitutionRelease::FirstNations::ManifestImporter::ImportError) do
        Warehouse::InstitutionRelease::FirstNations::ManifestImporter.new(release: release, path: tampered).import!
      end
      assert_match(/headquartered_in/, error.message)
    end
  end

  test "manifest importer supports Indigenous governments that are not ISC bands" do
    Dir.mktmpdir do |directory|
      manifest_path = Warehouse::InstitutionRelease::FirstNations::SourceAdapter.new(
        release_version: "2099-01-07", output_root: directory,
        http_client: FakeFirstNationsHttp.new, retrieved_at: Time.utc(2099, 1, 7), workers: 1
      ).call
      payload = JSON.parse(manifest_path.read)
      payload.fetch("sources") << {
        "key" => "treaty_government", "canonical_id" => "ca/sources/test/treaty-government",
        "publisher" => "Test Treaty Government", "title_en" => "Official government website",
        "url" => "https://government.example", "languages" => [ "en" ]
      }
      payload["indigenous_governments"] = [ {
        "canonical_id" => "ca/fn/test-treaty-government", "name_en" => "Test Treaty Government",
        "government_level" => "first_nation", "legal_form" => "Treaty self-government",
        "website_url" => "https://government.example", "source_key" => "treaty_government"
      } ]
      manifest_path.write(JSON.pretty_generate(payload))
      release = Warehouse::InstitutionRelease.create!(
        version: "2099-01-07", effective_on: Date.new(2099, 1, 7), schema_version: "1.0",
        published_at: Time.utc(2099, 1, 7), geography_vintage: 2021, attribution: "Test"
      )

      Warehouse::InstitutionRelease::FirstNations::ManifestImporter.new(
        release: release, path: manifest_path
      ).import!

      institution = release.institutions.find_by!(canonical_id: "ca/fn/test-treaty-government")
      assert_equal "Treaty self-government", institution.legal_form
      assert_equal "first_nation", institution.government_level
      refute institution.institution_identifiers.exists?(scheme: "isc.band_number")
    end
  end

  class FakeFirstNationsHttp
    def get(url, params: nil, **)
      case url
      when Warehouse::InstitutionRelease::FirstNations::SourceAdapter::ISC_LOCATION_EN
        JSON.generate(features: english.map { |attributes| { attributes: attributes } }, exceededTransferLimit: false)
      when Warehouse::InstitutionRelease::FirstNations::SourceAdapter::ISC_LOCATION_FR
        JSON.generate(features: french.map { |attributes| { attributes: attributes } }, exceededTransferLimit: false)
      when Warehouse::InstitutionRelease::FirstNations::SourceAdapter::STATCAN_CSD_EN
        JSON.generate(features: [ { attributes: {
          CSDUID: "1234567", DGUID: "2021A00051234567", CSDNAME: "Test Reserve", CSDTYPE: "IRI", PRUID: "12"
        } } ])
      when Warehouse::InstitutionRelease::FirstNations::SourceAdapter::STATCAN_CSD_FR
        JSON.generate(features: [ { attributes: {
          SDRIDU: "1234567", IDUGD: "2021A00051234567", SDRNOM: "Réserve test", SDRGENRE: "IRI", PRIDU: "12"
        } } ])
      else
        dynamic_response(url)
      end
    end

    private

    def english
      [
        location(1, "Test Nation", parent: nil),
        location(2, "Test-Nation", parent: 1)
      ]
    end

    def french
      [
        location(1, "Nation test", parent: nil),
        location(2, "Nation-test", parent: 1)
      ]
    end

    def location(number, name, parent:)
      {
        BAND_NUMBER: number, BAND_NAME: name, LATITUDE: 44.5, LONGITUDE: -63.5,
        MOST_POPULATED_RESERVE_NUM: 100 + number, MOST_POPULATED_RESERVE_NAME: "Test Reserve",
        PARENT_FIRST_NATION: parent, PARENT_FIRST_NATION_NAME: parent && "Test Nation"
      }
    end

    def dynamic_response(url)
      uri = URI(url)
      query = CGI.parse(uri.query.to_s).transform_values(&:first)
      number = query.fetch("BAND_NUMBER")
      if uri.path.end_with?("FNMain.aspx")
        <<~HTML
          <html><table><tr><td>Phone:</td><td>555-000#{number}</td></tr>
          <tr><td>Address:</td><td>#{number} Main Street</td></tr></table>
          <a id="plcMain_anchor1" href="https://nation-#{number == '1' ? 'one' : 'two'}.example">Web Site</a></html>
        HTML
      elsif uri.path.end_with?("FederalFundingMain.aspx")
        fnfta(number, query.fetch("lang"))
      else
        raise "unexpected test URL #{url}"
      end
    end

    def fnfta(number, language)
      title = language == "fra" ? "États financiers consolidés vérifiés" : "Audited consolidated financial statements"
      href = number == "1" ? "DisplayBinaryData.aspx?BAND_NUMBER_FF=1&amp;FY=2024-2025&amp;DOC=Audited" : "#"
      <<~HTML
        <html><table><tr><th>Fiscal Year</th><th>Document</th><th>Date Received</th></tr>
        <tr><td>2024-2025</td><td><a href="#{href}">#{title}</a></td><td>2025-07-15</td></tr></table></html>
      HTML
    end
  end
end
