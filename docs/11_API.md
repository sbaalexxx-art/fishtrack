# AIFishMap API

---

# Purpose

This document defines the official API strategy of AIFishMap.

Flutter communicates with a single backend service.

The backend is responsible for aggregating, validating and transforming data from multiple providers.

---

# API Principles

Every API must be:

- Secure
- Fast
- Versioned
- Documented
- Consistent

Every endpoint should have one responsibility.

---

# Architecture

```
Flutter

↓

Backend API

↓

Supabase

↓

External Providers
```

Flutter must never communicate directly with external providers.

---

# API Versioning

Current Version

v1

Future versions

v2

v3

Breaking changes require a new API version.

---

# Authentication

Authentication uses JWT.

Protected endpoints require a valid authenticated user.

Public endpoints remain accessible without login where appropriate.

---

# Response Format

Every response should follow a consistent structure.

Success

```
{
  "success": true,
  "data": { }
}
```

Error

```
{
  "success": false,
  "message": "Description"
}
```

---

# Planned Endpoints

## Stations

Retrieve fishing stations.

Retrieve station details.

Retrieve nearby stations.

---

## Water Levels

Retrieve latest level.

Retrieve historical data.

Retrieve trend.

---

## Weather

Current weather.

Forecast.

Wind.

Pressure.

Humidity.

Moon phase.

---

## Reports

Create report.

Update report.

Delete report.

Retrieve nearby reports.

---

## Catches

Create catch.

Update catch.

Delete catch.

Retrieve catches.

---

## Profile

Retrieve profile.

Update profile.

Avatar.

Preferences.

---

## Favorites

Add favorite.

Remove favorite.

Retrieve favorites.

---

## AI

Retrieve Fishing Score.

Retrieve AI Insights.

Retrieve recommendations.

---

# Performance

Pagination should be used whenever large datasets are returned.

Responses should contain only required fields.

Compression should be enabled.

---

# Security

HTTPS only.

JWT authentication.

Input validation.

Rate limiting.

Logging.

---

# Error Handling

Every endpoint should return meaningful errors.

Never expose internal server information.

---

# Documentation

Every endpoint must include:

Purpose.

Parameters.

Authentication.

Example request.

Example response.

Possible errors.

---

# Official Rule

No API endpoint is implemented before being documented.

---

# End of API