class Warehouse::RawIngestion::RecordBrowser
  LIMIT = 100
  Dataset = Data.define(:name, :count)
  Result = Data.define(:columns, :rows)

  def initialize(raw_ingestion, connection: Warehouse::Record.connection)
    @raw_ingestion = raw_ingestion
    @connection = connection
  end

  def datasets
    @datasets ||= dataset_names.map do |name|
      Dataset.new(name:, count: count_for(name))
    end
  end

  def records(dataset_name)
    name = dataset_name.to_s
    raise ActiveRecord::RecordNotFound unless dataset_names.include?(name)

    result = connection.exec_query(<<~SQL)
      SELECT *
      FROM #{qualified_table(name)}
      WHERE raw_ingestion_id = #{connection.quote(raw_ingestion.id)}
      ORDER BY id DESC
      LIMIT #{LIMIT}
    SQL

    Result.new(columns: result.columns, rows: result.to_a)
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

  def count_for(name)
    connection.select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM #{qualified_table(name)}
      WHERE raw_ingestion_id = #{connection.quote(raw_ingestion.id)}
    SQL
  end

  def qualified_table(name)
    "#{connection.quote_table_name('warehouse')}.#{connection.quote_table_name(name)}"
  end
end
