# AIFishMap Decision Log

---

# Purpose

This document records all major architectural, technical and product decisions made during the development of AIFishMap.

The objective is to preserve the reasoning behind important decisions and maintain a clear project history.

---

# Decision Format

Each decision must include:

- Date
- Category
- Decision
- Reason
- Impact
- Status

---

# Decision 001

Date

2026-06

Category

Branding

Decision

The project name changed from FishTrack to AIFishMap.

Reason

The FishTrack name was not available.

AIFishMap better reflects the long-term vision of combining maps, AI and fishing information.

Impact

All future branding uses AIFishMap.

Status

Approved

---

# Decision 002

Category

Architecture

Decision

Flutter uses a modular architecture.

Reason

Improves scalability and maintainability.

Status

Approved

---

# Decision 003

Category

Maps

Decision

OpenStreetMap becomes the official mapping solution.

Reason

Open source.

Flexible.

European coverage.

Status

Approved

---

# Decision 004

Category

Backend

Decision

Supabase becomes the official Backend-as-a-Service.

Reason

Authentication.

PostgreSQL.

Realtime.

Storage.

RLS.

Status

Approved

---

# Decision 005

Category

Development

Decision

Complete files only.

Reason

Avoid partial implementations and reduce integration errors.

Status

Approved

---

# Decision 006

Category

Workflow

Decision

Official workflow:

Plan

↓

Approval

↓

Implementation

↓

Compile

↓

Testing

↓

Documentation

↓

Git Commit

↓

Next Feature

Status

Approved

---

# Future Decisions

Every important decision must be recorded here before implementation.

---

# End of Decision Log