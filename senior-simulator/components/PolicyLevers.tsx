"use client";

import type { PolicyParams } from "@/lib/types";

interface Props {
  policy: PolicyParams;
  onChange: (policy: PolicyParams) => void;
}

function Slider({
  label,
  value,
  onChange,
  min,
  max,
  step,
  format,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  min: number;
  max: number;
  step: number;
  format: (v: number) => string;
}) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex justify-between items-center">
        <label className="text-sm font-medium text-gray-300">{label}</label>
        <span className="text-sm font-mono text-amber-400">{format(value)}</span>
      </div>
      <input
        type="range"
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        min={min}
        max={max}
        step={step}
        className="w-full accent-amber-500"
      />
    </div>
  );
}

function Toggle({
  label,
  description,
  checked,
  onChange,
}: {
  label: string;
  description: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <label className="flex items-start gap-3 cursor-pointer group">
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="mt-1 accent-amber-500"
      />
      <div>
        <span className="text-sm font-medium text-white group-hover:text-amber-400 transition-colors">{label}</span>
        <p className="text-xs text-gray-400">{description}</p>
      </div>
    </label>
  );
}

const dollarFmt = (v: number) => `$${(v / 1000).toFixed(0)}K`;
const pctFmt = (v: number) => `${(v * 100).toFixed(1)}%`;
const dollarFmtFull = (v: number) => `$${v.toLocaleString()}`;

export default function PolicyLevers({ policy, onChange }: Props) {
  const set = (key: keyof PolicyParams, value: number | string | boolean) =>
    onChange({ ...policy, [key]: value });

  return (
    <div className="space-y-5">
      <h3 className="text-lg font-semibold text-white">Policy Levers</h3>

      {/* GIS Clawback Regime */}
      <div className="space-y-2">
        <label className="text-sm font-semibold text-gray-400 uppercase tracking-wide">GIS Clawback Regime</label>
        <div className="flex gap-2">
          {(["current", "ccb_style", "custom"] as const).map((regime) => (
            <button
              key={regime}
              onClick={() => set("gis_clawback_regime", regime)}
              className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${
                (policy.gis_clawback_regime ?? "current") === regime
                  ? "bg-amber-600 text-white"
                  : "bg-gray-700 text-gray-300 hover:bg-gray-600"
              }`}
            >
              {regime === "current" ? "Current (50%)" : regime === "ccb_style" ? "CCB-Style" : "Custom"}
            </button>
          ))}
        </div>
      </div>

      {/* CCB-style parameters */}
      {(policy.gis_clawback_regime ?? "current") === "ccb_style" && (
        <div className="space-y-3 pl-3 border-l-2 border-amber-600/50">
          <Slider label="Lower rate" value={policy.gis_ccb_lower_rate ?? 0.10} onChange={(v) => set("gis_ccb_lower_rate", v)} min={0.01} max={0.30} step={0.01} format={pctFmt} />
          <Slider label="Upper rate" value={policy.gis_ccb_upper_rate ?? 0.05} onChange={(v) => set("gis_ccb_upper_rate", v)} min={0.01} max={0.20} step={0.01} format={pctFmt} />
          <Slider label="Lower threshold" value={policy.gis_ccb_lower_threshold ?? 5000} onChange={(v) => set("gis_ccb_lower_threshold", v)} min={0} max={20000} step={1000} format={dollarFmt} />
          <Slider label="Upper threshold" value={policy.gis_ccb_upper_threshold ?? 40000} onChange={(v) => set("gis_ccb_upper_threshold", v)} min={20000} max={80000} step={1000} format={dollarFmt} />
        </div>
      )}

      {/* Custom rate */}
      {(policy.gis_clawback_regime ?? "current") === "custom" && (
        <div className="pl-3 border-l-2 border-amber-600/50">
          <Slider label="Custom reduction rate" value={policy.gis_custom_rate ?? 0.50} onChange={(v) => set("gis_custom_rate", v)} min={0.05} max={0.75} step={0.01} format={pctFmt} />
        </div>
      )}

      {/* OAS */}
      <div className="space-y-3">
        <label className="text-sm font-semibold text-gray-400 uppercase tracking-wide">OAS Clawback</label>
        <Slider label="Clawback threshold" value={policy.oas_clawback_threshold ?? 90997} onChange={(v) => set("oas_clawback_threshold", v)} min={50000} max={200000} step={1000} format={dollarFmtFull} />
        <Slider label="Clawback rate" value={policy.oas_clawback_rate ?? 0.15} onChange={(v) => set("oas_clawback_rate", v)} min={0.05} max={0.50} step={0.01} format={pctFmt} />
      </div>

      {/* Loophole closures */}
      <div className="space-y-3">
        <label className="text-sm font-semibold text-gray-400 uppercase tracking-wide">Close Loopholes</label>
        <Toggle
          label="Count TFSA withdrawals for GIS"
          description="TFSA withdrawals are currently invisible to means tests. Millionaires collect full GIS."
          checked={policy.include_tfsa_in_gis ?? false}
          onChange={(v) => set("include_tfsa_in_gis", v)}
        />
        <Toggle
          label="Count corporate income"
          description="Capital dividends from CCPCs are tax-free and hidden from means tests."
          checked={policy.include_corporate_income ?? false}
          onChange={(v) => set("include_corporate_income", v)}
        />
      </div>

      {/* Wealth test */}
      <div className="space-y-3">
        <Toggle
          label="Enable wealth test"
          description="Reduce OAS based on net worth, not just income. Primary residence partially exempt."
          checked={policy.wealth_test_enabled ?? false}
          onChange={(v) => set("wealth_test_enabled", v)}
        />
        {(policy.wealth_test_enabled ?? false) && (
          <div className="space-y-3 pl-3 border-l-2 border-amber-600/50">
            <Slider label="Wealth threshold" value={policy.wealth_test_threshold ?? 2000000} onChange={(v) => set("wealth_test_threshold", v)} min={500000} max={5000000} step={100000} format={(v) => `$${(v / 1000000).toFixed(1)}M`} />
            <Slider label="Home exemption" value={policy.wealth_test_home_exemption ?? 500000} onChange={(v) => set("wealth_test_home_exemption", v)} min={0} max={2000000} step={50000} format={dollarFmtFull} />
          </div>
        )}
      </div>
    </div>
  );
}
