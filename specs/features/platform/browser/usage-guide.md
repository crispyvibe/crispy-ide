---
title: "In-App Browser"
feature: "F012"
domain: "platform"
audience: "user"
version: "1.0"
sidebar:
  label: "Browser"
  order: 3
---

# In-App Browser

## Overview

Crispy includes a full-featured in-app browser integrated into the vibespace. It supports URL navigation, address bar with history suggestions, find-in-page, configurable search engines, downloads, session persistence, named profiles, developer tools, and an agent automation API — all without leaving the IDE.

## Getting Started

1. Click a web link in a terminal session — it opens as a browser spotlight preview inside Crispy.
2. Use the address bar to navigate to any URL.
3. Pin the browser to the terminal board dock or detailed content viewer for persistent access.

## Workflows

### Navigating to a URL

1. Click the address bar in the browser chrome.
2. Type a URL, localhost address, or search query:
   - Input containing "localhost" resolves with `http://` scheme.
   - Input containing a dot or colon resolves with `https://` scheme.
   - Input with spaces or no URL pattern is treated as a search query using your selected engine.
3. Press Enter to navigate.

### Using Back/Forward Navigation

- Click the **Back** or **Forward** buttons in the browser chrome.
- Use mouse button 3 (back) or button 4 (forward) for hardware navigation.
- Session history is maintained across relaunches via persisted back/forward URL stacks.

### Find-in-Page

1. Open find-in-page (browser-specific activation).
2. Type your search term in the inline find bar.
3. Matches are highlighted yellow (#ffff00), with the current match in orange (#ff9632).
4. Use Next/Previous buttons to navigate between matches.
5. Dismiss the find bar to clear all highlights.

### Adjusting Page Zoom

- Zoom levels range from 0.25x to 5.0x.
- The zoom level is persisted in the session snapshot across relaunches.

### Opening Links from Terminal

1. When terminal output contains a web URL or hyperlink, activate it.
2. The link opens as a browser spotlight preview inside Crispy (not in the system browser).
3. From spotlight, you can:
   - **Pin** to the detailed content viewer (in detailed canvas mode).
   - **Pin** to the terminal board dock (in terminal-only canvas mode).

### Using Context Menus

Right-click on browser content for contextual actions:
- **On a link**: Open Link in New Tab, Open Link in Default Browser, Download Linked File.
- **On an image**: Copy Image.

### Managing Downloads

1. Downloads are triggered automatically by `Content-Disposition: attachment` headers or unrenderable MIME types.
2. A save panel (NSSavePanel) appears for you to choose the save location.
3. A downloading indicator appears in the browser chrome during active downloads.
4. If a download fails, an alert is displayed.

### Using Named Profiles

1. Create named browser profiles for isolated browsing contexts.
2. Each profile has its own cookies, storage, and data store (isolated `WKWebsiteDataStore`).
3. Profiles are persisted as JSON.
4. The default profile cannot be deleted.
5. Switch between profiles to use different browsing contexts.

### Importing Browser History

- Import history from **Chrome** or **Safari** via their SQLite databases.
- Duplicates are deduplicated by URL.
- Imported entries integrate with the frecency-ranked suggestion system.

### Using Developer Tools

- **Web Inspector**: Attach Safari developer tools to inspect browser content.
- **Console Capture**: Console messages (log, warn, error, info, debug) are captured via injected JavaScript, stored up to 512 entries.
- **Element Picker**: Activate to hover-highlight elements with a blue border showing tag#id.class. Click to copy rich context (Selector, Tag, Text, Component, File, HTML) to clipboard.

### Taking a Screenshot

1. Trigger the screenshot action from the browser overflow menu.
2. A `WKSnapshotConfiguration` captures the visible content.
3. An NSSavePanel appears to save the image as PNG.

### Opening in System Browser

- Select "Open in System Browser" to open the current URL in your default macOS browser.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Paste as plain text | Cmd+Shift+V |
| Address bar suggestions: navigate | Arrow Up/Down |
| Address bar suggestions: accept | Enter |
| Address bar suggestions: dismiss | Escape |

Menu key equivalents (Cmd+shortcuts) are routed to the menu system first. Return/Enter passes through for web form submission.

## Settings

| Setting | Description |
|---------|-------------|
| Search engine | Google, DuckDuckGo, or Bing — used for address bar search queries |
| Search suggestions enabled | Toggle remote search suggestions from Google Suggest API (250ms debounce, 1s timeout) |
| Custom insecure HTTP allowlist | Wildcard patterns (e.g., `*.local`) that bypass HTTP blocking |
| Theme mode | System, Light, or Dark — injects CSS `color-scheme` override |
| External open patterns | Regex patterns for URLs that should open in the system browser instead |

## Tips

- The browser history store is capped at 5000 entries with oldest evicted on overflow.
- History suggestions use frecency scoring: URL/host/title match, recency, visit count, and typed count.
- Saves to the history store are debounced at 200ms to avoid excessive writes.
- Insecure HTTP is blocked by default. The built-in allowlist includes localhost, 127.0.0.1, ::1, and 0.0.0.0.
- If the web content process crashes, the browser automatically recovers: it snapshots state, tears down the old WebView, creates a fresh one, and restores the session transparently.
- JavaScript `alert()`, `confirm()`, and `prompt()` dialogs are presented as native NSAlerts.
- Middle-clicking a link (button 2 with 0.8s intent window) opens it in a new browser tab.
- The browser supports WebAuthn/passkey authentication via a JavaScript bridge delegating to `ASAuthorizationController`.
- SSH proxy support routes browser traffic through a SOCKS5 tunnel for remote vibespace browsing.
- The Agent Automation API supports 84+ commands for programmatic browser control including navigation, element interaction, DOM queries, and accessibility snapshots.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Page shows error overlay | Check the URL is correct. The overlay includes a retry action — click it to reload. |
| HTTP page blocked | The URL uses insecure HTTP. Choose Proceed to continue, Open in Default Browser, or add the host to your custom allowlist in settings. |
| Downloads not saving | Ensure you have write permission to the chosen save location. Check for download failure alerts. |
| Browser stealing focus | The focus guard (`allowsFirstResponderAcquisition`) controls this. If the browser unexpectedly takes focus, it may be a click-through event — this is by design for `acceptsFirstMouse`. |
| Suggestions not appearing | Ensure search suggestions are enabled in settings. Suggestions are suppressed during active navigation. |
| Favicon not showing | The browser queries `link[rel~=icon]` elements first, then falls back to `/favicon.ico`. Some sites may not provide either. |

## Project Ownership

Each browser instance belongs to exactly one project. When you create a browser via the toolbar (or via terminal link / agent CLI without specifying a project), it is automatically associated with the currently focused project. If no project is focused, the create request is suppressed.

When you remove a project, all browsers owned by that project are closed automatically. The same applies when you park a project — but unlike removal, parking persists each browser's URL, history stacks, zoom, and theme so they can be restored on activate.

Browser tabs in the content viewer respect project scope filtering: when scope is "focused project", only browsers belonging to the focused project are shown.
