# AIFishMap Architecture

---

# Purpose

This document defines the official software architecture of AIFishMap.

Every implementation must follow this architecture.

No feature should bypass it without updating the Project Bible.

---

# Architecture Philosophy

AIFishMap is built around four principles:

- Modular
- Scalable
- Maintainable
- Reusable

The application should remain easy to extend as new countries, rivers and services are added.

---

# Technology Stack

## Frontend

Flutter

---

## Backend

Supabase

---

## Database

PostgreSQL (Supabase)

---

## Maps

OpenStreetMap

---

## State Management

Flutter recommended architecture.

Business logic must remain separated from UI.

---

# Project Structure

```
lib/

core/
features/
shared/
services/
widgets/
```

---

# Core

The Core layer contains everything shared by the entire application.

Examples:

- Theme
- Colors
- Typography
- Dimensions
- Constants
- Utilities
- Helpers

Core must never contain feature-specific logic.

---

# Features

Every major functionality belongs to its own module.

Examples:

```
features/

dashboard/
map/
weather/
community/
profile/
settings/
auth/
```

Each feature should contain:

```
presentation/

domain/

data/
```

---

# Shared

Contains reusable components used by multiple features.

Examples:

- Buttons
- Cards
- Dialogs
- Inputs
- Loading widgets

---

# Services

Responsible for communication with external systems.

Examples:

- Supabase
- Weather
- Backend
- Location
- Permissions

---

# Design Rules

UI must never contain business logic.

Business logic must never contain UI.

Database access must never happen directly inside widgets.

---

# Data Flow

```
UI

↓

Presentation

↓

Domain

↓

Data

↓

Supabase / Backend

↓

Response

↓

UI
```

---

# Responsiveness

The application must work correctly on:

- Small phones
- Large phones
- Tablets

Layouts must adapt instead of relying on fixed sizes.

---

# Performance

Avoid unnecessary rebuilds.

Reuse widgets whenever possible.

Lazy loading should be preferred for large datasets.

---

# Scalability

The architecture must support future expansion across Europe without major refactoring.

Every new country should require configuration rather than architectural changes.

---

# Official Rule

Architecture decisions are documented before implementation.

Implementation follows architecture.

Never the opposite.

---

# End of Architecture