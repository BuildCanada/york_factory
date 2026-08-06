class CanadaSpendsController < ApplicationController
  def show
    source_name = Warehouse::Spending::Datasets.source_name_for(params[:database])
    award = Warehouse::SpendingAward.published.includes(:source).joins(:source)
      .merge(Warehouse::Source.where(name: source_name)).find_by(external_key: params[:id])
    return render json: [], status: :not_found unless award

    render json: [ Warehouse::Spending::Serializer.legacy(award, slug: params[:database]) ]
  rescue KeyError
    render json: [], status: :not_found
  end
end
