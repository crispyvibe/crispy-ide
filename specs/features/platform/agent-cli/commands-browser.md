# Agent CLI — Browser Commands

This document specifies the `browser.*` commands. See [spec.md](spec.md) for cross-cutting requirements.

## Commands

Shipped:

- `browser.list` — list all browser panels in a vibespace
- `browser.open` — open a URL in an embedded browser panel
- `browser.close` — close a browser panel

Deferred (spec'd but not yet implemented):

- `browser.snapshot` — capture the DOM/accessibility tree as text
- `browser.navigate` — navigate an existing browser panel
- `browser.back` — navigate back in history
- `browser.forward` — navigate forward in history
- `browser.reload` — reload the current page
- `browser.eval` — execute JavaScript in the panel
- `browser.click` — click an element
- `browser.type` — fill an input field
- `browser.wait` — block until a page condition is met
- `browser.screenshot` — capture a PNG screenshot of the panel
- `browser.console` — read recent console messages
- `browser.dialog` — accept or dismiss a JS dialog (alert/confirm/prompt)

Browser panels are scoped to the channel client's vibespace. Multiple browser panels per vibespace are supported. See [F012 Browser](../browser/spec.md) for the underlying feature.

---

## `browser.open`

Opens a URL in a new browser panel within the channel client's vibespace.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `url` | string | yes | URL to load. Must include scheme (`http://`, `https://`, `file://`). |
| `vibespace_id` | string | no | Vibespace to open the panel in. Defaults to caller's `CRISPY_VIBESPACE`. |

### Result

| Field | Type | Description |
|---|---|---|
| `browser_id` | string | UUID of the new browser surface |
| `pane_id` | string | UUID of the pane that received the panel |
| `url` | string | URL after browser normalization (may differ from input) |

### Requirements

#### F044-R60: Open routes through BrowserPanelViewModel

`browser.open` MUST go through the same code path used by the user's "New Browser" action so the panel persists in vibespace layout and appears in session restore.

#### F044-R61: URL scheme validation

URLs without a scheme MUST be rejected with `invalid_params`. The CLI does NOT silently prepend `http://`. (Agents are expected to pass full URLs.)

#### F044-R62: Vibespace scoping

The panel MUST be created in the resolved vibespace's pane layout, not in any other vibespace. The browser is project-scoped per [F044-R09](spec.md).

### Scenarios

#### Scenario F044-S140: Open URL in caller's vibespace

**Given** the agent is in a project at `/projects/foo`
**When** the agent invokes `browser.open` with `url: "https://docs.rs/clap"`
**Then** a browser panel opens in the caller's vibespace
**And** the response includes `browser_id` and the loaded URL

#### Scenario F044-S141: Open with missing scheme

**When** the agent invokes `browser.open` with `url: "docs.rs/clap"`
**Then** the response is `invalid_params` with message about missing scheme

#### Scenario F044-S142: Persist across restart

**Given** the agent has opened a browser panel
**When** the user quits and relaunches the app
**Then** the browser panel reopens with the same URL in the same vibespace

---

## `browser.snapshot`

Captures the page as an accessibility tree text representation. Designed for agents — agents cannot consume images, but they can reason over structured DOM text.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `browser_id` | string | no | Browser surface UUID. Defaults to most-recently-active browser panel in caller's vibespace. |
| `interactive` | boolean | no | If true, assigns short ref IDs (e.g. `ref=1`) to clickable elements for use with `browser.click`/`browser.type`. Default false. |

### Result

| Field | Type | Description |
|---|---|---|
| `url` | string | Current URL |
| `title` | string | Document title |
| `tree` | string | Accessibility tree as multi-line text |
| `refs` | object \| null | Map of ref ID → element selector (only when `interactive: true`) |

### Requirements

#### F044-R63: Tree format is human-readable

The `tree` MUST be human-readable text, indented by nesting depth, with element role and visible text on each line. Example:

```
[document]
  [heading level=1] clap
  [paragraph] Command Line Argument Parser for Rust
  [link ref=1 'API docs'] href=/clap/latest
  [textbox ref=2 name='Search'] value=''
  [button ref=3 'Go']
```

#### F044-R64: Ref stability

Ref IDs MUST be stable for the duration of the browser session as long as the page DOM does not change. After navigation or reload, refs from a previous snapshot MUST be considered stale (return `stale_ref` if used by `browser.click`/`browser.type`).

#### F044-R65: Text-only output

The snapshot MUST NOT include base64 image data, computed style values, or other content that would make agent prompts large. Visual-only elements (decorative images, etc.) MAY be omitted.

### Scenarios

#### Scenario F044-S145: Snapshot without refs

**Given** the agent has opened https://docs.rs/clap
**When** the agent invokes `browser.snapshot` without parameters
**Then** the response includes `url`, `title`, and a tree string showing headings, paragraphs, links
**And** `refs` is null

#### Scenario F044-S146: Snapshot with refs

**When** the agent invokes `browser.snapshot` with `interactive: true`
**Then** the tree includes `ref=N` annotations on clickable elements
**And** the `refs` field maps each ref ID to a CSS selector

---

## `browser.navigate`

Navigates an existing browser panel to a new URL.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `url` | string | yes | URL to navigate to. Must include scheme. |
| `browser_id` | string | no | Browser surface UUID. Defaults to most-recently-active browser panel in caller's vibespace. |

### Result

Empty object. The navigation is fire-and-forget; use `browser.wait` to block until load completes.

### Requirements

#### F044-R66: No active panel error

If no browser panel exists in the caller's vibespace and `browser_id` is not provided, the response is `not_connected` with message about creating a panel first.

### Scenarios

#### Scenario F044-S150: Navigate existing panel

**Given** a browser panel is showing https://example.com
**When** the agent invokes `browser.navigate` with `url: "https://docs.rs"`
**Then** the panel begins loading the new URL
**And** the response is `ok: true`

#### Scenario F044-S151: Navigate with no panel

**Given** the caller's vibespace has no browser panels
**When** the agent invokes `browser.navigate` without `browser_id`
**Then** the response is `not_connected`

---

## `browser.eval`

Executes JavaScript in the page and returns the result.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `js` | string | yes | JavaScript expression or statement. |
| `browser_id` | string | no | Defaults to most-recently-active browser panel. |
| `timeout` | number | no | Seconds to wait for evaluation. Default 5. |

### Result

| Field | Type | Description |
|---|---|---|
| `value` | any | JSON-serialized return value of the evaluated JS |
| `type` | string | JS type of the return value (`"string"`, `"number"`, `"boolean"`, `"object"`, `"undefined"`, `"null"`) |

### Requirements

#### F044-R67: Serialization

If the JS expression returns an object, it MUST be serialized via `JSON.stringify` before being returned. Functions, DOM nodes, circular references, etc. become `null` or `"[non-serializable]"`.

#### F044-R68: Eval errors propagate

If the JS throws, the response is `eval_error` with the thrown value's message.

### Scenarios

#### Scenario F044-S155: Eval returning a number

**When** the agent invokes `browser.eval` with `js: "document.querySelectorAll('a').length"`
**Then** the response is `value: <number>`, `type: "number"`

#### Scenario F044-S156: Eval that throws

**When** the agent invokes `browser.eval` with `js: "nonexistent.foo"`
**Then** the response is `eval_error` with the JS error message

#### Scenario F044-S157: Eval returning DOM node

**When** the agent invokes `browser.eval` with `js: "document.body"`
**Then** the response `value` is `null` (DOM nodes are not serializable)
**And** `type: "object"`

---

## `browser.click`

Clicks an element identified by ref (from snapshot) or CSS selector.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `ref` | integer | one of | Ref ID from a recent `browser.snapshot --interactive` call. |
| `selector` | string | one of | CSS selector. Used if `ref` is not provided. |
| `browser_id` | string | no | Defaults to most-recently-active panel. |

Exactly one of `ref` or `selector` MUST be specified.

### Result

Empty object on success.

### Requirements

#### F044-R69: Stale ref detection

If the page has navigated or reloaded since the ref was issued, the response is `stale_ref` with the ref ID.

#### F044-R6A: Element not found

If the selector matches no element, the response is `element_not_found`.

#### F044-R6B: Multiple matches

If the selector matches multiple elements, the click targets the first one in document order. The response includes a warning field `match_count` with the total count.

### Scenarios

#### Scenario F044-S160: Click via ref

**Given** the agent has called `snapshot --interactive` and noted `ref=3` is the Submit button
**When** the agent invokes `browser.click` with `ref: 3`
**Then** the button is clicked

#### Scenario F044-S161: Click via selector

**When** the agent invokes `browser.click` with `selector: "#submit"`
**Then** the matching element is clicked

#### Scenario F044-S162: Stale ref after navigation

**Given** the agent had a snapshot for page A
**And** the page has navigated to page B
**When** the agent invokes `browser.click` with a ref from page A's snapshot
**Then** the response is `stale_ref`

#### Scenario F044-S163: Selector matches nothing

**When** the agent invokes `browser.click` with `selector: "#does-not-exist"`
**Then** the response is `element_not_found`

---

## `browser.type`

Fills an input field with text. Replaces the field's existing content.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `text` | string | yes | Text to type. |
| `ref` | integer | one of | Ref ID from snapshot. |
| `selector` | string | one of | CSS selector. |
| `browser_id` | string | no | Defaults to most-recently-active panel. |
| `submit` | boolean | no | If true, press Enter after typing. Default false. |

### Result

Empty object on success.

### Requirements

#### F044-R6C: Replace existing value

`browser.type` MUST clear the field before typing the new value. To append, use `browser.eval` with field manipulation.

#### F044-R6D: Type only into typable elements

If the targeted element is not an input, textarea, or contenteditable, the response is `invalid_target`.

### Scenarios

#### Scenario F044-S165: Type into input field

**When** the agent invokes `browser.type` with `selector: "#search"` and `text: "clap"`
**Then** the search field's value is `"clap"` (replacing any prior value)

#### Scenario F044-S166: Type and submit

**When** the agent invokes `browser.type` with `selector: "#search"`, `text: "clap"`, `submit: true`
**Then** the field is filled and Enter is pressed
**And** form submission occurs

#### Scenario F044-S167: Type into non-typable element

**When** the agent invokes `browser.type` with `selector: "h1"`
**Then** the response is `invalid_target`

---

## `browser.wait`

Blocks until a page condition is met.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `browser_id` | string | no | Defaults to most-recently-active panel. |
| `url` | string | no | Wait until the page URL contains this substring or matches this pattern. |
| `text` | string | no | Wait until this text appears anywhere in the page. |
| `selector` | string | no | Wait until an element matching this CSS selector exists in the DOM. |
| `load_state` | string | no | One of `"load"`, `"domcontentloaded"`, `"networkidle"`. |
| `timeout` | number | no | Seconds to wait. Default 30. Maximum 600. |

Exactly one of `url`, `text`, `selector`, `load_state` MUST be specified.

### Result

| Field | Type | Description |
|---|---|---|
| `matched` | boolean | True if the condition was met before timeout |
| `url` | string \| null | Final URL when matched |

### Requirements

#### F044-R6E: One condition per call

Multiple wait conditions in a single call MUST return `invalid_params`.

#### F044-R6F: Pre-existing match returns immediately

If the condition is already true at the moment the request is processed (e.g. selector exists in DOM, URL already matches), the response MUST return immediately with `matched: true`.

### Scenarios

#### Scenario F044-S170: Wait for selector

**Given** the agent has just clicked a button that triggers async content load
**When** the agent invokes `browser.wait` with `selector: "#results"`, `timeout: 10`
**Then** when the `#results` element appears in the DOM, the response is `matched: true`

#### Scenario F044-S171: Wait for URL change

**When** the agent invokes `browser.wait` with `url: "/dashboard"`, `timeout: 30`
**Then** when the page navigates to a URL containing `/dashboard`, the response returns

#### Scenario F044-S172: Wait for networkidle

**When** the agent invokes `browser.wait` with `load_state: "networkidle"`, `timeout: 30`
**Then** when the page has had no in-flight network requests for 500ms, the response returns

#### Scenario F044-S173: Wait timeout

**When** the agent invokes `browser.wait` with `selector: "#never-shows"`, `timeout: 5`
**Then** after 5s the response is `matched: false` with error `timeout`

#### Scenario F044-S174: Pre-existing match

**Given** the page already has `#results` in the DOM
**When** the agent invokes `browser.wait` with `selector: "#results"`
**Then** the response returns immediately with `matched: true`


---

## `browser.back`

Navigates back one entry in the browser panel's history.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `browser_id` | string | no | Defaults to most-recently-active panel in caller's vibespace. |

### Result

| Field | Type | Description |
|---|---|---|
| `url` | string | URL after navigation |
| `navigated` | boolean | True if there was a previous entry; false if already at the oldest entry |

### Requirements

#### F044-R6G: Back is a no-op when at history start

If the panel has no back history, the response MUST be `ok: true` with `navigated: false` and the current URL. The CLI MUST NOT raise an error in this case.

### Scenarios

#### Scenario F044-S250: Back from second page

**Given** the panel has visited https://example.com/a then https://example.com/b
**When** the agent invokes `browser.back`
**Then** the panel navigates to https://example.com/a
**And** the response is `navigated: true`, `url: "https://example.com/a"`

#### Scenario F044-S251: Back at oldest history entry

**Given** the panel has only visited one URL since opening
**When** the agent invokes `browser.back`
**Then** the response is `navigated: false`

---

## `browser.forward`

Navigates forward one entry in history. Mirrors `browser.back`.

### Parameters

Same as `browser.back`.

### Result

Same shape as `browser.back`.

### Requirements

#### F044-R6H: Forward is a no-op when at history end

If the panel has no forward history (typical state after a fresh navigation), the response MUST be `ok: true` with `navigated: false`.

### Scenarios

#### Scenario F044-S252: Forward after back

**Given** the agent just called `browser.back`
**When** the agent invokes `browser.forward`
**Then** the panel returns to the URL it was on before the back call

---

## `browser.reload`

Reloads the current page.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `browser_id` | string | no | Defaults to most-recently-active panel. |
| `bypass_cache` | boolean | no | If true, force a hard reload bypassing HTTP cache. Default false. |

### Result

| Field | Type | Description |
|---|---|---|
| `url` | string | URL after reload (same as before unless the page redirects on reload) |

### Requirements

#### F044-R6I: Reload is fire-and-forget

The reload returns once the navigation has been initiated; the response does NOT wait for `load` event. Use `browser.wait load_state: "load"` if the agent needs to block until the new page is ready.

### Scenarios

#### Scenario F044-S253: Reload current page

**When** the agent invokes `browser.reload`
**Then** the page reloads
**And** the response includes the URL

#### Scenario F044-S254: Hard reload

**When** the agent invokes `browser.reload` with `bypass_cache: true`
**Then** the page reloads ignoring cache

---

## `browser.screenshot`

Captures a PNG screenshot of the browser panel viewport. Designed for multimodal agents that can consume images.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `browser_id` | string | no | Defaults to most-recently-active panel. |
| `full_page` | boolean | no | If true, captures the full scrollable page rather than just the visible viewport. Default false. |
| `format` | string | no | `"png"` only in v1. (Reserved for future formats.) Default `"png"`. |

### Result

| Field | Type | Description |
|---|---|---|
| `image_base64` | string | Base64-encoded PNG bytes |
| `width` | integer | Image width in pixels |
| `height` | integer | Image height in pixels |
| `bytes` | integer | Decoded image size |

### Requirements

#### F044-R6J: Size limit

The encoded image MUST NOT exceed 10 MB. If `full_page: true` would produce a larger image, the response is `image_too_large` with the actual dimensions, and the agent SHOULD retry with `full_page: false` or scroll-and-paginate.

#### F044-R6K: PNG-only in v1

`format` other than `"png"` returns `invalid_params`. JPEG and WebP may be added later.

### Scenarios

#### Scenario F044-S255: Capture viewport

**When** the agent invokes `browser.screenshot`
**Then** the response contains a base64 PNG of the visible region
**And** `width` and `height` match the panel's content size

#### Scenario F044-S256: Capture full page

**When** the agent invokes `browser.screenshot` with `full_page: true`
**Then** the response contains the full scrollable page

#### Scenario F044-S257: Image too large

**Given** the page renders to a 50 MB PNG when `full_page: true`
**When** the agent invokes `browser.screenshot` with `full_page: true`
**Then** the response is `image_too_large` with `width`, `height`, and the size that would have been required

---

## `browser.console`

Returns recent console messages from the page (errors, warnings, logs). Useful when `browser.eval` returns unexpected results and the agent needs to diagnose.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `browser_id` | string | no | Defaults to most-recently-active panel. |
| `limit` | integer | no | Max messages to return. Default 50. Max 500. |
| `levels` | array of string | no | Filter to specific levels: `"log"`, `"info"`, `"warn"`, `"error"`. Default returns all levels. |

### Result

| Field | Type | Description |
|---|---|---|
| `messages` | array of ConsoleMessage | Most recent messages first |
| `truncated` | boolean | True if more messages exist than `limit` |

`ConsoleMessage`:

| Field | Type | Description |
|---|---|---|
| `level` | string | `"log"`, `"info"`, `"warn"`, `"error"` |
| `text` | string | Rendered message text |
| `timestamp` | string | ISO-8601 timestamp |
| `source_url` | string \| null | Origin script URL if available |
| `source_line` | integer \| null | Line number if available |

### Requirements

#### F044-R6L: Buffer size

The server MUST keep a rolling buffer of at least 500 console messages per browser panel. Older messages MAY be dropped silently.

#### F044-R6M: Buffer per panel

Each browser panel has its own console buffer. `browser.console` returns only the buffer for the resolved surface.

### Scenarios

#### Scenario F044-S258: Read errors only

**When** the agent invokes `browser.console` with `levels: ["error"]`
**Then** only error-level messages are returned

#### Scenario F044-S259: Truncated when buffer larger than limit

**Given** the panel has 100 console messages
**When** the agent invokes `browser.console` with `limit: 10`
**Then** the response includes 10 most-recent messages
**And** `truncated: true`

---

## `browser.dialog`

Handles a pending JavaScript dialog (`alert`, `confirm`, `prompt`). Until handled, dialogs block all other page interactions.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `browser_id` | string | no | Defaults to most-recently-active panel. |
| `action` | string | yes | `"accept"` or `"dismiss"`. |
| `text` | string | no | For `prompt` dialogs with `action: "accept"`, the text to provide. Ignored for `alert`/`confirm`. |

### Result

| Field | Type | Description |
|---|---|---|
| `dialog_kind` | string | `"alert"`, `"confirm"`, `"prompt"`, or `"beforeunload"` |
| `message` | string | The dialog's message text |
| `handled` | boolean | True if there was a pending dialog and it was handled |

### Requirements

#### F044-R6N: No-op when no dialog pending

If no dialog is currently pending, the response MUST be `ok: true` with `handled: false`. The CLI MUST NOT block waiting for one.

#### F044-R6O: Dialog kind reported

The response MUST include the dialog kind so the agent can verify it handled the right kind of prompt.

### Scenarios

#### Scenario F044-S260: Accept confirm dialog

**Given** the page has triggered `confirm("Are you sure?")`
**When** the agent invokes `browser.dialog` with `action: "accept"`
**Then** the dialog is dismissed with OK
**And** the response includes `dialog_kind: "confirm"`, `message: "Are you sure?"`, `handled: true`

#### Scenario F044-S261: Dismiss prompt dialog

**Given** the page has triggered `prompt("Name?")`
**When** the agent invokes `browser.dialog` with `action: "dismiss"`
**Then** the prompt is cancelled (returns null to the page)

#### Scenario F044-S262: Accept prompt with text

**When** the agent invokes `browser.dialog` with `action: "accept"`, `text: "test"`
**Then** the prompt is accepted with `"test"` as the response

#### Scenario F044-S263: No dialog pending

**Given** no dialog is open
**When** the agent invokes `browser.dialog` with `action: "accept"`
**Then** the response is `ok: true, handled: false`
