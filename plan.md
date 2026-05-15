# Ultimate Organizer - Project Plan

A native macOS application to organize, rename, and optimize Chrome bookmarks using local AI.

## Project Architecture
- **Platform:** macOS (SwiftUI)
- **Language:** Swift
- **Persistence:** SwiftData (for storing the staging area/pending changes)
- **AI Engine:** Local LLM via **Ollama** (connecting to `localhost:11434`)
- **Data Source:** Direct file access to Chrome's `Bookmarks` JSON file.

## Core Features

### 1. Bookmark Analysis & Optimization
- **Total Renaming:** The AI will generate a fresh, clean, and consistent name for *every* bookmark based on its URL and original title.
- **The Librarian (Deep Hierarchy):** The AI will propose a detailed, nested folder structure to optimize the distribution of links.
- **Hybrid Fetching:**
    - **Fast Mode:** Uses only the existing URL and Title for initial analysis.
    - **Deep Mode:** Optional per-link or batch fetching of page content (meta tags/text) for more accurate categorization.
- **Auto-Merge:** Duplicate URLs across different folders will be automatically consolidated into the single best location suggested by the AI.

### 2. User Experience (Staging Area)
- **Review & Approve:** A side-by-side "Current" vs. "Proposed" view.
- **Interactive Editing:** Users can manually tweak AI-suggested names or drag-and-drop items between folders before final application.
- **Persistence:** Progress is saved in SwiftData, allowing for multi-session organization.

### 3. Safety & Application
- **Chrome Conflict Detection:** The app will detect if Chrome is running and prevent writing to the file until Chrome is closed to avoid data corruption or overwrites.
- **Direct Write:** Once approved, the app writes the finalized JSON back to the Chrome `Bookmarks` file.

## Implementation Roadmap

### Phase 1: Foundation
- Scaffold the macOS SwiftUI project.
- Implement Chrome `Bookmarks` file discovery and parsing (JSON).
- Set up SwiftData models for Bookmarks and Folders in the staging area.

### Phase 2: AI Integration
- Implement Ollama API client.
- Develop prompts for:
    - User-friendly renaming.
    - Hierarchical categorization.
- Implement "Fast Mode" metadata analysis.

### Phase 3: Staging UI
- Build the main side-by-side comparison view.
- Add folder navigation and bookmark list components.
- Implement manual editing and drag-and-drop functionality.

### Phase 4: Advanced Features & Safety
- Implement the "Deep Fetch" logic for HTML content.
- Implement duplicate detection and auto-merging.
- Add Chrome process detection logic.

### Phase 5: Final Polish
- Refine the UI/UX with native macOS aesthetics.
- Add "Apply" logic with proper error handling and backups.
