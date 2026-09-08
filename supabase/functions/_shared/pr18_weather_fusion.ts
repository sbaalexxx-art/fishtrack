export type WeatherVariable =
  | "temperature_c"
  | "pressure_hpa"
  | "wind_kmh"
  | "gust_kmh"
  | "precipitation_mm"
  | "precipitation_probability_pct"
  | "humidity_pct";

export interface ProviderSkill {
  providerId: string;
  familyId: string;
  sampleCount: number;
  mae?: number | null;
  rmse?: number | null;
  brier?: number | null;
  availability?: number | null;
}

export interface ForecastCandidate {
  providerId: string;
  familyId: string;
  value: number;
  issuedAt: string;
  validAt: string;
  baseWeight?: number;
  skill?: ProviderSkill | null;
}

export interface FusionOptions {
  variable: WeatherVariable;
  now: string;
  familyWeightCap?: number;
  outlierMadMultiplier?: number;
  minSkillSamples?: number;
  singleFamilyConfidenceCap?: number;
  twoFamilyConfidenceCap?: number;
  maxConfidence?: number;
}

export interface WeightedCandidate extends ForecastCandidate {
  rawWeight: number;
  normalizedWeight: number;
  freshnessFactor: number;
  skillFactor: number;
  outlierFactor: number;
}

export interface FusionResult {
  value: number;
  confidence: number;
  spread: number;
  effectiveProviderCount: number;
  independentFamilyCount: number;
  familyWeights: Record<string, number>;
  diagnostics: WeightedCandidate[];
}

const EPS = 1e-9;

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function parseInstant(value: string): number {
  const time = Date.parse(value);
  if (!Number.isFinite(time)) throw new Error("invalid timestamp: " + value);
  return time;
}

function median(values: number[]): number {
  if (!values.length) throw new Error("median requires values");
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

function mad(values: number[], center: number): number {
  return values.length
    ? median(values.map((value) => Math.abs(value - center)))
    : 0;
}

function variableScale(variable: WeatherVariable): number {
  switch (variable) {
    case "temperature_c": return 2;
    case "pressure_hpa": return 3;
    case "wind_kmh": return 8;
    case "gust_kmh": return 12;
    case "precipitation_mm": return 2.5;
    case "precipitation_probability_pct": return 18;
    case "humidity_pct": return 10;
  }
}

function errorScale(variable: WeatherVariable): number {
  switch (variable) {
    case "temperature_c": return 2.5;
    case "pressure_hpa": return 4;
    case "wind_kmh": return 10;
    case "gust_kmh": return 15;
    case "precipitation_mm": return 3;
    case "precipitation_probability_pct": return 20;
    case "humidity_pct": return 12;
  }
}

function skillFactor(
  variable: WeatherVariable,
  skill: ProviderSkill | null | undefined,
  minSamples: number,
): number {
  if (!skill || skill.sampleCount <= 0) return 0.75;

  const evidence = clamp(skill.sampleCount / Math.max(1, minSamples), 0, 1);
  let performance = 0.75;

  if (
    variable === "precipitation_probability_pct" &&
    skill.brier != null &&
    Number.isFinite(skill.brier)
  ) {
    performance = clamp(1 - skill.brier / 0.25, 0.2, 1.15);
  } else {
    const error = skill.mae ?? skill.rmse;
    if (error != null && Number.isFinite(error)) {
      performance = clamp(
        Math.exp(-Math.max(0, error) / errorScale(variable)),
        0.2,
        1.15,
      );
    }
  }

  const availability = skill.availability == null
    ? 1
    : clamp(skill.availability, 0.5, 1);
  const learned = 0.55 + 0.45 * performance;
  return clamp(
    (0.75 * (1 - evidence) + learned * evidence) * availability,
    0.2,
    1.15,
  );
}

function freshnessFactor(nowMs: number, issuedMs: number): number {
  const ageHours = Math.max(0, (nowMs - issuedMs) / 3_600_000);
  if (ageHours <= 1) return 1;
  if (ageHours >= 18) return 0.45;
  return clamp(Math.exp(-(ageHours - 1) / 24), 0.45, 1);
}

function capFamilies(
  items: WeightedCandidate[],
  familyCap: number,
): WeightedCandidate[] {
  const totals = new Map<string, number>();
  for (const item of items) {
    totals.set(item.familyId, (totals.get(item.familyId) ?? 0) + item.rawWeight);
  }

  const capped = items.map((item) => ({ ...item }));
  for (const item of capped) {
    const total = totals.get(item.familyId) ?? item.rawWeight;
    if (total > familyCap + EPS) item.rawWeight *= familyCap / total;
  }

  const total = capped.reduce((sum, item) => sum + item.rawWeight, 0);
  if (total <= EPS) throw new Error("all candidate weights are zero");
  return capped.map((item) => ({
    ...item,
    normalizedWeight: item.rawWeight / total,
  }));
}

export function fuseScalarForecast(
  candidates: ForecastCandidate[],
  options: FusionOptions,
): FusionResult {
  const valid = candidates.filter((candidate) => Number.isFinite(candidate.value));
  if (!valid.length) throw new Error("no valid forecast candidates");

  const nowMs = parseInstant(options.now);
  const center = median(valid.map((candidate) => candidate.value));
  const dispersion = mad(valid.map((candidate) => candidate.value), center);
  const robustScale = Math.max(
    variableScale(options.variable) * 0.25,
    dispersion * 1.4826,
  );
  const outlierMultiplier = options.outlierMadMultiplier ?? 3.5;
  const minSkillSamples = options.minSkillSamples ?? 60;

  let weighted: WeightedCandidate[] = valid.map((candidate) => {
    const distance = Math.abs(candidate.value - center);
    const boundary = Math.max(
      variableScale(options.variable),
      robustScale * outlierMultiplier,
    );
    const outlierFactor = distance <= boundary
      ? 1
      : clamp(boundary / Math.max(distance, EPS), 0.1, 1);
    const freshness = freshnessFactor(nowMs, parseInstant(candidate.issuedAt));
    const skill = skillFactor(options.variable, candidate.skill, minSkillSamples);
    const base = clamp(candidate.baseWeight ?? 1, 0.05, 4);

    return {
      ...candidate,
      freshnessFactor: freshness,
      skillFactor: skill,
      outlierFactor,
      rawWeight: base * freshness * skill * outlierFactor,
      normalizedWeight: 0,
    };
  });

  weighted = capFamilies(weighted, options.familyWeightCap ?? 1);

  const value = weighted.reduce(
    (sum, candidate) => sum + candidate.value * candidate.normalizedWeight,
    0,
  );
  const variance = weighted.reduce(
    (sum, candidate) =>
      sum + candidate.normalizedWeight * (candidate.value - value) ** 2,
    0,
  );
  const spread = Math.sqrt(Math.max(0, variance));
  const weightSquares = weighted.reduce(
    (sum, candidate) => sum + candidate.normalizedWeight ** 2,
    0,
  );
  const effectiveProviderCount = 1 / Math.max(EPS, weightSquares);

  const familyWeights: Record<string, number> = {};
  for (const candidate of weighted) {
    familyWeights[candidate.familyId] =
      (familyWeights[candidate.familyId] ?? 0) + candidate.normalizedWeight;
  }
  const independentFamilyCount = Object.values(familyWeights)
    .filter((weight) => weight >= 0.08)
    .length;

  const agreement = clamp(
    Math.exp(-spread / Math.max(variableScale(options.variable), EPS)),
    0,
    1,
  );
  const diversity = clamp((effectiveProviderCount - 1) / 3, 0, 1);
  const skillConfidence = clamp(
    weighted.reduce(
      (sum, candidate) =>
        sum + candidate.normalizedWeight * candidate.skillFactor,
      0,
    ) / 1.05,
    0,
    1,
  );
  const freshnessConfidence = clamp(
    weighted.reduce(
      (sum, candidate) =>
        sum + candidate.normalizedWeight * candidate.freshnessFactor,
      0,
    ),
    0,
    1,
  );

  let confidence =
    0.20 +
    0.36 * agreement +
    0.18 * diversity +
    0.16 * skillConfidence +
    0.10 * freshnessConfidence;

  if (independentFamilyCount <= 1) {
    confidence = Math.min(
      confidence,
      options.singleFamilyConfidenceCap ?? 0.72,
    );
  } else if (independentFamilyCount === 2) {
    confidence = Math.min(
      confidence,
      options.twoFamilyConfidenceCap ?? 0.84,
    );
  }

  confidence = clamp(confidence, 0.05, options.maxConfidence ?? 0.95);

  return {
    value,
    confidence,
    spread,
    effectiveProviderCount,
    independentFamilyCount,
    familyWeights,
    diagnostics: weighted.sort(
      (a, b) => b.normalizedWeight - a.normalizedWeight,
    ),
  };
}
