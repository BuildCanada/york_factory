"use client";

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
  Legend,
  Area,
  ComposedChart,
} from "recharts";
import type { MarginalRatePoint } from "@/lib/types";
import { currency, pct } from "@/lib/formatters";

interface Props {
  currentData: MarginalRatePoint[];
  proposedData?: MarginalRatePoint[];
}

export default function EmtrChart({ currentData, proposedData }: Props) {
  // Merge data for comparison
  const data = currentData.map((point, i) => ({
    income: point.income,
    current_emtr: point.emtr,
    current_net: point.net_income,
    proposed_emtr: proposedData?.[i]?.emtr,
    proposed_net: proposedData?.[i]?.net_income,
  }));

  return (
    <div className="space-y-6">
      {/* EMTR Chart */}
      <div>
        <h4 className="text-sm font-semibold text-gray-400 uppercase tracking-wide mb-3">
          Effective Marginal Tax Rate
        </h4>
        <div className="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
          <ResponsiveContainer width="100%" height={300}>
            <ComposedChart data={data} margin={{ top: 5, right: 20, bottom: 5, left: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
              <XAxis
                dataKey="income"
                tickFormatter={(v) => `$${(v / 1000).toFixed(0)}K`}
                stroke="#9CA3AF"
                fontSize={12}
              />
              <YAxis
                tickFormatter={(v) => `${(v * 100).toFixed(0)}%`}
                domain={[0, 1]}
                stroke="#9CA3AF"
                fontSize={12}
              />
              <Tooltip
                contentStyle={{ backgroundColor: "#1F2937", border: "1px solid #374151", borderRadius: "8px" }}
                labelFormatter={(v) => `Income: ${currency(v as number)}`}
                formatter={(value, name) => [
                  pct(Number(value)),
                  name === "current_emtr" ? "Current EMTR" : "Proposed EMTR",
                ]}
              />
              <Legend
                formatter={(value) => (value === "current_emtr" ? "Current" : "Proposed")}
              />
              {/* Danger zone background */}
              <ReferenceLine y={0.5} stroke="#EF4444" strokeDasharray="5 5" label={{ value: "50%", fill: "#EF4444", fontSize: 11 }} />
              <Area
                dataKey="current_emtr"
                fill="#EF444420"
                stroke="none"
                isAnimationActive={false}
              />
              <Line
                type="stepAfter"
                dataKey="current_emtr"
                stroke="#EF4444"
                strokeWidth={2}
                dot={false}
                isAnimationActive={false}
              />
              {proposedData && (
                <Line
                  type="stepAfter"
                  dataKey="proposed_emtr"
                  stroke="#34D399"
                  strokeWidth={2}
                  dot={false}
                  strokeDasharray="5 5"
                  isAnimationActive={false}
                />
              )}
            </ComposedChart>
          </ResponsiveContainer>
          <p className="text-xs text-gray-500 mt-2">
            Higher EMTR = less incentive to earn. Above 50% (red line), a senior keeps less than half of each additional dollar.
          </p>
        </div>
      </div>

      {/* Net Income Chart */}
      <div>
        <h4 className="text-sm font-semibold text-gray-400 uppercase tracking-wide mb-3">
          Net Income After Tax & Clawbacks
        </h4>
        <div className="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={data} margin={{ top: 5, right: 20, bottom: 5, left: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
              <XAxis
                dataKey="income"
                tickFormatter={(v) => `$${(v / 1000).toFixed(0)}K`}
                stroke="#9CA3AF"
                fontSize={12}
              />
              <YAxis
                tickFormatter={(v) => `$${(v / 1000).toFixed(0)}K`}
                stroke="#9CA3AF"
                fontSize={12}
              />
              <Tooltip
                contentStyle={{ backgroundColor: "#1F2937", border: "1px solid #374151", borderRadius: "8px" }}
                labelFormatter={(v) => `Market Income: ${currency(v as number)}`}
                formatter={(value, name) => [
                  currency(Number(value)),
                  name === "current_net" ? "Current Net" : "Proposed Net",
                ]}
              />
              <Legend
                formatter={(value) => (value === "current_net" ? "Current" : "Proposed")}
              />
              <Line type="monotone" dataKey="current_net" stroke="#F59E0B" strokeWidth={2} dot={false} isAnimationActive={false} />
              {proposedData && (
                <Line type="monotone" dataKey="proposed_net" stroke="#34D399" strokeWidth={2} dot={false} strokeDasharray="5 5" isAnimationActive={false} />
              )}
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
}
