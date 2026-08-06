module Warehouse::Spending::Scrapers
  class TransferPayments < Base
    SOURCE_URL = "https://open.canada.ca/data/en/dataset/69bdc3eb-e919-4854-bc52-a435a3e19092"

    private

    def each_attributes(payload)
      each_csv(payload) do |row|
        year = fiscal_year(value(row, "FSCL_YR", "Fscl-yr_Ex-fin"))
        payer_name = clean(value(row, "DEPT_EN_DESC", "Dept-name_Nom-min_eng")) ||
          clean(value(row, "MINE", "Min-portfolio_Portefeuille-min_eng"))
        program_name = clean(value(row, "RCPNT_CLS_EN_DESC", "Rcpt-class_Cat-bnfcrs_eng"))
        recipient_name = clean(value(row, "RCPNT_NML_EN_DESC", "Rcpt-nm-locn_Nm-lieu-bnfcrs_eng"))
        next if year.nil? || payer_name.blank? || program_name.blank?

        aggregated = recipient_name.blank? || recipient_name.match?(/payments under/i)
        total_amount = amount(value(row, "TOT_CY_XPND_AMT", "Xpnd-current-yr_Dep-ex-courant"))
        aggregate_amount = amount(value(row, "AGRG_PYMT_AMT", "Aggregate-payments_Versements-totalisant"))
        payment_amount = aggregated ? total_amount&.nonzero? || aggregate_amount :
          aggregate_amount&.nonzero? || total_amount

        yield(
          external_key: stable_key(row.values),
          award_type: "transfer_payment",
          language: "en",
          title: recipient_name || program_name,
          description: program_name,
          payer_name: payer_name,
          recipient_name: recipient_name || "Multiple recipients",
          recipient_type: aggregated ? "multiple" : "grantee",
          program_name: program_name,
          program_key: clean(value(row, "DepartmentNumber-Numéro-de-Ministère", "Dept-nbr_No-min")),
          fiscal_year: year,
          occurred_at: occurred_at("#{year}-04-01"),
          amount: payment_amount,
          currency: "CAD",
          is_aggregated: aggregated,
          source_url: SOURCE_URL,
          province_code: province_code(value(row, "PROVTER_EN", "Prov-Terr_eng")),
          country_code: transfer_country_code(value(row, "CNTRY_EN_NM", "Country_Pays_eng")),
          metadata: transfer_metadata(row)
        )
      end
    end

    def transfer_country_code(value)
      country = clean(value)
      country.blank? ? "CA" : country_code(country)
    end

    def transfer_metadata(row)
      total_amount = amount(value(row, "TOT_CY_XPND_AMT", "Xpnd-current-yr_Dep-ex-courant"))
      aggregate_amount = amount(value(row, "AGRG_PYMT_AMT", "Aggregate-payments_Versements-totalisant"))
      row.transform_values { |value| clean(value) }.compact.merge(
        "FSCL_YR" => clean(value(row, "FSCL_YR", "Fscl-yr_Ex-fin")),
        "ministry_code" => clean(value(row, "MINC", "Min-code")),
        "ministry_name" => clean(value(row, "MINE", "Min-portfolio_Portefeuille-min_eng")),
        "department_number" => clean(value(row, "DepartmentNumber-Numéro-de-Ministère", "Dept-nbr_No-min")),
        "recipient_class_fr" => clean(value(row, "RCPNT_CLS_FR_DESC", "Rcpt-class_Cat-bnfcrs_fra")),
        "recipient_name_fr" => clean(value(row, "RCPNT_NML_FR_DESC", "Rcpt-nm-locn_Nm-lieu-bnfcrs_fra")),
        "city" => clean(value(row, "CTY_EN_NM", "City_Ville_eng")),
        "country" => clean(value(row, "CNTRY_EN_NM", "Country_Pays_eng")),
        "total_current_year_expenditure" => total_amount,
        "TOT_CY_XPND_AMT" => total_amount&.to_f,
        "AGRG_PYMT_AMT" => aggregate_amount&.to_f,
        "aggregate_payment_amount" => aggregate_amount
      ).compact
    end

    def value(row, *names)
      names.each do |name|
        result = row[name]
        return result if result.present?
      end
      nil
    end
  end
end
