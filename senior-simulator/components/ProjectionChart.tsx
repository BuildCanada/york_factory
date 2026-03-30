"use client";

import {
  ComposedChart,
  Bar,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";
import type { ProjectionPoint } from "@/lib/types";
import { billions } from "@/lib/formatters";

interface Props {
  data: ProjectionPoint[];
}

export default function ProjectionChart({ data }: Props) {
  // Show every 5th year for cleaner labels
  const filteredData = data.filter((_, i) => i % 5 === 0 || i === data.length - 1);

  return (
    <div className="space-y-6">
      {/* Cost projection */}
      <div>
        <h4 className="text-sm font-semibold text-gray-400 uppercase tracking-wide mb-3">
          Total OAS + GIS Cost (2025-2050)
        </h4>
        <div className="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
          <ResponsiveContainer width="100%" height={300}>
            <ComposedChart data={data} margin={{ top: 5, right: 20, bottom: 5, left: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
              <XAxis dataKey="year" stroke="#9CA3AF" fontSize={12} />
              <YAxis
                yAxisId="cost"
                tickFormatter={(v) => `$${v}B`}
                stroke="#9CA3AF"
                fontSize={12}
              />
              <YAxis
                yAxisId="ratio"
                orientation="right"
                tickFormatter={(v) => `${v}:1`}
                stroke="#9CA3AF"
                fontSize={12}
              />
              <Tooltip
                contentStyle={{ backgroundColor: "#1F2937", border: "1px solid #374151", borderRadius: "8px" }}
                formatter={(value, name) => {
                  const v = Number(value);
                  if (name === "oas_cost_billions") return [billions(v), "OAS Cost"];
                  if (name === "gis_cost_billions") return [billions(v), "GIS Cost"];
                  if (name === "worker_to_retiree_ratio") return [`${v}:1`, "Workers per Retiree"];
                  return [String(value), String(name)];
                }}
              />
              <Legend
                formatter={(value) => {
                  if (value === "oas_cost_billions") return "OAS Cost";
                  if (value === "gis_cost_billions") return "GIS Cost";
                  if (value === "worker_to_retiree_ratio") return "Workers per Retiree";
                  return value;
                }}
              />
              <Bar dataKey="oas_cost_billions" yAxisId="cost" stackId="cost" fill="#F59E0B" isAnimationActive={false} />
              <Bar dataKey="gis_cost_billions" yAxisId="cost" stackId="cost" fill="#D97706" isAnimationActive={false} />
              <Line
                type="monotone"
                dataKey="worker_to_retiree_ratio"
                yAxisId="ratio"
                stroke="#EF4444"
                strokeWidth={2}
                dot={false}
                isAnimationActive={false}
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Cost per worker */}
      <div>
        <h4 className="text-sm font-semibold text-gray-400 uppercase tracking-wide mb-3">
          Intergenerational Burden: Cost per Working-Age Canadian
        </h4>
        <div className="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
          <ResponsiveContainer width="100%" height={250}>
            <ComposedChart data={data} margin={{ top: 5, right: 20, bottom: 5, left: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
              <XAxis dataKey="year" stroke="#9CA3AF" fontSize={12} />
              <YAxis
                tickFormatter={(v) => `$${(v / 1000).toFixed(0)}K`}
                stroke="#9CA3AF"
                fontSize={12}
              />
              <Tooltip
                contentStyle={{ backgroundColor: "#1F2937", border: "1px solid #374151", borderRadius: "8px" }}
                formatter={(value) => [`$${Number(value).toLocaleString()}`, "Cost per Worker"]}
              />
              <Bar dataKey="cost_per_working_canadian" fill="#EF4444" isAnimationActive={false} />
            </ComposedChart>
          </ResponsiveContainer>
          <p className="text-xs text-gray-500 mt-2">
            Every working-age Canadian implicitly pays this amount annually to fund OAS + GIS through federal taxes. This amount is growing faster than wages.
          </p>
        </div>
      </div>

      {/* Key stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {filteredData.map((point) => (
          <div key={point.year} className="bg-gray-800/50 rounded-lg p-3 border border-gray-700 text-center">
            <div className="text-lg font-bold text-amber-400">{point.year}</div>
            <div className="text-sm text-gray-300">{billions(point.total_cost_billions)}</div>
            <div className="text-xs text-gray-500">${point.cost_per_working_canadian.toLocaleString()}/worker</div>
            <div className="text-xs text-red-400">{point.worker_to_retiree_ratio}:1 ratio</div>
          </div>
        ))}
      </div>
    </div>
  );
}
