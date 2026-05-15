# Ultimate Organizer

Ultimate Organizer is a native macOS app for reviewing, cleaning up, and safely applying changes to Google Chrome bookmarks. It imports Chrome's `Bookmarks` JSON file, shows the bookmark library in a review workspace, detects duplicates, can generate cleaner titles and folder suggestions with a local AI service, and lets you export or apply reviewed changes.

## What It Does

- Imports Chrome bookmark files from detected Chrome profiles or a manually selected `Bookmarks` file.
- Shows bookmark counts, root folders, duplicate bookmarks, current titles, proposed titles, current folders, destination folders, URLs, and live web previews.
- Searches review rows across bookmark fields, including titles, URLs, folders, proposed edits, status, and protection state.
- Uses local AI through Ollama, LM Studio, or another compatible local endpoint to propose cleaner bookmark titles and folder paths.
- Lets you manually edit proposed titles and destination folders.
- Lets you protect bookmarks so they keep their original title and folder.
- Deletes selected unprotected bookmarks from the local working set.
- Detects duplicate URLs and can remove duplicate rows while keeping the first matching bookmark.
- Saves local working state for a bookmark file so manual edits, protected rows, and local deletions can be restored.
- Exports the current review state as JSON.
- Applies reviewed title changes and local deletions back to Chrome's bookmark file, with optional backup creation and Chrome-running checks.

Current write behavior: applying changes writes reviewed title changes and deleted bookmarks. Proposed folder moves are preserved in JSON exports for review, but folder moves are not written back to Chrome yet.

## Requirements

- macOS 14 or newer.
- Xcode Command Line Tools or Xcode with Swift 5.9 support.
- Google Chrome, if you want automatic Chrome profile discovery.
- Optional: a local AI service for bookmark enrichment.

For Ollama, the default settings are:

```text
Endpoint: http://localhost:11434
Model: llama3.1
```

You can change the endpoint, model, context window, and timeout in the app's Settings window.

## Install From Source

Clone or open this project directory, then run:

```bash
./script/build_and_run.sh
```

That command builds the Swift package, creates `dist/UltimateOrganizer.app`, and launches it.

To build the app bundle without launching it:

```bash
./script/build_and_run.sh --build-only
```

Then move or copy this app bundle wherever you want it installed:

```text
dist/UltimateOrganizer.app
```

## Create a DMG Installer

Build a distributable DMG with:

```bash
./script/package_dmg.sh
```

The script builds the app, creates a DMG in `dist/`, includes a quick-start text file, and adds an Applications shortcut. Open the generated DMG and drag `UltimateOrganizer.app` into Applications.

## Run Tests

```bash
swift test
```

## How To Use

1. Launch Ultimate Organizer.
2. Open Settings and choose the Chrome profile you want, if the default is not correct.
3. Use Import to choose a Chrome `Bookmarks` file manually, or let the app load a detected profile on launch.
4. Open Review to inspect bookmarks, edit proposed titles, edit proposed destination folders, search across all fields, protect rows, and delete unwanted rows.
5. Open Duplicates to review duplicate URLs and remove selected duplicates or all detected duplicates.
6. Start your local AI server if you want AI enrichment.
7. Click Process to generate proposed titles and folder paths.
8. Use Export to save a JSON review copy before writing anything back to Chrome.
9. Open Storage, close Chrome, refresh Chrome status, then click Apply Changes when you are ready to write title changes and deletions back to the loaded Chrome bookmark file.

## Local AI Setup

With Ollama installed, pull and run a model such as:

```bash
ollama pull llama3.1
ollama serve
```

Keep the server running while using Process in Ultimate Organizer. If you use LM Studio or another local server, configure the endpoint and model in Settings.

## Safety Notes

- Close Chrome before applying changes. Chrome can overwrite external edits if it is running.
- Keep backup creation enabled unless you have your own backup process.
- Use Export before Apply when reviewing a large bookmark library.
- Protected bookmarks are left unchanged by AI processing, export/apply title changes, and local delete actions.
- Local deletions and edits stay in the working set until you save local state, export, or apply changes.

## Development Commands

```bash
./script/build_and_run.sh            # build, bundle, and launch
./script/build_and_run.sh --verify   # build, launch, and verify the process starts
./script/build_and_run.sh --logs     # launch and stream app logs
./script/build_and_run.sh --debug    # build and launch under lldb
swift test                           # run tests
```
