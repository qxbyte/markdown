# Changelog

## [Unreleased]
- sync scroll position between editor and preview (2026-05-10)

## [1.4.0] - 2026-05-10
### Added
- Find and replace functionality
- Line number display in editor

## [1.3.0] - 2026-03-15
### Added
- Outline panel with popover support

## [1.2.0] - 2026-01-20
### Added
- Dark mode support via CSS variables

## [1.0.0] - 2025-12-01
### Added
- Initial release

- extract file open/save into FileCommands (2026-05-10)
- consolidate color tokens into theme file (2026-05-10)
- simplify document navigation state machine (2026-05-10)
- bump Swift package dependencies (2026-05-10)
- remove legacy build phase from package script (2026-05-10)
- delete stale icon assets from bundle (2026-05-10)
- unit tests for CommonMark edge cases (2026-05-10)
- integration test for find-replace round trip (2026-05-10)
- snapshot tests for outline panel rendering (2026-05-10)
- end-to-end export flow integration test (2026-05-10)
- update README feature list for v1.4 (2026-05-10)
- add keyboard shortcuts reference table (2026-05-10)
- add CONTRIBUTING guide for external contributors (2026-05-10)
- expand tech-stack table with version numbers (2026-05-10)
- export document to PDF via print subsystem (2026-05-10)
- show word and character count in status bar (2026-05-10)
- configurable auto-save interval in preferences (2026-05-10)
- recent files submenu in File menu (2026-05-10)
- restore cursor position after undo (2026-05-10)
- refresh outline panel on heading change (2026-05-10)
- preserve highlight across find-replace operations (2026-05-10)
- align line numbers with wrapped text (2026-05-10)
- code block background in dark mode (2026-05-10)
- table overflow clipped in narrow window (2026-05-10)
- resolve relative image paths correctly (2026-05-10)
- default save-as path to document directory (2026-05-10)
- restore window frame on relaunch (2026-05-10)
- debounce preview re-render on keystroke (2026-05-10)
- cache syntax highlight tokens per line (2026-05-10)