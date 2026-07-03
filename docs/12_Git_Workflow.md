# AIFishMap Git Workflow

---

# Purpose

This document defines the official development workflow of AIFishMap.

Every feature, bug fix and improvement must follow this workflow.

The objective is to maintain a stable, traceable and professional development process.

---

# Official Development Workflow

Every task follows exactly this sequence:

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

Documentation Update

↓

Git Commit

↓

Next Feature

This workflow must not be skipped.

---

# Planning

Before writing code:

- Define the objective.
- Decide the implementation approach.
- Check the Project Bible.
- Check the Roadmap.
- Confirm that the implementation belongs to the current sprint.

---

# Implementation

Development rules:

- Complete files only.
- One file at a time.
- No partial implementations.
- No unfinished features.
- Reusable widgets whenever possible.
- Respect the approved architecture.

---

# Compilation

Every file must compile successfully before moving to the next one.

Compilation errors are resolved immediately.

No new feature starts while the project is broken.

---

# Testing

Before committing:

- Verify the feature works correctly.
- Check responsiveness.
- Check visual consistency.
- Verify no regressions were introduced.

---

# Documentation

After completing a feature:

Update:

- Project Bible
- Roadmap (if required)
- Decision Log (if required)
- Changelog

Documentation must always reflect the current state of the project.

---

# Git Commits

Every completed feature receives its own commit.

Avoid combining unrelated changes.

---

# Commit Message Format

Examples:

feat(home): redesign premium dashboard

feat(map): add OpenStreetMap markers

feat(weather): integrate OpenWeather API

fix(home): resolve dashboard overflow

refactor(core): improve reusable widgets

docs(project): update Project Bible

---

# Branch Strategy

Current development:

main

Future:

main

develop

feature/*

release/*

hotfix/*

---

# Sprint Completion

A sprint is complete only when:

- Feature implementation is finished.
- The application compiles successfully.
- Testing is completed.
- Documentation is updated.
- Git commit has been created.

---

# Official Rule

Never sacrifice architecture or code quality to save a small amount of time.

A stable foundation is more valuable than rapid but fragile development.

---

# End of Git Workflow