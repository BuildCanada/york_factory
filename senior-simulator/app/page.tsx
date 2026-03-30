"use client";

import { useState, useCallback, useEffect } from "react";
import type { Profile, PolicyParams, BenefitSummary, MarginalRatePoint, ProjectionPoint, Persona } from "@/lib/types";
import * as api from "@/lib/api";
import ProfileForm from "@/components/ProfileForm";
import PolicyLevers from "@/components/PolicyLevers";
import BenefitBreakdown from "@/components/BenefitBreakdown";
import EmtrChart from "@/components/EmtrChart";
import PersonaCards from "@/components/PersonaCards";
import ComparisonPanel from "@/components/ComparisonPanel";
import ProjectionChart from "@/components/ProjectionChart";

type Tab = "simulator" | "personas" | "projections";

const DEFAULT_PERSONAS: Persona[] = [
  {
    id: "tfsa_maximizer",
    name: "TFSA Maximizer",
    description: "Millionaire living off tax-free TFSA withdrawals. Zero taxable income, collects full OAS + GIS.",
    gaming_explanation: "TFSA withdrawals are invisible to OAS/GIS means tests. This person has $1.2M in assets but qualifies for maximum low-income supplements.",
    profile: { age: 70, marital_status: "single", years_in_canada: 40, employment_income: 0, pension_income: 0, investment_income: 0, rrif_income: 0, tfsa_withdrawals: 85000, corporate_income: 0, net_worth: 1200000, home_value: 400000 },
  },
  {
    id: "corporate_holdco",
    name: "Corporate Holdco",
    description: "Business owner with $5M in a holding company. Pays no salary, takes tax-free capital dividends.",
    gaming_explanation: "Capital dividend account distributions from a CCPC are tax-free and not reported as personal income.",
    profile: { age: 68, marital_status: "single", years_in_canada: 40, employment_income: 0, pension_income: 0, investment_income: 0, rrif_income: 0, tfsa_withdrawals: 0, corporate_income: 120000, net_worth: 5000000, home_value: 800000 },
  },
  {
    id: "home_equity_senior",
    name: "Home Equity Senior",
    description: "Lives in a $2.5M home, uses HELOC for expenses. Minimal taxable income.",
    gaming_explanation: "HELOC draws aren't income. Primary residence is fully exempt. A person in a $2.5M home collects GIS designed for poverty relief.",
    profile: { age: 72, marital_status: "single", years_in_canada: 40, employment_income: 0, pension_income: 0, investment_income: 0, rrif_income: 12000, tfsa_withdrawals: 0, corporate_income: 0, net_worth: 2800000, home_value: 2500000 },
  },
  {
    id: "income_splitter",
    name: "Income Splitter Couple",
    description: "Affluent couple splitting $120K pension to stay below OAS clawback.",
    gaming_explanation: "Pension income splitting keeps both spouses below OAS recovery thresholds. Combined $120K household income pays no recovery tax.",
    profile: { age: 67, marital_status: "coupled", years_in_canada: 40, employment_income: 0, pension_income: 60000, investment_income: 10000, rrif_income: 0, tfsa_withdrawals: 0, corporate_income: 0, net_worth: 900000, home_value: 600000 },
  },
  {
    id: "median_canadian_senior",
    name: "Median Canadian Senior",
    description: "Typical senior: modest CPP, small part-time job, renter. Faces punishing clawback on every dollar earned.",
    gaming_explanation: "No gaming - no assets to shelter. $5K part-time earnings trigger GIS clawback. EMTR on additional income exceeds 70%.",
    profile: { age: 69, marital_status: "single", years_in_canada: 40, employment_income: 5000, pension_income: 9800, investment_income: 0, rrif_income: 0, tfsa_withdrawals: 0, corporate_income: 0, net_worth: 35000, home_value: 0 },
  },
  {
    id: "median_working_canadian",
    name: "Median Working Canadian (Comparison)",
    description: "35-year-old earning median income. What does a working Canadian pay to fund seniors benefits?",
    gaming_explanation: "This worker pays full income tax + CPP/EI. OAS alone costs ~$3,500 per working-age Canadian annually and rising.",
    profile: { age: 35, marital_status: "single", years_in_canada: 35, employment_income: 59300, pension_income: 0, investment_income: 0, rrif_income: 0, tfsa_withdrawals: 0, corporate_income: 0, net_worth: 50000, home_value: 0 },
  },
];

const DEFAULT_PROFILE: Partial<Profile> = {
  age: 70,
  marital_status: "single",
  years_in_canada: 40,
  employment_income: 0,
  pension_income: 10000,
  investment_income: 0,
  rrif_income: 0,
  tfsa_withdrawals: 0,
  corporate_income: 0,
  net_worth: 0,
  home_value: 0,
};

export default function Home() {
  const [tab, setTab] = useState<Tab>("simulator");
  const [profile, setProfile] = useState<Partial<Profile>>(DEFAULT_PROFILE);
  const [policy, setPolicy] = useState<PolicyParams>({});
  const [selectedPersonaId, setSelectedPersonaId] = useState<string | undefined>();

  const [currentResult, setCurrentResult] = useState<BenefitSummary | null>(null);
  const [proposedResult, setProposedResult] = useState<BenefitSummary | null>(null);
  const [currentEmtr, setCurrentEmtr] = useState<MarginalRatePoint[]>([]);
  const [proposedEmtr, setProposedEmtr] = useState<MarginalRatePoint[]>([]);
  const [difference, setDifference] = useState<{
    net_income_change: number;
    oas_change: number;
    gis_change: number;
    tax_change: number;
    total_benefits_change: number;
  } | null>(null);
  const [projections, setProjections] = useState<ProjectionPoint[]>([]);
  const [personas, setPersonas] = useState<Persona[]>(DEFAULT_PERSONAS);
  const [loading, setLoading] = useState(false);
  const [useApi, setUseApi] = useState(true);

  useEffect(() => {
    api.getPersonas(true).then((data) => {
      setPersonas(data);
    }).catch(() => {
      setUseApi(false);
    });
  }, []);

  const runSimulation = useCallback(async () => {
    if (!useApi) return;
    setLoading(true);
    try {
      const compareResult = await api.compare(profile, {}, policy);
      setCurrentResult(compareResult.current.summary);
      setProposedResult(compareResult.proposed.summary);
      setCurrentEmtr(compareResult.current_marginal_rates);
      setProposedEmtr(compareResult.proposed_marginal_rates);
      setDifference(compareResult.difference);
    } catch {
      setUseApi(false);
    } finally {
      setLoading(false);
    }
  }, [profile, policy, useApi]);

  const loadProjections = useCallback(async () => {
    if (!useApi) return;
    try {
      const result = await api.getProjections(policy);
      setProjections(result.projections);
    } catch {
      setUseApi(false);
    }
  }, [policy, useApi]);

  useEffect(() => {
    const timer = setTimeout(() => {
      runSimulation();
    }, 300);
    return () => clearTimeout(timer);
  }, [runSimulation]);

  useEffect(() => {
    if (tab === "projections") loadProjections();
  }, [tab, loadProjections]);

  const handlePersonaSelect = (personaProfile: Partial<Profile>) => {
    setProfile(personaProfile);
    const persona = personas.find((p) => JSON.stringify(p.profile) === JSON.stringify(personaProfile));
    setSelectedPersonaId(persona?.id);
    setTab("simulator");
  };

  const hasProposedChanges = Object.keys(policy).length > 0;

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <header className="border-b border-gray-800 bg-gray-900/50">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold">Senior Benefit Simulator</h1>
              <p className="text-sm text-gray-400 mt-1">
                Explore how OAS, GIS, and tax policy affect Canadian seniors
              </p>
            </div>
            <div className="text-xs text-gray-500">
              Build Canada
              {!useApi && (
                <span className="ml-2 text-amber-500">(API unavailable)</span>
              )}
            </div>
          </div>

          <div className="flex gap-1 mt-4">
            {(
              [
                ["simulator", "Simulator"],
                ["personas", "Scenarios"],
                ["projections", "Future Cost"],
              ] as const
            ).map(([id, label]) => (
              <button
                key={id}
                onClick={() => setTab(id)}
                className={`px-4 py-2 rounded-t text-sm font-medium transition-colors ${
                  tab === id
                    ? "bg-gray-800 text-amber-400 border-b-2 border-amber-400"
                    : "text-gray-400 hover:text-gray-200"
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 py-6">
        {tab === "simulator" && (
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            <div className="lg:col-span-4 space-y-6">
              <ProfileForm profile={profile} onChange={setProfile} />
              <div className="border-t border-gray-800 pt-4">
                <PolicyLevers policy={policy} onChange={setPolicy} />
              </div>
              {Object.keys(policy).length > 0 && (
                <button
                  onClick={() => setPolicy({})}
                  className="text-sm text-gray-400 hover:text-red-400 transition-colors"
                >
                  Reset to current policy
                </button>
              )}
            </div>

            <div className="lg:col-span-8 space-y-6">
              {loading && (
                <div className="text-center py-8 text-gray-400">Calculating...</div>
              )}

              {!useApi && (
                <div className="bg-amber-900/20 border border-amber-700 rounded-lg p-4">
                  <p className="text-sm text-amber-300">
                    Rails API not connected. Start the backend with{" "}
                    <code className="bg-gray-800 px-1 rounded">rails s</code> and set{" "}
                    <code className="bg-gray-800 px-1 rounded">NEXT_PUBLIC_API_URL</code>.
                  </p>
                </div>
              )}

              {currentResult && (
                <div className={`grid gap-4 ${hasProposedChanges ? "grid-cols-1 md:grid-cols-2" : "grid-cols-1 max-w-md"}`}>
                  <BenefitBreakdown
                    summary={currentResult}
                    label={hasProposedChanges ? "Current Policy" : undefined}
                  />
                  {hasProposedChanges && proposedResult && (
                    <BenefitBreakdown summary={proposedResult} label="Proposed Policy" />
                  )}
                </div>
              )}

              {hasProposedChanges && difference && <ComparisonPanel difference={difference} />}

              {currentEmtr.length > 0 && (
                <EmtrChart
                  currentData={currentEmtr}
                  proposedData={hasProposedChanges ? proposedEmtr : undefined}
                />
              )}
            </div>
          </div>
        )}

        {tab === "personas" && (
          <PersonaCards
            personas={personas}
            onSelect={handlePersonaSelect}
            selectedId={selectedPersonaId}
          />
        )}

        {tab === "projections" && (
          <div className="space-y-6">
            {projections.length > 0 ? (
              <ProjectionChart data={projections} />
            ) : useApi ? (
              <div className="text-center py-8 text-gray-400">Loading projections...</div>
            ) : (
              <div className="bg-amber-900/20 border border-amber-700 rounded-lg p-4">
                <p className="text-sm text-amber-300">
                  Connect the Rails API to see demographic cost projections.
                </p>
              </div>
            )}
          </div>
        )}
      </main>

      <footer className="border-t border-gray-800 mt-12 py-6">
        <div className="max-w-7xl mx-auto px-4 text-center text-xs text-gray-500">
          <p>
            Experimental policy simulator. Rates based on 2025 Q1 federal data.
            Not financial advice. Built by Build Canada.
          </p>
        </div>
      </footer>
    </div>
  );
}
