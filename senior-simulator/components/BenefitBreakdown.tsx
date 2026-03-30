"use client";

import type { BenefitSummary } from "@/lib/types";
import { currency, pct } from "@/lib/formatters";

interface Props {
  summary: BenefitSummary;
  label?: string;
}

function Row({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="flex justify-between items-center py-1">
      <span className="text-sm text-gray-300">{label}</span>
      <span className={`text-sm font-mono ${color ?? "text-white"}`}>{value}</span>
    </div>
  );
}

function Divider() {
  return <div className="border-t border-gray-700 my-1" />;
}

export default function BenefitBreakdown({ summary, label }: Props) {
  return (
    <div className="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
      {label && <h4 className="text-sm font-semibold text-amber-400 mb-3">{label}</h4>}

      <Row label="Employment" value={currency(summary.employment_income)} />
      <Row label="CPP / Pension" value={currency(summary.pension_income)} />
      <Row label="Investment" value={currency(summary.investment_income)} />
      <Row label="RRIF" value={currency(summary.rrif_income)} />
      <Divider />
      <Row label="Market Income" value={currency(summary.total_market_income)} color="text-gray-100" />

      <div className="mt-2" />
      <Row label="+ OAS Benefit" value={currency(summary.oas_benefit)} color="text-green-400" />
      <Row label="+ GIS Benefit" value={currency(summary.gis_benefit)} color="text-green-400" />
      <Divider />
      <Row label="Total Benefits" value={currency(summary.total_benefits)} color="text-green-300" />

      <div className="mt-2" />
      <Row label="- Federal Tax" value={currency(summary.federal_tax)} color="text-red-400" />
      <Divider />

      <div className="flex justify-between items-center py-2">
        <span className="text-base font-semibold text-white">Net Income</span>
        <span className="text-lg font-bold font-mono text-amber-400">{currency(summary.net_income)}</span>
      </div>

      <div className="mt-2 flex gap-4">
        <div className="text-xs text-gray-400">
          Effective tax rate: <span className="text-gray-200">{pct(summary.effective_tax_rate)}</span>
        </div>
      </div>
    </div>
  );
}
