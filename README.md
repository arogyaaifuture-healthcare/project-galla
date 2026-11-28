# Galla
Restaurant billing: billing, KOT, UPI QR, offline mode, WhatsApp bills, inventory, GST registers, reports, loyalty.
- `docs/TECHNICAL_PLAN.md` — the full plan (v1.4); build phase by phase (Section 16, Section 30.10)
- `backend/` — Spring Boot API + Flyway migrations V001–V017 (**compiled and tested only by CI; not yet run by the author**)
- `frontend/` — React + TypeScript PWA (3D only on login/landing, with a low-power fallback)
- `tools/` — database test suites and Python/JS reference specs
- Run all: `docker compose up --build`
## Status
Phase 1 (in progress): register, login (role selector, lockout), tenant-scoped menu API, login + menu screens. CI runs 12 backend tests, 4 frontend tests, 848 database cases (V001-V017), 230 reference tests.
