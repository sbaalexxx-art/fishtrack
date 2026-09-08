import {
  fuseScalarForecast,
  type ForecastCandidate,
} from "../../_shared/pr18_weather_fusion.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const now = "2026-09-08T15:00:00Z";

Deno.test("correlated providers cannot inflate confidence", () => {
  const candidates: ForecastCandidate[] = [
    {
      providerId: "met-no",
      familyId: "ecmwf",
      value: 21,
      issuedAt: "2026-09-08T14:30:00Z",
      validAt: "2026-09-09T15:00:00Z",
    },
    {
      providerId: "ecmwf-ifs",
      familyId: "ecmwf",
      value: 21.2,
      issuedAt: "2026-09-08T14:00:00Z",
      validAt: "2026-09-09T15:00:00Z",
    },
    {
      providerId: "dwd-icon-eu",
      familyId: "dwd",
      value: 20.8,
      issuedAt: "2026-09-08T14:00:00Z",
      validAt: "2026-09-09T15:00:00Z",
    },
  ];

  const result = fuseScalarForecast(candidates, {
    variable: "temperature_c",
    now,
  });

  assert(
    result.independentFamilyCount === 2,
    "MET Norway and ECMWF must count as one independent model family",
  );
  assert(
    result.confidence <= 0.84 + 1e-9,
    "two-family confidence must remain capped",
  );
  assert(
    Math.abs(result.value - 21) <= 0.25,
    "consensus temperature must remain near the robust center",
  );
});

Deno.test("gross outlier is heavily downweighted", () => {
  const candidates: ForecastCandidate[] = [
    { providerId: "ecmwf", familyId: "ecmwf", value: 12, issuedAt: "2026-09-08T14:00:00Z", validAt: "2026-09-09T15:00:00Z" },
    { providerId: "dwd", familyId: "dwd", value: 13, issuedAt: "2026-09-08T14:00:00Z", validAt: "2026-09-09T15:00:00Z" },
    { providerId: "noaa", familyId: "noaa", value: 12.5, issuedAt: "2026-09-08T14:00:00Z", validAt: "2026-09-09T15:00:00Z" },
    { providerId: "broken", familyId: "other", value: 48, issuedAt: "2026-09-08T14:00:00Z", validAt: "2026-09-09T15:00:00Z" },
  ];

  const result = fuseScalarForecast(candidates, {
    variable: "wind_kmh",
    now,
  });
  const broken = result.diagnostics.find(
    (candidate) => candidate.providerId === "broken",
  );

  assert(result.value < 20, "outlier must not dominate fused wind");
  assert(
    !!broken && broken.outlierFactor < 0.5,
    "gross outlier must receive a strong penalty",
  );
});

Deno.test("fresh forecast outweighs stale forecast", () => {
  const candidates: ForecastCandidate[] = [
    {
      providerId: "stale",
      familyId: "a",
      value: 1015,
      issuedAt: "2026-09-07T10:00:00Z",
      validAt: "2026-09-09T15:00:00Z",
    },
    {
      providerId: "fresh",
      familyId: "b",
      value: 1016,
      issuedAt: "2026-09-08T14:45:00Z",
      validAt: "2026-09-09T15:00:00Z",
    },
  ];

  const result = fuseScalarForecast(candidates, {
    variable: "pressure_hpa",
    now,
  });
  const fresh = result.diagnostics.find(
    (candidate) => candidate.providerId === "fresh",
  )!;
  const stale = result.diagnostics.find(
    (candidate) => candidate.providerId === "stale",
  )!;

  assert(
    fresh.normalizedWeight > stale.normalizedWeight,
    "fresh forecast must outweigh stale forecast",
  );
});

Deno.test("one model family cannot report high confidence", () => {
  const candidates: ForecastCandidate[] = [
    { providerId: "a", familyId: "same", value: 18, issuedAt: "2026-09-08T14:00:00Z", validAt: "2026-09-09T15:00:00Z" },
    { providerId: "b", familyId: "same", value: 18.2, issuedAt: "2026-09-08T14:00:00Z", validAt: "2026-09-09T15:00:00Z" },
    { providerId: "c", familyId: "same", value: 17.9, issuedAt: "2026-09-08T14:00:00Z", validAt: "2026-09-09T15:00:00Z" },
  ];

  const result = fuseScalarForecast(candidates, {
    variable: "temperature_c",
    now,
  });

  assert(result.independentFamilyCount === 1, "family count must be one");
  assert(
    result.confidence <= 0.72 + 1e-9,
    "single family must never report high confidence",
  );
});
