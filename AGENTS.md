# Simple Live iOS PiP — Engineering Guide

## Goal
Add native iOS Picture in Picture for live video and publish a reproducible TrollStore-compatible IPA through GitHub Actions.

## Delivery phases
1. Establish a reproducible unsigned/ad-hoc iOS IPA baseline on GitHub Actions.
2. Add native PiP plumbing and Dart method-channel state management.
3. Bridge decoded iOS video frames into `AVSampleBufferDisplayLayer`.
4. Add automatic PiP on background, restoration, error handling, and device validation.

## Constraints
- Preserve upstream Android, desktop, MPV, and MDK behavior.
- First PiP implementation may support only the default MPV/media-kit path on iOS.
- Do not claim iOS correctness without a successful macOS build artifact.
- Do not claim PiP runtime correctness without user confirmation from a TrollStore-installed build.
- Keep upstream as a separate Git remote; feature work stays on `pip/ios-trollstore`.

## Workflow
- Read relevant source and upstream plugin code before editing.
- For each behavior change: add a test or a deterministic static/build verification first.
- Commit coherent phases separately.
- Before each push run formatting, analysis/tests available on Linux, and inspect `git diff --check`.
- Never store credentials, tokens, signing identities, or device identifiers in Git.

## Repository
- Working tree: `/root/projects/dart-simple-live-pip`
- Upstream: `https://github.com/GH4NG/dart_simple_live.git`
- Origin: `git@github-simple-live-pip:gonepaul/dart-simple-live-pip.git`
- Branch: `pip/ios-trollstore`
