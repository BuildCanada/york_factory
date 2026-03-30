"use client";

import { currency } from "@/lib/formatters";

interface Props {
  difference: {
    net_income_change: number;
    oas_change: number;
    gis_change: number;
    tax_change: number;
    total_benefits_change: number;
  };
}

function DiffRow({ label, value }: { label: string; value: number }) {
  const color = value > 0 ? "text-green-400" : value < 0 ? "text-red-400" : "text-gray-400";
  const sign = value > 0 ? "+" : "";
  return (
    <div className="flex justify-between items-center py-1">
      <span className="text-sm text-gray-300">{label}</span>
      <span className={`text-sm font-mono ${color}`}>
        {sign}{currency(value)}
      </span>
    </div>
  );
}

export default function ComparisonPanel({ difference }: Props) {
  return (
    <div className="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
      <h4 className="text-sm font-semibold text-amber-400 mb-3">Impact of Proposed Changes</h4>
      <DiffRow label="OAS Change" value={difference.oas_change} />
      <DiffRow label="GIS Change" value={difference.gis_change} />
      <DiffRow label="Tax Change" value={difference.tax_change} />
      <div className="border-t border-gray-700 my-2" />
      <DiffRow label="Benefits Change" value={difference.total_benefits_change} />
      <div className="border-t border-gray-700 my-2" />
      <div className="flex justify-between items-center py-1">
        <span className="text-base font-semibold text-white">Net Income Change</span>
        <span
          className={`text-lg font-bold font-mono ${
            difference.net_income_change > 0
              ? "text-green-400"
              : difference.net_income_change < 0
              ? "text-red-400"
              : "text-gray-400"
          }`}
        >
          {difference.net_income_change > 0 ? "+" : ""}
          {currency(difference.net_income_change)}
        </span>
      </div>
    </div>
  );
}
