"use client";

import type { Profile } from "@/lib/types";

interface Props {
  profile: Partial<Profile>;
  onChange: (profile: Partial<Profile>) => void;
}

function Field({
  label,
  value,
  onChange,
  min = 0,
  max,
  step = 1,
  prefix,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  min?: number;
  max?: number;
  step?: number;
  prefix?: string;
}) {
  return (
    <div className="flex flex-col gap-1">
      <label className="text-sm font-medium text-gray-300">{label}</label>
      <div className="flex items-center gap-2">
        {prefix && <span className="text-gray-400 text-sm">{prefix}</span>}
        <input
          type="number"
          value={value}
          onChange={(e) => onChange(Number(e.target.value))}
          min={min}
          max={max}
          step={step}
          className="w-full bg-gray-800 border border-gray-600 rounded px-3 py-1.5 text-sm text-white"
        />
      </div>
    </div>
  );
}

export default function ProfileForm({ profile, onChange }: Props) {
  const set = (key: keyof Profile, value: number | string) =>
    onChange({ ...profile, [key]: value });

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-white">Individual Profile</h3>

      <div className="grid grid-cols-2 gap-3">
        <Field label="Age" value={profile.age ?? 70} onChange={(v) => set("age", v)} min={18} max={99} />
        <div className="flex flex-col gap-1">
          <label className="text-sm font-medium text-gray-300">Status</label>
          <select
            value={profile.marital_status ?? "single"}
            onChange={(e) => set("marital_status", e.target.value)}
            className="bg-gray-800 border border-gray-600 rounded px-3 py-1.5 text-sm text-white"
          >
            <option value="single">Single</option>
            <option value="coupled">Coupled</option>
          </select>
        </div>
      </div>

      <Field
        label="Years in Canada"
        value={profile.years_in_canada ?? 40}
        onChange={(v) => set("years_in_canada", v)}
        min={0}
        max={80}
      />

      <h4 className="text-sm font-semibold text-gray-400 uppercase tracking-wide pt-2">Income Sources</h4>

      <div className="grid grid-cols-2 gap-3">
        <Field label="Employment" prefix="$" value={profile.employment_income ?? 0} onChange={(v) => set("employment_income", v)} step={1000} />
        <Field label="CPP / Pension" prefix="$" value={profile.pension_income ?? 0} onChange={(v) => set("pension_income", v)} step={1000} />
        <Field label="Investment" prefix="$" value={profile.investment_income ?? 0} onChange={(v) => set("investment_income", v)} step={1000} />
        <Field label="RRIF" prefix="$" value={profile.rrif_income ?? 0} onChange={(v) => set("rrif_income", v)} step={1000} />
      </div>

      <h4 className="text-sm font-semibold text-gray-400 uppercase tracking-wide pt-2">Hidden Income (Gaming)</h4>

      <div className="grid grid-cols-2 gap-3">
        <Field label="TFSA Withdrawals" prefix="$" value={profile.tfsa_withdrawals ?? 0} onChange={(v) => set("tfsa_withdrawals", v)} step={1000} />
        <Field label="Corporate Income" prefix="$" value={profile.corporate_income ?? 0} onChange={(v) => set("corporate_income", v)} step={1000} />
      </div>

      <h4 className="text-sm font-semibold text-gray-400 uppercase tracking-wide pt-2">Assets</h4>

      <div className="grid grid-cols-2 gap-3">
        <Field label="Net Worth" prefix="$" value={profile.net_worth ?? 0} onChange={(v) => set("net_worth", v)} step={10000} />
        <Field label="Home Value" prefix="$" value={profile.home_value ?? 0} onChange={(v) => set("home_value", v)} step={10000} />
      </div>
    </div>
  );
}
