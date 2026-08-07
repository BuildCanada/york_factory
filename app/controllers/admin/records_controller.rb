module Admin
  class RecordsController < BaseController
    def index
      @ingestions = Warehouse::RawIngestion.includes(:source).order(fetched_at: :desc).limit(100)
      return unless params[:raw_ingestion_id].present?

      @ingestion = Warehouse::RawIngestion.includes(:source).find(params[:raw_ingestion_id])
      @browser = Warehouse::RawIngestion::RecordBrowser.new(@ingestion)
      @datasets = @browser.datasets
      @dataset = params[:dataset].presence || @datasets.find { |dataset| dataset.count.positive? }&.name
      @result = @browser.records(@dataset) if @dataset
    end
  end
end
