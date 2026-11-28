# Galla
Restaurant billing: billing, KOT, UPI QR, offline mode, WhatsApp bills, inventory, GST registers, reports, loyalty.
- `docs/TECHNICAL_PLAN.md` — the full plan (v1.4); build phase by phase (Section 16, Section 30.10)
- `backend/` — Spring Boot API + Flyway migrations V001–V017 (**compiled and tested only by CI; not yet run by the author**)
- `frontend/` — React + TypeScript PWA (3D only on login/landing, with a low-power fallback)
- `tools/` — database test suites and Python/JS reference specs
- Run all: `docker compose up --build`
## Status
Phase 1 (in review, PR #2): self-signup with 30-day trial; login with role selector, lockout and refresh-cookie sessions (rotation + reuse detection); staff management with plan limits; restaurant details (GSTIN/FSSAI validated); tenant-scoped menu; audit/activity log; UPI-QR subscription payment with super-admin confirmation; platform console. CI: 38 backend tests, 14 frontend tests, 848 database cases, reference tests, and a real-browser end-to-end run with zero console errors.
