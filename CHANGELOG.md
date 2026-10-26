# Changelog

## [1.0.1] - 2026-10-26

### Changed

- Make the selected addon clearer with a border one physical pixel thick and
  inset by one pixel on every side, plus a persistent brighter background.
  Keep the border, icon and labels aligned when moving, scrolling or changing
  UI scale. Soften alternating rows and hover shading, and use solid dark-grey
  backgrounds for the addon list and release-notes inset panels.

### Fixed

- Keep windows created by 1.0.0 usable when a newer embedded copy loads later.
  Existing rows keep their original decoration until reload.

## [1.0.0] - 2026-10-12

### Added

- Shared update window with a persistent icon-based addon list, per-addon unread notices,
  interactive LMS highlights with featured, important, or user-requested labels,
  optional full notes, Settings pages, and consumer-owned notification storage.
- Global `/changelog` command and `ShowAll()` API to browse every consumer's latest
  registered release, including read updates and addons with popups disabled.
- Markdown-to-Lua release-note generator for bundling the current changelog.

### Requirements

- Retail 12.1.5, LibStub, and LibModernSettings 1.10.0 or newer.
- Uses LibStub MINOR 1 within the `LibChangelog-1.0` API family.
