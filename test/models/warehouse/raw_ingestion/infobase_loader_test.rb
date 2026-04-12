require "test_helper"

class Warehouse::RawIngestion::InfobaseLoaderTest < ActiveSupport::TestCase
  setup do
    @source = Warehouse::Source.create!(name: "infobase_test", url: "https://example.com/test.csv", format: "csv")
    @ingestion = Warehouse::RawIngestion.create!(
      source: @source,
      fetched_at: Time.current,
      raw_file_path: "raw/test/data.csv",
      checksum: "abc123",
      status: :pending
    )
  end

  test "loads InfoBase CSV with voted expenditures" do
    csv = <<~CSV
      "fy_ef","org_id","org_name","voted_or_statutory","description","authorities","expenditures"
      "2023-24",1,"Department of Agriculture and Agri-Food",1,"Operating/Program",756690489.00,704941276.00
    CSV

    @ingestion.infobase_loader.load(csv_content: csv)

    assert_equal "complete", @ingestion.reload.status
    assert_equal 1, Warehouse::FiscalExpenditure.count

    fe = Warehouse::FiscalExpenditure.first
    assert_equal "2023-24", fe.fiscal_year
    assert_equal "operating", fe.vote_type
    assert_equal "1", fe.vote_number
    assert_equal 756_690_489.00, fe.pa_voted_ceiling.to_f
    assert_equal 704_941_276.00, fe.actual_expenditure.to_f
  end

  test "loads statutory expenditures" do
    csv = <<~CSV
      "fy_ef","org_id","org_name","voted_or_statutory","description","authorities","expenditures"
      "2023-24",1,"Department of Agriculture and Agri-Food","S","Some Statutory Item",4893823.00,4893823.00
    CSV

    @ingestion.infobase_loader.load(csv_content: csv)

    fe = Warehouse::FiscalExpenditure.first
    assert_equal "statutory", fe.vote_type
    assert_equal "S", fe.vote_number
  end

  test "handles negative expenditure values" do
    csv = <<~CSV
      "fy_ef","org_id","org_name","voted_or_statutory","description","authorities","expenditures"
      "2023-24",1,"Department of Agriculture and Agri-Food","S","Revolving Fund",3922399.00,-253649.28
    CSV

    @ingestion.infobase_loader.load(csv_content: csv)

    fe = Warehouse::FiscalExpenditure.first
    assert_equal(-253_649.28, fe.actual_expenditure.to_f)
  end

  test "creates organizations and aliases" do
    csv = <<~CSV
      "fy_ef","org_id","org_name","voted_or_statutory","description","authorities","expenditures"
      "2023-24",1,"Department of Agriculture and Agri-Food",1,"Operating",100,100
    CSV

    @ingestion.infobase_loader.load(csv_content: csv)

    org = Warehouse::Organization.find_by(org_id_infobase: 1)
    assert_not_nil org
    assert_equal "Department of Agriculture and Agri-Food", org.canonical_name
    assert org.organization_aliases.exists?(alias_name: "Department of Agriculture and Agri-Food")
  end

  test "is idempotent — re-running same CSV does not duplicate" do
    csv = <<~CSV
      "fy_ef","org_id","org_name","voted_or_statutory","description","authorities","expenditures"
      "2023-24",1,"Department of Agriculture and Agri-Food",1,"Operating",100,100
    CSV

    @ingestion.infobase_loader.load(csv_content: csv)

    # Create a second ingestion with same data
    ingestion2 = Warehouse::RawIngestion.create!(
      source: @source,
      fetched_at: Time.current,
      raw_file_path: "raw/test/data2.csv",
      checksum: "def456",
      status: :pending
    )
    ingestion2.infobase_loader.load(csv_content: csv)

    # Should still be 1 org and 1 expenditure (updated, not duplicated)
    assert_equal 1, Warehouse::Organization.count
    assert_equal 1, Warehouse::FiscalExpenditure.count
  end

  test "maps vote types correctly" do
    csv = <<~CSV
      "fy_ef","org_id","org_name","voted_or_statutory","description","authorities","expenditures"
      "2023-24",1,"Dept A",1,"Operating",100,100
      "2023-24",1,"Dept A",5,"Capital",200,200
      "2023-24",1,"Dept A",10,"Grants",300,300
      "2023-24",1,"Dept A","S","Statutory",400,400
    CSV

    @ingestion.infobase_loader.load(csv_content: csv)

    types = Warehouse::FiscalExpenditure.pluck(:vote_type).sort
    assert_equal [ "capital", "grants_contributions", "operating", "statutory" ], types
  end

  test "creates lineage entries for each row" do
    csv = <<~CSV
      "fy_ef","org_id","org_name","voted_or_statutory","description","authorities","expenditures"
      "2023-24",1,"Department of Agriculture",1,"Operating",100,100
    CSV

    @ingestion.infobase_loader.load(csv_content: csv)

    assert_equal 1, Warehouse::LineageEntry.count
    entry = Warehouse::LineageEntry.first
    assert_equal "deterministic", entry.transformation_type
    assert_equal 1.0, entry.confidence.to_f
  end
end
