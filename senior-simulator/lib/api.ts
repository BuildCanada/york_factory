import type {
  Profile,
  PolicyParams,
  CalculateResponse,
  MarginalRatePoint,
  CompareResponse,
  ProjectionResponse,
  Persona,
} from "./types";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000/api/v1";

async function post<T>(path: string, body: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

async function get<T>(path: string, params?: Record<string, string>): Promise<T> {
  const url = new URL(`${API_BASE}${path}`);
  if (params) Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  const res = await fetch(url.toString());
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function calculate(
  profile: Partial<Profile>,
  policy?: PolicyParams
): Promise<CalculateResponse> {
  return post("/senior_benefits/calculate", { ...profile, policy });
}

export async function getMarginalRates(
  profile: Partial<Profile>,
  policy?: PolicyParams
): Promise<{ profile: Profile; data: MarginalRatePoint[] }> {
  return post("/senior_benefits/marginal_rates", { ...profile, policy });
}

export async function compare(
  profile: Partial<Profile>,
  currentPolicy: PolicyParams,
  proposedPolicy: PolicyParams
): Promise<CompareResponse> {
  return post("/senior_benefits/compare", {
    ...profile,
    current_policy: currentPolicy,
    proposed_policy: proposedPolicy,
  });
}

export async function getProjections(policy?: PolicyParams): Promise<ProjectionResponse> {
  return post("/senior_benefits/project", { policy });
}

export async function getPersonas(withCalculations = false): Promise<Persona[]> {
  return get("/senior_benefits/personas", withCalculations ? { calculate: "true" } : undefined);
}
