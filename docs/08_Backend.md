# AIFishMap Backend

---

# Purpose

This document defines the backend architecture of AIFishMap.

The backend acts as the intelligence layer between external data providers and the mobile application.

Flutter should never communicate directly with multiple external providers.

The backend centralizes, validates and distributes data.

---

# Philosophy

AIFishMap owns its data pipeline.

External services provide information.

The backend transforms that information into a unified format.

Flutter communicates with one backend.

Not with multiple providers.

---

# Responsibilities

The backend is responsible for:

- Collecting official data
- Validating information
- Normalising formats
- Caching responses
- Reducing API calls
- Scheduling updates
- Delivering clean data to Supabase

---

# External Data Providers

Current planned providers:

## DanubeHIS

Water level information

Navigation stations

River measurements

---

## AFDJ

Romanian Danube navigation data.

Official station information.

Hydrological data.

---

## INHGA

Romanian hydrological institute.

River monitoring.

Official measurements.

---

## OpenWeather

Weather forecast

Current weather

Wind

Pressure

Humidity

Moon phase

---

# Future Providers

The architecture must allow adding new providers without changing Flutter.

Examples:

- European weather services
- Lake authorities
- Fishing associations
- Government open-data platforms

---

# Backend Responsibilities

The backend must:

Validate incoming data.

Merge duplicate information.

Resolve conflicts.

Store historical values.

Generate statistics.

Calculate trends.

Prepare AI input.

---

# Data Flow

Official Provider

↓

Backend

↓

Validation

↓

Transformation

↓

Supabase

↓

Flutter

---

# Caching

The backend should cache external responses whenever possible.

Benefits:

- Faster application
- Lower API usage
- Better reliability

---

# Scheduled Jobs

The backend executes scheduled tasks.

Examples:

Update water levels.

Update weather.

Refresh station data.

Generate daily statistics.

Run AI calculations.

---

# Notifications

The backend decides when notifications should be sent.

Examples:

Rapid water level changes.

Important community reports.

Weather alerts.

Fishing alerts.

---

# AI Preparation

Artificial Intelligence does not query external providers directly.

The backend prepares structured datasets for AI analysis.

---

# Scalability

The backend must support:

New countries.

New rivers.

New lakes.

New languages.

Without architectural changes.

---

# Security

Flutter never accesses provider credentials.

Only the backend communicates with external services.

---

# Official Rule

Every new provider must first be documented here before implementation.

---

# End of Backend