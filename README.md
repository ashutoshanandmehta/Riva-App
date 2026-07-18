# Riva

I am building Riva, a companion app for people on GLP-1 medication. We
provide the app together with the medicine, so patients can track their
weight, shots, nutrition, water, and how they feel through every week of
treatment. The product is aimed at US health seekers.

The whole product lives in this repo:

| Folder | What it is |
|---|---|
| `ios/` | The Riva iPhone app. SwiftUI, iOS 26, Liquid Glass design. |
| `backend/` | Riva Snap, the backend: the food and water photo scanner, all logging APIs, Supabase persistence, and a mobile web tester I use for tuning. |

## What works today

- **Dashboards**: Home, Medication, Tracker, and Weekly Summary, built from
  my Figma wireframes. They still render sample data while the read APIs
  are pending.
- **Snap scanner**: point the camera at a meal, a drink, or a glass of
  water and it identifies the dish, estimates the portion from the plate,
  and grounds calories and nutrients in USDA data. Accepting a scan writes
  a per-meal history row and increments the day's totals in Supabase.
- **Quick logging**: weight, shots (with injection site and comfort),
  protein, side effects with severity, and sleep quality, all persisted
  per my database schema with Row Level Security.
- **Identity**: no sign-in screen for now. Each device silently gets its
  own account, so logs are isolated per user without any friction. A real
  landing page sign-in comes later; the email code flow is already built
  and parked in the codebase.

## Working on it

- **iOS**: open `ios/Riva.xcodeproj` and run the `Riva` target. Details in
  `ios/README.md`.
- **Backend**: `cd backend`, create a venv with uv, add keys from
  `.env.example`, and run uvicorn. Details in `backend/README.md`, and the
  full system design with diagrams in `backend/ARCHITECTURE.md`.

The backend deploys on Render at https://riva-snap.onrender.com from a
mirror repo (Riva-Snap) that Render watches. I sync that mirror whenever
`backend/` changes; work happens here.
