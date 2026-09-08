export type WeatherProviderRole =
  | "point_forecast"
  | "nwp_forecast"
  | "ensemble"
  | "observation"
  | "radar"
  | "lightning";

export type LegalStatus = "verified_open_commercial" | "pending_review";

export interface WeatherProviderDefinition {
  id: string;
  role: WeatherProviderRole;
  correlationFamily: string;
  legalStatus: LegalStatus;
  productionEnabled: boolean;
  shadowEnabled: boolean;
  notes: string;
}

export const PR18_WEATHER_PROVIDERS: WeatherProviderDefinition[] = [
  {
    id: "met_norway_locationforecast_v2",
    role: "point_forecast",
    correlationFamily: "ecmwf_center",
    legalStatus: "verified_open_commercial",
    productionEnabled: true,
    shadowEnabled: true,
    notes:
      "Current PR18 production source. For Romania, treat as correlated with ECMWF-derived guidance when computing independence/confidence.",
  },
  {
    id: "dwd_icon_eu",
    role: "nwp_forecast",
    correlationFamily: "dwd_center",
    legalStatus: "verified_open_commercial",
    productionEnabled: false,
    shadowEnabled: false,
    notes:
      "Candidate for Romania 0-120h. Enable shadow only after adapter, provenance and operational validation.",
  },
  {
    id: "ecmwf_ifs_open",
    role: "nwp_forecast",
    correlationFamily: "ecmwf_center",
    legalStatus: "verified_open_commercial",
    productionEnabled: false,
    shadowEnabled: false,
    notes:
      "Candidate medium-range source. Same center-family cap prevents double counting with MET Norway.",
  },
  {
    id: "ecmwf_aifs_open",
    role: "nwp_forecast",
    correlationFamily: "ecmwf_center",
    legalStatus: "verified_open_commercial",
    productionEnabled: false,
    shadowEnabled: false,
    notes:
      "AI forecast candidate. Keep within ECMWF center-family confidence cap until empirical error correlation is measured.",
  },
  {
    id: "noaa_gfs",
    role: "nwp_forecast",
    correlationFamily: "noaa_center",
    legalStatus: "verified_open_commercial",
    productionEnabled: false,
    shadowEnabled: false,
    notes:
      "Independent global fallback candidate.",
  },
  {
    id: "noaa_gefs",
    role: "ensemble",
    correlationFamily: "noaa_center",
    legalStatus: "verified_open_commercial",
    productionEnabled: false,
    shadowEnabled: false,
    notes:
      "Probabilistic uncertainty candidate. Do not count deterministic GFS and GEFS as fully independent.",
  },
  {
    id: "anm_wrf_romania",
    role: "nwp_forecast",
    correlationFamily: "anm_wrf",
    legalStatus: "pending_review",
    productionEnabled: false,
    shadowEnabled: false,
    notes:
      "Romania-local candidate. Legal metadata, boundary-condition dependency and operational ingestion must be verified before shadow activation.",
  },
  {
    id: "anm_radar_romania",
    role: "radar",
    correlationFamily: "anm_observation",
    legalStatus: "pending_review",
    productionEnabled: false,
    shadowEnabled: false,
    notes:
      "Observation/nowcast evidence only; never treated as another NWP vote.",
  },
  {
    id: "eumetsat_mtg_lightning",
    role: "lightning",
    correlationFamily: "eumetsat_observation",
    legalStatus: "verified_open_commercial",
    productionEnabled: false,
    shadowEnabled: false,
    notes:
      "Safety/convective evidence channel; not a scalar forecast provider.",
  },
];
