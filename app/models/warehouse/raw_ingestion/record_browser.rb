class Warehouse::RawIngestion::RecordBrowser
  LIMIT = 100
  Result = Data.define(:columns, :rows)

  def initialize(raw_ingestion, connection: Warehouse::Record.connection)
    @raw_ingestion = raw_ingestion
    @connection = connection
  end

  def datasets
    dataset_names
  end

  def records(dataset_name)
    model = model_for(dataset_name)
    rows = model.where(raw_ingestion_id: raw_ingestion.id).order(id: :desc).limit(LIMIT)

    Result.new(columns: model.column_names, rows: rows.map(&:attributes))
  end

  private

  attr_reader :connection, :raw_ingestion

  def dataset_names
    @dataset_names ||= connection.select_values(<<~SQL)
      SELECT table_name
      FROM information_schema.columns
      WHERE table_schema = 'warehouse'
        AND column_name = 'raw_ingestion_id'
      ORDER BY table_name
    SQL
  end

  def model_for(dataset_name)
    name = dataset_name.to_s
    raise ActiveRecord::RecordNotFound unless dataset_names.include?(name)

    Class.new(Warehouse::Record) do
      self.table_name = "warehouse.#{name}"
    end
  end
end
