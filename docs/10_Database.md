# AIFishMap Database

---

# Purpose

This document defines the official database architecture of AIFishMap.

The database is the central source of application data.

All schema changes must be documented before implementation.

---

# Database Platform

Provider

Supabase

Database Engine

PostgreSQL

---

# Design Principles

The database must be:

- Normalised
- Scalable
- Secure
- Performant
- Easy to maintain

Every table should have a single responsibility.

---

# Core Tables

## profiles

Stores user information.

Examples:

- id
- username
- avatar
- reputation
- country
- language

---

## stations

Stores fishing stations.

Examples:

- id
- name
- river
- country
- latitude
- longitude

---

## water_levels

Stores water level measurements.

Examples:

- station_id
- value
- timestamp
- trend

---

## weather

Stores weather information.

Examples:

- station_id
- temperature
- wind
- pressure
- humidity
- moon_phase

---

## catches

Stores fishing catches.

Examples:

- user_id
- species
- weight
- length
- bait
- station_id
- image
- timestamp

---

## reports

Stores community reports.

Examples:

- hazards
- obstacles
- navigation issues
- fishing information

---

## favorites

Stores user favourite locations.

---

## notifications

Stores application notifications.

---

## ai_results

Stores AI generated insights.

Examples:

- Fishing Score
- Prediction
- Recommendation
- Confidence

---

# Relationships

profiles

↓

catches

↓

stations

↓

water_levels

↓

weather

All relations should use foreign keys.

---

# Primary Keys

Every table uses:

UUID

Generated automatically.

---

# Indexing

Indexes should be created for:

- station_id
- timestamp
- user_id
- location queries

---

# Security

Row Level Security must remain enabled.

Private user data must never be publicly accessible.

---

# Backups

Automatic Supabase backups remain enabled.

Database exports should be created before major migrations.

---

# Migration Rules

Every migration must:

- be versioned
- be documented
- be reversible

---

# Future Tables

Examples:

- achievements
- badges
- subscriptions
- competitions
- AI history
- analytics

---

# Official Rule

Database design follows the Project Bible.

Flutter adapts to the database.

The database should not be redesigned to fit temporary UI requirements.

---

# End of Database