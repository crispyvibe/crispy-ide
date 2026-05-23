# Browser — Spec

Status: implemented

## Overview

In-app browser provides vibespace-integrated web browsing with full navigation controls, address bar with history and search suggestions, find-in-page, configurable search engines, download management, insecure HTTP blocking, theme mode injection, favicon display, crash recovery, JavaScript dialog handling, session persistence and restore, WebView focus and key routing, context menus, element picker, console capture, named profiles, browser data import, SSH proxy tunneling, WebAuthn/passkey support, and an agent automation API.

## Dependencies

- F003 (Terminal Spotlight) — browser spotlight preview and pin workflows
- F002 (Terminal Board) — browser tiles on terminal board
- F001 (Sessions & Tabs) — terminal-originated browser links

## Requirements

### F012-R01: Browser Navigation

Browser MUST support URL navigation, smart address bar resolution, back/forward history, reload/stop, and page zoom within the vibespace.

### F012-R02: Terminal-Originated Routing

Terminal web links MUST open in browser spotlight preview across vibespace surfaces.

### F012-R03: Spotlight Pin Workflows

Browser spotlight MUST support pinning to terminal board dock or detailed content viewer depending on canvas mode.

### F012-R04: Address Bar and Suggestions

Browser MUST provide an address bar with history suggestions (frecency-ranked) and optional remote search suggestions with debounce.

### F012-R05: Find-in-Page

Browser MUST support inline find-in-page with match highlighting, navigation between matches, and keyboard dismiss.

### F012-R06: Security Controls

Browser MUST block insecure HTTP with a configurable allowlist, display a secure badge for HTTPS, and handle TLS challenges with default behavior.

### F012-R07: Session Persistence

Browser MUST persist and restore URL, back/forward history stacks, zoom level, and theme mode across relaunches.

### F012-R08: Download Management

Browser MUST handle downloads triggered by Content-Disposition headers or unrenderable MIME types, with NSSavePanel for save location and failure alerts.

### F012-R09: WebView Hosting

Browser MUST manage WebView focus guards, key routing, mouse button navigation, click-through, drag filtering, and ownership arbitration between vibespace surfaces.

### F012-R10: Context Menus

Browser MUST provide context menu actions for links (open in new tab, open in default browser, download linked file) and images (copy image).

### F012-R11: Agent Automation API

Browser MUST expose a command dispatch API for programmatic navigation, element interaction, DOM queries, snapshots, and evaluation.

### F012-R12: Developer Tools

Browser MUST support Web Inspector attachment, console message capture, and element picker overlay.

### F012-R13: Named Profiles

Browser MUST support named browser profiles with isolated data stores and JSON persistence.

### F012-R14: Browser Data Import

Browser MUST support importing history from Chrome and Safari via SQLite with deduplication.

### F012-R15: SSH Proxy

Browser MUST support routing traffic through an SSH SOCKS5 tunnel for remote vibespace browsing.

### F012-R16: WebAuthn / Passkeys

Browser MUST support passkey authentication via a JavaScript bridge intercepting navigator.credentials and delegating to ASAuthorizationController.

### F012-R17: Project Ownership

Each browser instance MUST be owned by exactly one project. When a browser is created via the toolbar button, it MUST be auto-associated with the currently focused project. If no project is focused, browser creation MUST be blocked.

**CLI parity:** `browser.open` (Agent CLI) MUST resolve an owning project before dispatching: prefer the caller's `CRISPY_PROJECT_PATH` (set by terminals spawned with project context), then fall back to the active vibespace's focused project. If neither resolves, the call MUST fail with `no_focused_project` rather than silently succeed.

### F012-R18: Project Lifecycle Coupling

When a project is removed from the vibespace OR parked (F021-R09 through R11), all browsers associated with that project MUST be closed. Lifecycle parity with terminals and files: the close request goes through the existing `.closeBrowserRequested` notification pipeline so board tiles, content-viewer tabs, and orphan view-models are torn down consistently.

### F012-R19: Browser Tabs in Detailed View

In detailed view, project-associated browsers MUST appear as content-viewer tabs using the existing `webPage` tab kind. Browser tabs MUST respect viewer scope filtering (F006-R13) — when scope is "focused project", only browsers belonging to the focused project are shown.

### F012-R20: Browser Session Persistence per Project

Browser session state (URL, history stacks, zoom, theme mode per F012-R07) MUST be persisted as part of the owning project's `ProjectConfigFile.browserSessionEntries`. On vibespace restore, browser tabs MUST be restored for active (non-parked) projects. Parked projects retain their browser session entries on disk; restoration occurs as part of unpark (F021-R11).


## Scenarios

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Navigation & Address Bar                                    -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S01: Browser supports URL navigation with in-app chrome

**Given** a browser is opened inside the vibespace
**When** the user navigates to a URL
**Then** the browser displays in-app chrome with back, forward, reload/stop, address field, and overflow menu
**And** the address bar updates to reflect the loaded page URL

### Scenario F012-S02: Address bar resolves localhost input with http scheme

**Given** the user types text into the address bar
**When** the input contains "localhost"
**Then** it is resolved with `http://` scheme

### Scenario F012-S03: User selects a configurable search engine

**Given** the browser has a SearchEngine enum with Google, DuckDuckGo, and Bing options
**When** the user selects a search engine
**Then** address bar search queries use that engine's URL template
**And** the selection is persisted across sessions

### Scenario F012-S04: Back and forward navigation with restored session history

**Given** a browser has navigation history
**When** the user activates back or forward
**Then** the browser navigates using parallel back/forward URL stacks maintained in the view model
**And** if a restored session history exists, it is consumed on first back/forward and then abandoned

### Scenario F012-S05: Reload control reloads the current page

**Given** a browser is open inside the vibespace
**When** the user activates reload
**Then** the current page is reloaded

### Scenario F012-S06: Page zoom between 0.25x and 5.0x

**Given** a browser is displaying web content
**When** the user adjusts the zoom level
**Then** the rendered page zoom updates within the range 0.25x to 5.0x
**And** the zoom level is persisted in the session snapshot

### Scenario F012-S07: Page load progress rendered as accent loading bar

**Given** a browser is loading a page
**When** `estimatedProgress` updates on the WKWebView
**Then** the value is observed and stored on `BrowserPanelViewModel`
**And** a 2px accent-colored progress bar is displayed in the browser chrome

### Scenario F012-S08: Friendly error page shown for navigation failures

**Given** the user navigates to a URL that fails to load
**When** the navigation error is not a cancellation (NSURLErrorCancelled or frame load interrupted)
**Then** the browser displays a custom error overlay with the error description
**And** the error overlay offers a retry action

### Scenario F012-S09: Cancelled navigation errors are suppressed

**Given** a browser navigation is in progress
**When** the navigation is cancelled (NSURLErrorCancelled or WebKitErrorFrameLoadInterruptedByPolicyChange)
**Then** the error is silently suppressed and no error page or alert is shown


<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Address Bar Suggestions                                     -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S10: History suggestions ranked by frecency

**Given** the user types into the address bar
**When** matching history entries exist
**Then** suggestions are ranked by frecency scoring (URL/host/title match, recency, visit count, typed count)
**And** the history store is capped at 5000 entries with oldest evicted on overflow

### Scenario F012-S11: Remote search suggestions fetched with debounce

**Given** the user types a query into the address bar
**And** `searchSuggestionsEnabled` is true
**When** input pauses for 250ms
**Then** the browser fetches search suggestions from the Google Suggest API
**And** the request times out after 1 second if no response is received

### Scenario F012-S12: Keyboard navigation through suggestions dropdown

**Given** the suggestions dropdown is visible
**When** the user presses arrow down or arrow up
**Then** the selection moves through the suggestion list
**And** pressing Enter navigates to the selected suggestion
**And** pressing Escape dismisses the dropdown

### Scenario F012-S13: Suggestions suppressed during active navigation

**Given** a navigation is in progress
**When** the address bar text changes due to the navigation
**Then** the suggestions dropdown is not shown

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Find-in-Page                                                -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S14: Find-in-page with match highlighting

**Given** a browser is displaying web content
**When** the user opens find-in-page
**Then** an inline find bar is shown over the browser chrome
**And** matching text is highlighted yellow (#ffff00) with the current match highlighted orange (#ff9632)
**And** matches are found via injected JavaScript using a TreeWalker over text nodes

### Scenario F012-S15: Find-in-page navigation and dismiss

**Given** find-in-page is active with matches highlighted
**When** the user activates find next or find previous
**Then** the current match advances or retreats and scrolls into view with smooth center alignment
**And** when the user dismisses find-in-page, all highlights are removed and the find bar is hidden


<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Security                                                    -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S16: Insecure HTTP blocking with allowlist

**Given** the user navigates to an HTTP (non-HTTPS) URL
**When** the host is not in the default allowlist (localhost, 127.0.0.1, ::1, 0.0.0.0) and not in the `customInsecureHTTPAllowlist`
**Then** the browser presents an alert with three options: Open in Default Browser, Proceed, or Cancel
**And** hosts matching wildcard patterns in the custom allowlist (e.g., `*.local`) bypass the block

### Scenario F012-S17: HTTPS secure badge displayed in address bar

**Given** the user navigates to an HTTPS page
**When** the page loads with `hasOnlySecureContent` true
**Then** a lock icon is displayed in the address bar
**And** the icon is removed when navigating to a non-secure or mixed-content page

### Scenario F012-S18: TLS authentication challenge uses default handling

**Given** a browser navigates to a server presenting a TLS certificate challenge
**When** the `didReceive challenge` delegate is called
**Then** the browser applies `performDefaultHandling`
**And** no custom certificate trust UI is presented

### Scenario F012-S19: External URL scheme handoff to macOS

**Given** the user clicks a `mailto:`, `tel:`, or other non-HTTP link in browser content
**When** the navigation is intercepted by the navigation delegate
**Then** the URL is handed off to the default macOS handler via `NSVibeSpace.shared.open`
**And** the browser remains on the current page

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Session Persistence                                         -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S20: Session snapshot persists URL, history stacks, zoom, and theme

**Given** a browser session is active
**When** the session is serialized via `sessionSnapshot()`
**Then** the snapshot includes `urlString`, `backHistoryURLStrings`, `forwardHistoryURLStrings`, `pageZoom`, and `themeMode`
**And** `about:blank` URLs are filtered out

### Scenario F012-S21: Session restore reconstructs browser state on relaunch

**Given** a persisted `BrowserSessionSnapshot` exists
**When** the vibespace is reopened
**Then** the browser navigates to the saved URL
**And** the back/forward history stacks, zoom level, and theme mode are restored

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Downloads                                                   -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S22: Download triggered by Content-Disposition or unrenderable MIME

**Given** the browser receives a server response
**When** the response includes a `Content-Disposition: attachment` header or the MIME type is not renderable by WebKit
**Then** the browser initiates a two-phase download: temporary file then NSSavePanel for final save location

### Scenario F012-S23: Download progress indicator during active download

**Given** a file download is in progress
**When** `setDownloading(true)` is called via `onDownloadStarted`
**Then** the `isDownloading` flag is set on the view model
**And** `setDownloading(false)` is called via `onDownloadEnded` when the download completes or fails

### Scenario F012-S24: Download failure displays an alert

**Given** a file download is in progress
**When** the download fails
**Then** an alert is displayed to the user indicating the failure


<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Theme Mode                                                  -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S25: Theme mode injection (system, light, dark)

**Given** a browser is open inside the vibespace
**When** the user selects a theme mode (system, light, or dark)
**Then** the browser injects the corresponding CSS `color-scheme` override into the web content
**And** the selected mode is persisted in the session snapshot

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Favicon                                                     -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S26: Favicon fetched and displayed in browser chrome

**Given** a browser navigates to a web page
**When** the page finishes loading
**Then** the browser queries for a favicon via injected JavaScript (link[rel~=icon])
**And** falls back to `/favicon.ico` if no link element is found
**And** the favicon data is displayed in the address bar

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Crash Recovery                                              -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S27: Web content process crash recovery

**Given** a browser is displaying web content
**When** the web content process terminates unexpectedly
**Then** the browser snapshots the current state, tears down the old WebView, creates a fresh one, and restores the session
**And** the recovery is transparent to the user

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- JavaScript Dialogs                                          -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S28: JavaScript alert dialog presented as native NSAlert

**Given** a browser is displaying web content
**When** the page triggers `window.alert()`
**Then** a native NSAlert is presented with the page message and an OK button

### Scenario F012-S29: JavaScript confirm dialog presented with OK/Cancel

**Given** a browser is displaying web content
**When** the page triggers `window.confirm()`
**Then** a native NSAlert is presented with OK and Cancel buttons
**And** the boolean result is returned to the calling script

### Scenario F012-S30: JavaScript prompt dialog presented with text input

**Given** a browser is displaying web content
**When** the page triggers `window.prompt()`
**Then** a native NSAlert is presented with a text input field
**And** the user's input (or nil on cancel) is returned to the calling script

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- WebView Hosting & Focus                                     -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S31: Focus guard prevents unexpected focus stealing

**Given** a browser WebView is embedded in the vibespace
**When** the WebView attempts to acquire first responder status
**Then** `allowsFirstResponderAcquisition` and `pointerFocusAllowanceDepth` on the hosting view control whether focus is granted
**And** this prevents the browser from stealing focus from other vibespace surfaces

### Scenario F012-S32: Click-through behavior accepts first mouse

**Given** the browser WebView is not the focused view
**When** the user clicks on the browser content
**Then** `acceptsFirstMouse` returns true, so the click both focuses the browser and activates the clicked element

### Scenario F012-S33: Key routing priority chain

**Given** a browser is focused inside the vibespace
**When** the user presses a key combination
**Then** menu key equivalents (Cmd+shortcuts) are routed to the menu system first
**And** Return/Enter is passed through for web form submission
**And** Cmd+Shift+V is intercepted for paste-as-plain-text
**And** IME marked text is bypassed to avoid partial input submission

### Scenario F012-S34: Mouse back/forward buttons navigate history

**Given** a browser is open and focused
**When** the user presses mouse button 3 (back) or button 4 (forward)
**Then** the browser navigates back or forward in session history

### Scenario F012-S35: Middle-click link opens in new tab

**Given** the user middle-clicks a hyperlink in browser content
**When** the click is detected (button 2 with 0.8s intent window)
**Then** the link URL is routed to `onOpenNewBrowser` as a new tab

### Scenario F012-S36: WebView ownership arbitration between hosts

**Given** multiple vibespace surfaces may host browser content (tiles, detailed views, previews)
**When** a browser session is transferred between surfaces
**Then** `BrowserHostOwnershipCoordinator` arbitrates WebView ownership to prevent conflicts

### Scenario F012-S37: Drag filtering rejects internal pane drag types

**Given** a browser WebView is embedded in the vibespace
**When** an internal pane drag operation enters the browser area
**Then** the browser filters out internal pane drag types
**And** only standard web drag types (URLs, text, files) are accepted


<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Context Menus                                               -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S38: Open Link in New Tab via context menu

**Given** the user right-clicks a hyperlink in browser content
**When** the user selects "Open Link in New Tab"
**Then** the link URL is routed to `onOpenNewBrowser`
**And** the original page remains unchanged

### Scenario F012-S39: Open Link in Default Browser via context menu

**Given** the user right-clicks a hyperlink in browser content
**When** the user selects "Open Link in Default Browser"
**Then** the link URL is opened via `NSVibeSpace.shared.open`
**And** the in-app browser remains on the current page

### Scenario F012-S40: Copy Image via context menu

**Given** the user right-clicks an image in browser content
**When** the user selects "Copy Image"
**Then** the image data is fetched and placed on the system pasteboard via a pipeline

### Scenario F012-S41: Download Linked File via context menu

**Given** the user right-clicks a hyperlink in browser content
**When** the user selects "Download Linked File"
**Then** a download is initiated for the linked resource

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Popup Windows                                               -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S42: Sized popup opens in separate NSWindow

**Given** a website calls `window.open()` with explicit size parameters
**When** the popup is created via `BrowserUIDelegate`
**Then** a separate NSWindow is created with the specified dimensions
**And** the popup has opener linkage to the source page

### Scenario F012-S43: Non-sized popup opens as new browser tab

**Given** a website calls `window.open()` without size parameters or a link has `target="_blank"`
**When** the popup is created via `BrowserUIDelegate`
**Then** the URL is routed to `onOpenInNewTab`
**And** no separate window is created

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- File Upload & Media Capture                                 -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S44: File upload via NSOpenPanel

**Given** a web page contains a file input element
**When** the user activates the file input
**Then** the browser presents an NSOpenPanel via `WKUIDelegate.runOpenPanel`
**And** the selected files are provided to the web page

### Scenario F012-S45: Media capture permission delegated to user

**Given** a web page requests camera or microphone access
**When** the `requestMediaCapturePermissionFor` delegate is called
**Then** the browser returns `.prompt` to delegate the decision to the system permission dialog

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Terminal-Originated Routing & Spotlight                      -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S46: Terminal web links open in browser spotlight

**Given** terminal output contains a web URL or hyperlink
**When** the user activates that link from detailed view, terminal board, or spotlight
**Then** the link opens inside Crispy as a browser spotlight preview
**And** the system browser is not used for that activation

### Scenario F012-S47: Browser spotlight pin promotes to detailed content viewer in detailed mode

**Given** a browser is open in spotlight
**And** the canvas is in detailed mode
**When** the user clicks the pin action
**Then** the browser is promoted into the detailed content viewer

### Scenario F012-S48: Temporary browser preview restores previous spotlight on dismiss

**Given** a browser spotlight preview was opened from another spotlight item
**When** the browser preview is dismissed
**Then** the previous spotlight item is restored instead of clearing spotlight state

### Scenario F012-S49: Temporary browser previews excluded from spotlight carousel

**Given** spotlight is showing a temporary browser preview
**When** the user attempts spotlight carousel navigation
**Then** carousel controls are hidden and adjacent spotlight switching does not occur

### Scenario F012-S50: Browser preview spawns another transient preview

**Given** a browser spotlight preview is active
**When** web content requests a new tab or window via `target=_blank` or command-modified activation
**Then** a new transient browser spotlight preview is opened
**And** dismissing the nested preview restores the source browser spotlight

### Scenario F012-S51: Detailed-mode spotlight keeps pin available for browser content

**Given** canvas mode is detailed and spotlight is showing browser content
**When** spotlight chrome renders
**Then** the pin action remains available
**And** using pin promotes the browser into the detailed content viewer


<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Developer Tools & Console                                   -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S52: Console message capture via injected JavaScript

**Given** a browser is displaying web content
**When** the page calls `console.log()`, `console.warn()`, `console.error()`, `console.info()`, or `console.debug()`
**Then** the output is captured via injected JavaScript that overrides native console methods
**And** messages are stored up to a 512-entry cap and flushed via `flushConsoleMessages()`

### Scenario F012-S53: Element picker overlay for DOM inspection

**Given** the user activates the element picker (`isElementPickerActive`)
**When** the user hovers over elements in the browser content
**And** the user clicks an element
**Then** a blue-bordered overlay highlights the hovered element with a label showing tag#id.class
**And** rich context is copied to the clipboard (Selector, Tag, Text, Component if React, File if React, HTML)
**And** the picker auto-deactivates via a polling mechanism

### Scenario F012-S54: Web Inspector attachment

**Given** a browser is open inside the vibespace
**When** the user activates Web Inspector
**Then** Safari developer tools are attached to the browser content for inspection
**And** Web Inspector state is not persisted in the session snapshot

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- History Store                                               -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S55: Browser history persisted with frecency scoring

**Given** the user navigates to pages in the browser
**When** a page visit occurs, `recordVisit` is called; when the user types a URL, `recordTypedNavigation` is called
**Then** the visit is recorded in `BrowserHistoryStore` with JSON persistence
**And** saves are debounced at 200ms
**And** the store is capped at 5000 entries

### Scenario F012-S56: Clear all browsing data

**Given** the user triggers clear browsing data
**When** `clearBrowsingData()` is called
**Then** history is cleared via `BrowserHistoryStore.clearAll()`
**And** website data is removed from `WKWebsiteDataStore`

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Browser Actions                                             -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S57: Open current URL in system browser

**Given** a browser is displaying a loaded page
**When** the user selects "Open in System Browser"
**Then** the current URL is opened via `NSVibeSpace.shared.open`

### Scenario F012-S58: Take screenshot of browser content

**Given** a browser is displaying a loaded page
**When** the user triggers a screenshot
**Then** `WKSnapshotConfiguration` captures the visible content
**And** an NSSavePanel is presented to save the image as PNG

### Scenario F012-S59: Paste as plain text via Cmd+Shift+V

**Given** a browser form field is focused
**When** the user presses Cmd+Shift+V with rich text on the clipboard
**Then** only the plain text content is pasted into the field with all formatting stripped

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Host Allowlist / External Patterns                          -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S60: URL matching external pattern opens in system browser

**Given** the view model has `externalOpenPatterns` configured as regex patterns
**When** the browser navigates to a URL matching a pattern
**Then** `shouldOpenExternally` returns true
**And** the URL is opened in the default macOS browser instead of loading in-app


<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Named Browser Profiles                                      -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S61: Named profiles with isolated data stores

**Given** the browser supports named profiles via `BrowserProfileStore`
**When** the user creates a profile
**Then** an isolated `WKWebsiteDataStore` is created for that profile
**And** profiles are persisted as JSON
**And** the default profile cannot be deleted

### Scenario F012-S62: Switching between named profiles

**Given** multiple named profiles exist
**When** the user switches to a different profile
**Then** the browser uses that profile's isolated cookies, storage, and data store

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Browser Data Import                                         -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S63: Import history from Chrome

**Given** the user triggers a Chrome history import
**When** `BrowserDataImporter` reads the Chrome SQLite history database
**Then** history entries are imported with timestamp conversion
**And** duplicates are deduplicated by URL

### Scenario F012-S64: Import history from Safari

**Given** the user triggers a Safari history import
**When** `BrowserDataImporter` reads the Safari SQLite history database via a temp file copy
**Then** history entries are imported with timestamp conversion and deduplication

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- SSH Proxy                                                   -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S65: Browser routes traffic through SSH SOCKS5 proxy

**Given** the user is connected to a remote vibespace via SSH
**When** a browser pane is configured with a `BrowserProxyCoordinator`
**Then** a SOCKS5 tunnel is established and traffic is routed through the SSH connection
**And** `ProxyConfiguration` is applied to the WebView
**And** the tunnel is cleaned up on `deinit`

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- WebAuthn / Passkeys                                         -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S66: Passkey creation via navigator.credentials.create

**Given** a website calls `navigator.credentials.create()` for WebAuthn registration
**When** the browser's JavaScript bridge intercepts the call
**Then** `ASAuthorizationController` is invoked for passkey creation
**And** the credential is returned to the website on success
**And** a `LeakAvoider` pattern prevents retain cycles

### Scenario F012-S67: Passkey authentication via navigator.credentials.get

**Given** a website calls `navigator.credentials.get()` for WebAuthn authentication
**When** the browser's JavaScript bridge intercepts the call
**Then** `ASAuthorizationController` is invoked for passkey assertion
**And** the assertion result is returned to the website

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Docked Browser Coordinator                                  -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S68: Docked browser coordinator manages browser VMs

**Given** the vibespace has browser tiles, detailed views, and previews
**When** `DockedBrowserCoordinator` is active
**Then** it manages the lifecycle of `BrowserPanelViewModel` instances for each surface
**And** supports tab search by title or URL
**And** can promote a preview to a persistent tile

### Scenario F012-S69: Docked browser coordinator persists sessions

**Given** browser sessions are managed by `DockedBrowserCoordinator`
**When** persistence is triggered
**Then** session snapshots are collected from all managed VMs
**And** persistence scheduling ensures snapshots are saved without excessive writes


<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Agent Automation API                                        -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S70: Agent API command dispatch

**Given** a browser tab is open with loaded content
**When** an agent sends a command via `BrowserAgentAPI`
**Then** the command is dispatched through a dispatch table supporting 84+ commands
**And** results are returned as structured responses

### Scenario F012-S71: Agent API element ref system

**Given** the agent has taken a page snapshot
**When** the snapshot assigns `@eN` tokens to visible elements
**Then** subsequent commands can reference elements by `@eN` token
**And** tokens are resolved to CSS selectors for JavaScript execution

### Scenario F012-S72: Agent API navigation commands

**Given** an agent is controlling a browser tab
**When** the agent issues navigate, goBack, goForward, reload, or waitForNavigation commands
**Then** the browser performs the corresponding navigation action

### Scenario F012-S73: Agent API element interaction commands

**Given** an agent references an element via `@eN` token or CSS selector
**When** the agent issues click, dblclick, hover, or focus commands
**Then** the action is performed on the element with retry logic for transient failures

### Scenario F012-S74: Agent API form interaction commands

**Given** an agent references a form element
**When** the agent issues fill, type, press, or select commands
**Then** fill uses React-compatible native setter to trigger change events
**And** type simulates individual keystrokes
**And** select changes the value of a `<select>` element

### Scenario F012-S75: Agent API DOM query commands

**Given** an agent needs to inspect page content
**When** the agent issues querySelector, querySelectorAll, getText, getAttribute, or getProperty commands
**Then** the browser executes the query and returns structured results

### Scenario F012-S76: Agent API advanced find commands

**Given** an agent needs to locate elements by semantic attributes
**When** the agent issues findByRole, findByText, findByLabel, findByPlaceholder, findByAlt, findByTitle, findByTestId, findFirst, findLast, or findNth commands
**Then** CSS path generation locates the matching elements
**And** results include element refs for subsequent interaction

### Scenario F012-S77: Agent API accessibility snapshot

**Given** an agent requests a page snapshot
**When** the snapshot command is executed
**Then** the browser generates an accessibility tree with role detection and visibility filtering
**And** each visible element is assigned an `@eN` ref token
**And** the tree is returned as structured text

### Scenario F012-S78: Agent API eval executes JavaScript and returns result

**Given** an agent is controlling a browser tab
**When** the agent issues eval
**Then** the JavaScript is executed with async wrapping and the result returned


<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Planned Features                                            -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S79: Browser chrome navigable via VoiceOver and keyboard [planned]

**Given** VoiceOver is enabled
**When** the user navigates the browser chrome
**Then** all controls (address bar, back, forward, reload, pin) are reachable via keyboard Tab and VoiceOver cursor
**And** each control announces its role and state

### Scenario F012-S80: Ghost text inline autocompletion from history [planned]

**Given** the user types a partial URL in the address bar
**When** a matching history entry exists
**Then** ghost text appears completing the URL inline
**And** pressing Tab or Right Arrow accepts the completion

### Scenario F012-S81: Self-signed certificate trust prompt for local dev servers [planned]

**Given** the user navigates to a local dev server with a self-signed certificate
**When** the TLS challenge is received
**Then** the browser presents a certificate trust prompt
**And** the user can accept the certificate for the session or permanently

### Scenario F012-S82: Address bar state machine (idle, editing, loading) [planned]

**Given** the address bar is in idle state showing the current URL
**When** the user clicks the address bar
**Then** it transitions to editing state with the full URL selected
**And** submitting a URL transitions to loading state with a progress indicator
**And** it returns to idle state when navigation completes

### Scenario F012-S83: User disables remote search suggestions [planned]

**Given** the user opens browser settings
**When** the user disables the search suggestions toggle
**Then** the address bar no longer fetches remote suggestions
**And** only local history suggestions are shown while typing

### Scenario F012-S84: User adds host to insecure HTTP allowlist with wildcard [planned]

**Given** the user opens browser security settings
**When** the user adds a pattern (e.g., `*.local`) to the custom insecure HTTP allowlist
**Then** HTTP requests to matching hosts bypass the insecure connection warning
**And** the allowlist is persisted across app relaunches

### Scenario F012-S85: Download progress UI with percentage or bytes [planned]

**Given** a file download is in progress
**When** the download is actively transferring
**Then** a progress indicator shows the download percentage or bytes transferred
**And** the indicator is removed when the download completes or fails

### Scenario F012-S86: Local file URL grants read access to parent directory [planned]

**Given** the browser loads a local file URL via `loadFileURL`
**When** the file is loaded
**Then** `allowingReadAccessTo` is set to the file's parent directory
**And** the web content can reference sibling resources within that directory

### Scenario F012-S87: Address bar resolves dot or colon input with https scheme

**Given** the user types text into the address bar
**When** the input contains a dot or colon
**Then** it is resolved with `https://` scheme

### Scenario F012-S88: Address bar resolves ambiguous input as search query

**Given** the user types text into the address bar
**When** the input contains spaces or matches neither localhost nor dot/colon pattern
**Then** it is treated as a search query using the selected search engine

### Scenario F012-S89: Stop control cancels in-progress navigation

**Given** a browser is open inside the vibespace
**And** a page is currently loading
**When** the user activates stop
**Then** the in-progress navigation is cancelled

### Scenario F012-S90: Browser spotlight pin promotes to terminal board dock in terminal-only mode

**Given** a browser is open in spotlight
**And** the canvas is in terminal-only mode
**When** the user clicks the pin action
**Then** the browser is promoted into the terminal board dock

### Scenario F012-S91: Agent API wait polls until condition is met

**Given** an agent is controlling a browser tab
**When** the agent issues wait
**Then** a MutationObserver polls until the condition is met

### Scenario F012-S92: Agent API screenshot returns PNG base64 image

**Given** an agent is controlling a browser tab
**When** the agent issues screenshot
**Then** a PNG base64 image is returned

### Scenario F012-S93: Agent API cookies and storage commands

**Given** an agent is controlling a browser tab
**When** the agent issues cookies or storage commands
**Then** the corresponding browser data is returned or modified

<!-- ═══════════════════════════════════════════════════════════ -->
<!-- Project Ownership (F012-R17–R20)                            -->
<!-- ═══════════════════════════════════════════════════════════ -->

### Scenario F012-S94: Toolbar new browser auto-associates with focused project

**Given** a vibespace has a focused project
**When** the user creates a new browser via the toolbar (or any path that posts `.openNewBrowserRequested` without an explicit `projectPath`)
**Then** the new browser's `BrowserPanelViewModel.projectPath` is set to the focused project's normalized root path
**And** the browser appears in the surface matching the current canvas mode (board or content viewer)

### Scenario F012-S95: New browser is blocked when no project is focused

**Given** a vibespace has no focused project
**When** a new browser request is dispatched without an explicit `projectPath`
**Then** the request is suppressed and no browser instance is created
**And** the agent CLI logger records "browser open suppressed: no focused project"

### Scenario F012-S96: Removing a project closes all its browsers

**Given** project P has at least one browser open (board tile or content-viewer tab)
**When** project P is removed from the vibespace
**Then** `DockedBrowserCoordinator.closeBrowsers(forProjectPath:)` enumerates all browsers whose `projectPath` matches P's normalized path
**And** each receives a `.closeBrowserRequested` notification
**And** board tiles, content-viewer tabs, and any orphan view-models are torn down via the existing close-handling pipeline

### Scenario F012-S97: Parking a project captures and persists its browser sessions

**Given** project P has at least one browser owned by it
**When** project P is parked
**Then** `DockedBrowserCoordinator.snapshotBrowserSessions(forProjectPath:)` captures a `BrowserSessionEntry` for each browser (browserID + snapshot + optional pinned tile ID)
**And** the entries are persisted into `ProjectConfigFile.browserSessionEntries` for P
**And** all browsers for P are then closed via the standard close-handling pipeline

### Scenario F012-S98: Unparking a project restores its persisted browser sessions

**Given** parked project P has persisted `browserSessionEntries`
**When** project P is activated (unparked)
**Then** entries with `pinnedTileID` are restored as board tiles via `restoreTile(id:snapshot:)`
**And** entries without `pinnedTileID` are restored as content-viewer tabs via `restoreDetailedBrowser(reference:snapshot:)`
**And** when the canvas is in detailed mode, the corresponding `webPage` tabs are surfaced via `ContentViewerStore.openWebPage`

### Scenario F012-S99: Browser tabs respect viewer scope filtering

**Given** browsers belonging to multiple projects are open as content-viewer tabs
**And** viewer scope is set to "focused project"
**When** the active pane renders its tab strip
**Then** only `.webPage` tabs whose `BrowserTabReference.projectPath` matches the focused project's path are shown (extends F006-S34)

### Scenario F012-S100: CLI browser.open resolves project from CRISPY_PROJECT_PATH

**Given** a CLI client invokes `browser.open` from a terminal whose env has `CRISPY_PROJECT_PATH` set
**When** the request reaches `handleBrowserOpen`
**Then** the resolved project path is taken from `_env.project_path`
**And** the dispatch posts `.openNewBrowserRequested` with that path in userInfo
**And** the response result includes `project_path`

### Scenario F012-S101: CLI browser.open falls back to focused project

**Given** a CLI client invokes `browser.open` with no `_env.project_path` (or empty string)
**And** the active vibespace has a focused project
**When** the request reaches `handleBrowserOpen`
**Then** the resolved project path is the focused project's `projectIdentifier`
**And** dispatch proceeds normally

### Scenario F012-S102: CLI browser.open returns no_focused_project when no context resolves

**Given** a CLI client invokes `browser.open` with no `_env.project_path`
**And** no vibespace has a focused project (e.g., catalog empty or all projects parked)
**When** the request reaches `handleBrowserOpen`
**Then** the response is an error with code `no_focused_project`
**And** no `.openNewBrowserRequested` notification is posted

### Scenario F012-S103: CLI browser.list defaults to project scope, vibespace is opt-in

**Given** the focused vibespace has browsers owned by projects `/p/alpha` and `/p/beta`, plus one orphan browser with no project
**When** the agent invokes `crispy browser list` from a terminal whose `CRISPY_PROJECT_PATH` is `/p/alpha` (default scope)
**Then** the response includes only the `/p/alpha` browser
**And** the `/p/beta` browser and orphan browsers are filtered out

**Given** the same setup
**When** the agent invokes `crispy browser list --scope vibespace`
**Then** the response includes all 3 entries
**And** each entry has a `project_path` field (string for owned browsers, null for orphans)

**Given** the agent invokes `crispy browser list` (default scope) with no `CRISPY_PROJECT_PATH` and no focused project
**Then** the response is an error with code `no_focused_project` (rather than silently returning empty)
**And** the error message hints to pass `scope=vibespace` for cross-project listings

## Acceptance Criteria

- Browser navigation loads pages within standard WebKit timelines.
- Terminal links route to browser spotlight without system browser fallback.
- Pin action promotes to correct surface based on canvas mode.
- Address bar resolves URLs, localhost, and search queries correctly.
- History suggestions are ranked by frecency with 5000-entry cap.
- Remote search suggestions are fetched with 250ms debounce and 1s timeout.
- Find-in-page highlights matches with yellow/orange and supports next/previous navigation.
- Insecure HTTP is blocked with allowlist bypass for localhost and custom patterns.
- Session snapshot persists and restores URL, history stacks, zoom, and theme.
- Downloads use two-phase temp-file-then-NSSavePanel flow with failure alerts.
- Crash recovery transparently replaces the WebView and restores state.
- JS alert/confirm/prompt dialogs are presented as native NSAlerts.
- Focus guard, key routing, and click-through behave correctly in multi-surface vibespace.
- Context menus provide Open in New Tab, Open in Default Browser, Copy Image, Download Linked File.
- Console capture stores up to 512 messages via injected JS overrides.
- Element picker highlights on hover and copies rich context on click.
- Named profiles create isolated data stores with JSON persistence.
- Chrome and Safari history import works via SQLite with deduplication.
- SSH SOCKS5 proxy routes traffic through remote vibespace tunnel.
- WebAuthn passkey creation and authentication work via ASAuthorizationController bridge.
- Agent API dispatches 84+ commands with element ref system and accessibility snapshots.
- Each browser instance is owned by exactly one project; toolbar-created browsers auto-associate with the focused project (F012-R17).
- Removing or parking a project closes all browsers owned by that project via the standard close pipeline (F012-R18).
- Browser tabs in detailed view respect viewer scope filtering by project (F012-R19, extends F006-R13).
- Browser session state is persisted per-project in `ProjectConfigFile.browserSessionEntries`; restored for active projects on vibespace open and on unpark (F012-R20).
- CLI `browser.open` resolves an owning project (env → focused project) before dispatching, returning `no_focused_project` when neither resolves (F012-R17 CLI parity).

## Test Coverage

| Scope | Test File |
|---|---|
| Browser project ownership at the VM layer; `BrowserSessionEntry` serialization round-trip; `ProjectConfigFile` backward-compatible decode | `tests/unit/Models/VibeSpaceStateParkingTests.swift` |
| `browser.open` CLI handler: env-path takes precedence, focused-project fallback, structured error when neither resolves, browser_id tagged identifier | `tests/unit/Models/CLICommandRouterBrowserOpenTests.swift` |
| `browser.list` CLI handler: default vibespace scope, project scope filtering, project_path per entry, no_focused_project for unresolvable callers | `tests/unit/Models/CLICommandRouterBrowserListTests.swift` |
| Existing browser feature tests (preview reuse, agent API, restore flows) | `tests/unit/Features/VibeSpace/Services/Browser/BrowserFeatureTests.swift` |

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/browser/feature.md (BRW-001–033) | — |
| 2026-04-18 | Complete rewrite to reflect implemented code state with 86 scenarios | — |
| 2026-04-18 | Fix BDD format: add Then clauses, split multi-When scenarios into S87–S93 | — |
| 2026-05-22 | Add project ownership feature (F012-R17–R20, scenarios S94–S99) — 99 scenarios total | — |
| 2026-05-22 | CLI parity: `browser.open` resolves owning project before dispatch (scenarios S100–S102; new error code `no_focused_project`) — 102 scenarios total | — |
