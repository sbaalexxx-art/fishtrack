# AIFishMap Supabase

---

# Purpose

This document defines how Supabase is used inside AIFishMap.

Every database change must be documented here before implementation.

---

# Why Supabase

Supabase is the official Backend-as-a-Service platform used by AIFishMap.

It provides:

- PostgreSQL database
- Authentication
- Row Level Security (RLS)
- Storage
- Edge Functions
- Realtime
- REST API
- SQL Editor
- Backups

---

# Official Project

Project Name

AIFishMap

Environment

Production

Database

PostgreSQL

---

# Responsibilities

Supabase stores:

- Users
- Fishing stations
- Water levels
- Community reports
- Catch reports
- User profiles
- Favorites
- Reputation
- Notifications
- AI results
- Application settings

---

# Authentication

Supported methods:

- Email / Password
- Google (future)
- Apple (future)
- Facebook (future)

Every authenticated user receives a unique UUID.

---

# Database Rules

Never modify tables directly in production without updating documentation.

Every schema change must be recorded.

---

# Row Level Security

RLS must remain enabled.

Public data:

- stations
- water levels
- weather

Private data:

- profiles
- catches
- reports
- favorites

Users may only edit their own data.

---

# Storage

Storage is used for:

- Catch photos
- Profile pictures
- Future media

Every uploaded file must have security policies.

---

# Edge Functions

Used for:

- Data synchronisation
- Scheduled jobs
- Notifications
- AI processing
- External APIs

Business logic should remain outside Flutter whenever possible.

---

# Realtime

Realtime may be used for:

- New reports
- Catch updates
- Notifications

Only when required.

---

# Security

Never expose:

- Service Role Key
- Database password

Flutter only uses:

- Project URL
- Anon Key

---

# Backup Strategy

Automatic backups should remain enabled.

Database exports should be created before major migrations.

---

# Migration Rules

Every database migration must:

- be documented
- be reversible
- be tested

---

# Future Integrations

Supabase will communicate with:

- FishTrack Backend
- DanubeHIS
- INHGA
- AFDJ
- OpenWeather

---

# Official Rule

Supabase is the source of truth for application data.

Flutter never stores permanent business data locally.

---

# End of Supabase