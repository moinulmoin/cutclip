# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Context

For comprehensive project information, see:
- **[PROJECT_CONTEXT.md](agent-docs/PROJECT_CONTEXT.md)** - Complete project overview, architecture, and technical details
- **[progress.md](agent-docs/progress.md)** - Development history and recent changes

## Quick Reference

CutClip is a macOS SwiftUI application for clipping YouTube videos with a freemium model (3 free credits, then license required).

## Documentation

- **[Build Commands](agent-docs/BUILD_COMMANDS.md)** - Development, release, and troubleshooting commands
- **[Architecture](agent-docs/ARCHITECTURE.md)** - Service architecture and design patterns
- **[API Reference](agent-docs/API_REFERENCE.md)** - Backend API endpoints and integration

## Key Features

- **Video Processing**: Download and clip YouTube videos with quality selection (720p-2160p)
- **Aspect Ratios**: Original, 9:16 (vertical), 1:1 (square), 4:3 cropping
- **Video Cache**: 24-hour transparent caching to avoid re-downloads
- **License System**: Device-bound licensing with Stripe integration

## Development Guidelines

- Always use Swift 6 and latest SwiftUI/macOS 14+ APIs
- Follow SOLID principles and clean architecture patterns
- Prefer @MainActor for UI-related code
- Write self-documenting code with minimal comments
- When in doubt, check git history for context

## Important Notes

- Binary tools (yt-dlp, FFmpeg) are auto-downloaded on first launch
- Licenses are tied to device hardware UUID (SHA256 hashed)
- All external processes run in restricted sandboxed environment
- Error messages should be user-friendly and actionable