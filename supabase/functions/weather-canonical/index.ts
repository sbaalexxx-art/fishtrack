import tzLookup from "npm:tz-lookup@6.1.25";

const SOURCE_ID = "met_norway_locationforecast_v2";
const CANONICAL_VERSION = "weather-canonical-v1";
const CACHE_MINUTES = 30;
const STALE_HOURS = 12;
const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type",
};

type Json = Record<string, unknown>;

type CacheRow = {
  payload: Json;
  etag: string | null;
  last_modified: string | null;
  fetched_at: string;
  expires_at: string;
  stale_until: string;
};

function response(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

function number(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function roundedCoordinate(value: number): number {
  return Math.round(value * 100) / 100;
}

function cacheKey(latitude: number, longitude: number, country: string): string {
  return `${latitude.toFixed(2)}:${longitude.toFixed(2)}:${country}`;
}

function offsetFor(instant: Date, timeZone: string): string {
  const value = new Intl.DateTimeFormat("en-US", {
    timeZone,
    timeZoneName: "longOffset",
  }).formatToParts(instant).find((part) => part.type === "timeZoneName")?.value;
  if (!value || value === "GMT") return "+00:00";
  const match = /^GMT([+-]\d{2}):?(\d{2})$/.exec(value);
  return match ? `${match[1]}:${match[2]}` : "+00:00";
}

function zonedIso(instant: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(instant);
  const part = (type: string) => parts.find((item) => item.type === type)?.value ?? "00";
  return `${part("year")}-${part("month")}-${part("day")}T${part("hour")}:${part("minute")}:${part("second")}${offsetFor(instant, timeZone)}`;
}

function localDate(instant: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(instant);
}

function confidenceFor(validAt: Date, generatedAt: Date): number {
  const hours = Math.max(0, (validAt.getTime() - generatedAt.getTime()) / 3_600_000);
  return Math.max(0.45, Math.min(0.82, 0.82 - hours * 0.0016));
}

function provenanced(value: number | null, validAt: Date, generatedAt: Date): Json | null {
  if (value === null) return null;
  return {
    value,
    truth_class: "ESTIMATED",
    source: SOURCE_ID,
    observed_or_issued_at: generatedAt.toISOString(),
    confidence: confidenceFor(validAt, generatedAt),
  };
}

function conditionCode(data: Json): string | null {
  for (const period of ["next_1_hours", "next_6_hours", "next_12_hours"]) {
    const block = data[period] as Json | undefined;
    const summary = block?.summary as Json | undefined;
    if (typeof summary?.symbol_code === "string") return summary.symbol_code;
  }
  return null;
}

function precipitation(data: Json): number | null {
  for (const period of ["next_1_hours", "next_6_hours", "next_12_hours"]) {
    const block = data[period] as Json | undefined;
    const details = block?.details as Json | undefined;
    const amount = number(details?.precipitation_amount);
    if (amount !== null) return amount;
  }
  return null;
}

function parseFrame(raw: Json, generatedAt: Date, timeZone: string): Json | null {
  const validAt = new Date(String(raw.time ?? ""));
  if (!Number.isFinite(validAt.getTime())) return null;
  const data = raw.data as Json | undefined;
  const details = ((data?.instant as Json | undefined)?.details ?? {}) as Json;
  const windMs = number(details.wind_speed);
  return {
    valid_at: zonedIso(validAt, timeZone),
    temperature_c: provenanced(number(details.air_temperature), validAt, generatedAt),
    apparent_temperature_c: provenanced(number(details.apparent_air_temperature), validAt, generatedAt),
    humidity_pct: provenanced(number(details.relative_humidity), validAt, generatedAt),
    wind_kmh: provenanced(windMs === null ? null : windMs * 3.6, validAt, generatedAt),
    gust_kmh: null,
    wind_direction_deg: provenanced(number(details.wind_from_direction), validAt, generatedAt),
    pressure_hpa: provenanced(number(details.air_pressure_at_sea_level), validAt, generatedAt),
    precipitation_mm: provenanced(precipitation(data ?? {}), validAt, generatedAt),
    precipitation_probability_pct: null,
    cloud_cover_pct: provenanced(number(details.cloud_area_fraction), validAt, generatedAt),
    visibility_m: null,
    dew_point_c: provenanced(number(details.dew_point_temperature), validAt, generatedAt),
    uv_index: provenanced(number(details.ultraviolet_index_clear_sky), validAt, generatedAt),
    condition_code: conditionCode(data ?? {}),
  };
}

function dailyFrames(hourly: Json[], generatedAt: Date, timeZone: string): Json[] {
  const groups = new Map<string, Json[]>();
  for (const frame of hourly) {
    const instant = new Date(String(frame.valid_at));
    const key = localDate(instant, timeZone);
    groups.set(key, [...(groups.get(key) ?? []), frame]);
  }
  return [...groups.entries()].map(([date, frames]) => {
    const values = (field: string) => frames
      .map((frame) => number((frame[field] as Json | null)?.value))
      .filter((value): value is number => value !== null);
    const temperatures = values("temperature_c");
    const rain = values("precipitation_mm");
    const wind = values("wind_kmh");
    const condition = frames.find((frame) => frame.condition_code)?.condition_code ?? null;
    const issued = new Date(String(frames[0]?.valid_at));
    const min = temperatures.length ? Math.min(...temperatures) : null;
    const max = temperatures.length ? Math.max(...temperatures) : null;
    return {
      local_date: date,
      minimum_temperature_c: provenanced(min, issued, generatedAt),
      maximum_temperature_c: provenanced(max, issued, generatedAt),
      precipitation_probability_max_pct: null,
      precipitation_sum_mm: provenanced(rain.length ? rain.reduce((a, b) => a + b, 0) : null, issued, generatedAt),
      wind_max_kmh: provenanced(wind.length ? Math.max(...wind) : null, issued, generatedAt),
      gust_max_kmh: null,
      sunrise: null,
      sunset: null,
      condition_code: condition,
    };
  });
}

function withCache(payload: Json, state: string, ageSeconds: number): Json {
  return { ...payload, cache: { state, age_seconds: Math.max(0, ageSeconds) } };
}

async function cacheRequest(path: string, init?: RequestInit): Promise<Response> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("backend cache configuration unavailable");
  return fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
}

async function readCache(key: string): Promise<CacheRow | null> {
  const result = await cacheRequest(`weather_canonical_cache?cache_key=eq.${encodeURIComponent(key)}&select=payload,etag,last_modified,fetched_at,expires_at,stale_until&limit=1`);
  if (!result.ok) throw new Error(`cache_read_${result.status}`);
  const rows = await result.json() as CacheRow[];
  return rows[0] ?? null;
}

async function saveCache(key: string, latitude: number, longitude: number, country: string, payload: Json, provider: Response, now: Date): Promise<void> {
  const expires = new Date(now.getTime() + CACHE_MINUTES * 60_000);
  const stale = new Date(now.getTime() + STALE_HOURS * 3_600_000);
  const result = await cacheRequest("weather_canonical_cache?on_conflict=cache_key", {
    method: "POST",
    headers: { prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      cache_key: key,
      latitude_bucket: latitude,
      longitude_bucket: longitude,
      country_code: country,
      source_id: SOURCE_ID,
      canonical_version: CANONICAL_VERSION,
      payload,
      etag: provider.headers.get("etag"),
      last_modified: provider.headers.get("last-modified"),
      fetched_at: now.toISOString(),
      expires_at: expires.toISOString(),
      stale_until: stale.toISOString(),
      updated_at: now.toISOString(),
    }),
  });
  if (!result.ok) throw new Error(`cache_write_${result.status}`);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return response({ error: "method_not_allowed" }, 405);

  let body: Json;
  try {
    body = await request.json() as Json;
  } catch (_) {
    return response({ error: "invalid_json" }, 400);
  }
  const latitudeRaw = number(body.latitude);
  const longitudeRaw = number(body.longitude);
  const country = typeof body.country_code === "string" ? body.country_code.trim().toUpperCase() : "ZZ";
  if (latitudeRaw === null || longitudeRaw === null || latitudeRaw < -90 || latitudeRaw > 90 || longitudeRaw < -180 || longitudeRaw > 180 || !/^[A-Z]{2}$/.test(country)) {
    return response({ error: "invalid_weather_request" }, 400);
  }

  const latitude = roundedCoordinate(latitudeRaw);
  const longitude = roundedCoordinate(longitudeRaw);
  const key = cacheKey(latitude, longitude, country);
  const now = new Date();
  let cached: CacheRow | null = null;
  try {
    cached = await readCache(key);
    if (cached && new Date(cached.expires_at) > now) {
      const age = (now.getTime() - new Date(cached.fetched_at).getTime()) / 1000;
      return response(withCache(cached.payload, "CACHE", age));
    }
  } catch (error) {
    console.error("Weather canonical cache read failed", error);
  }

  try {
    const headers: Record<string, string> = {
      "user-agent": Deno.env.get("FLUVIAI_WEATHER_USER_AGENT") ?? "FluviAI/1.0 https://fluviai.app",
      accept: "application/json",
    };
    if (cached?.etag) headers["if-none-match"] = cached.etag;
    if (cached?.last_modified) headers["if-modified-since"] = cached.last_modified;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10_000);
    let provider: Response;
    try {
      provider = await fetch(`https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=${latitude}&lon=${longitude}`, { headers, signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
    if (provider.status === 304 && cached) {
      try {
        await saveCache(key, latitude, longitude, country, cached.payload, provider, now);
      } catch (error) {
        console.error("Weather canonical cache revalidation write failed", error);
      }
      return response(withCache(cached.payload, "CACHE", 0));
    }
    if (!provider.ok) throw new Error(`provider_${provider.status}`);
    const raw = await provider.json() as Json;
    const properties = raw.properties as Json | undefined;
    const meta = properties?.meta as Json | undefined;
    const generatedAt = new Date(String(meta?.updated_at ?? now.toISOString()));
    const series = Array.isArray(properties?.timeseries) ? properties?.timeseries as Json[] : [];
    const timeZone = tzLookup(latitudeRaw, longitudeRaw);
    const hourly = series.map((item) => parseFrame(item, generatedAt, timeZone)).filter((item): item is Json => item !== null);
    if (!hourly.length) throw new Error("provider_empty_timeseries");
    const payload: Json = {
      latitude: latitudeRaw,
      longitude: longitudeRaw,
      timezone: timeZone,
      generated_at: generatedAt.toISOString(),
      available_until: String(hourly[hourly.length - 1].valid_at),
      current: hourly[0],
      hourly,
      daily: dailyFrames(hourly, generatedAt, timeZone),
      hazards: [],
      source_ids: [SOURCE_ID],
      canonical_version: CANONICAL_VERSION,
      resolution: {
        role: "point_forecast",
        selected_source_id: SOURCE_ID,
        attempts: [{ source_id: SOURCE_ID, health: "healthy", success: true }],
      },
      attribution: "Weather forecast from MET Norway",
    };
    try {
      await saveCache(key, latitude, longitude, country, payload, provider, now);
    } catch (error) {
      console.error("Weather canonical cache write failed", error);
    }
    return response(withCache(payload, "LIVE", 0));
  } catch (error) {
    console.error("Weather canonical provider failed", error);
    if (cached && new Date(cached.stale_until) > now) {
      const age = (now.getTime() - new Date(cached.fetched_at).getTime()) / 1000;
      return response(withCache(cached.payload, "STALE_LKG", age));
    }
    return response({ error: "weather_canonical_unavailable" }, 503);
  }
});
