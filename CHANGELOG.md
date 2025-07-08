# Changelog

All notable changes to CutClip will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-07-08

### Added
- 24-hour transparent video caching system to avoid re-downloading videos
- Video metadata caching for faster video information retrieval
- Architecture-aware FFmpeg downloads (automatically selects ARM64 for Apple Silicon or Intel builds)
- Auto-update functionality via Sparkle framework
- New Clean UI/UX
- Restore license
- Popular aspect ratios cropping
- Improvements on Codebase and architecture
- Unit and integration tests

### Changed
- Time input fields now only accept numeric input with automatic HH:MM:SS formatting
- Improved error messages throughout the app for better user feedback
- Video cache service now uses singleton pattern to ensure proper cache sharing across services
- Increased default free credits from 3 to 5 for new users
- Clean architecture with separated services

## [1.0.0] - 2025-06-28

### Added
- Initial release of CutClip
- YouTube video downloading and clipping functionality
- Quality selection support (720p, 1080p, 1440p, 2160p)
- Freemium model with 3 free credits

For more information about CutClip, visit [cutclip](https://dub.sh/cutclip)