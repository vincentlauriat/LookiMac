# Looki Open API — reference notes

- `looki-memory-SKILL.md`: verbatim copy of Looki's official agent skill (https://web.looki.ai/agent/looki-memory/SKILL.md, fetched 2026-09-05). Authoritative list of the 12 endpoints, parameters and models.
- Live checks on 2026-09-05 (Vincent's account): `/for_you/items` answers HTTP 400 code 105 "deprecated, use /journals"; `/realtime/latest-event` works (proactive mode on); a moment exposes up to ~15 clips via `/moments/{id}/files` (208 files across 13 moments that day); `/journals` pages with `cursor_date` + `max_days`, not `cursor_id`.
- Signed `temporary_url` values expire after 1 hour. `media_type` may be `AUDIO`.
