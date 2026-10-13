# LibChangelog

Interactive update highlights for Retail WoW addons, with a shared multi-addon
window and an embeddable Settings page. Requires LibStub and **LibModernSettings
1.10.0 or newer** (LibStub MINOR 11 in the `LibModernSettings-1.0` API family).

Release `1.0.0` uses the `LibChangelog-1.0` API family with LibStub MINOR `1`.
It targets Retail 12.1.5 and Lua 5.1. It has no standalone
addon TOC and does not own SavedVariables.

## Open all changelogs

Use `/changelog` to browse the latest registered release from every consumer in
one window, including read updates, addons with automatic popups disabled, and
Unreleased previews. It does not enable automatic popups or mark entries as read
just by opening. An existing popup is replaced by this complete list.

Addons can use `LibStub("LibChangelog-1.0"):ShowAll()` for the same behavior. It
returns true, or false plus `not-safe` / `no-consumers`. The normal combat,
loading, cinematic and ready-check restrictions apply; blocked commands explain
why they cannot open rather than queuing a new window.

## Register an addon

Load LibStub, LMS, then `LibChangelog-1.0/embed.xml`. Register after your own
SavedVariables/database initialization, once per addon. Keep the release table
and control definitions immutable after registration.

Bundle both libraries with your addon, even if it uses LMS only for changelogs.
Keep one shared LMS copy at `Libs/LibModernSettings-1.0`, including its `Media`
folder; LibChangelog does not require a second nested copy or another installed
addon. Declare both released pins in the consumer's `.pkgmeta`. Do not rely on
recursive dependency packaging: the [BigWigs packager](https://github.com/BigWigsMods/packager#the-packagemeta-file)
only reads an external library's `.pkgmeta` for ignored files.

```yaml
externals:
    Libs/LibModernSettings-1.0:
        url: https://github.com/KyleCRat/LibModernSettings.git
        tag: 1.10.0
    Libs/LibChangelog-1.0:
        url: https://github.com/KyleCRat/LibChangelog.git
        tag: 1.0.0
```

```lua
local controller = LibStub("LibChangelog-1.0"):Register("MyAddon", {
    displayName = "My Addon",
    storage = {
        get = function(key) return notificationDB:Get(key) end,
        set = function(key, value) notificationDB:Set(key, value) end,
    },
    context = function()
        return activeProfileID, "Changes apply to profile: " .. activeProfileName
    end,
    release = {
        version = "1.2.0",
        date = "2026-10-12",
        title = "Arrange your toolbar",
        highlights = {
            {
                title = "Choose your own button size",
                body = "Adjust the toolbar without leaving these notes.",
                emphasis = "featured",
                controls = {
                    {
                        type = "slider",
                        getValue = function() return settingsDB:Get("buttonSize") end,
                        enabled = function() return true end,
                        options = {
                            label = "Button size",
                            minValue = 20, maxValue = 60, step = 1,
                            onChanged = function(value) ApplyButtonSize(value) end,
                        },
                    },
                },
            },
        },
        notes = {
            { kind = "heading", text = "Added" },
            { kind = "bullet", text = "Adjustable toolbar button size" },
        },
    },
})
```

The `context()` function is optional. Return a stable scalar identity and an
optional label above the highlights; omitting the label reserves no space.
Change the identity when the setting owner is replaced/reset,
not just when a profile's displayed name changes. Call `Refresh()` after such
changes; it cancels old drafts before reading the new owner's values.

Store notification data **account-wide, outside resettable settings profiles**.
The library reads/writes only `autoShow` (nil means true) and
`acknowledgedVersion` (an opaque string). Storage callbacks must persist writes
and must not throw. Do not share this namespace between different addons.

## Controller API

| Method | Behavior |
| --- | --- |
| `CreateSettingsPage(options)` | Returns a Frame using the same renderer as the popup; pass `measurementFrame`, or explicit `width`/`height`, and optional `parent` |
| `Show()` | Manually opens current highlights; returns true or false plus `not-safe` / `batch-open` |
| `Refresh()` | Re-reads bound values, enabled states and context in retained views, without saving settings |
| `GetAutoShowEnabled()` | Returns a boolean |
| `SetAutoShowEnabled(boolean)` | Sets notification consent; re-enabling baselines the current release so only future releases notify |

The addon owns native Settings registration:

```lua
local page = controller:CreateSettingsPage({
    measurementFrame = SettingsPanel:GetSettingsCanvas(),
})
Settings.RegisterCanvasLayoutSubcategory(parentCategory, page, "Changelog")
```

The page exposes `Sync` / `OnRefresh` and `layout`. Showing it refreshes values
but does not acknowledge a release until the player interacts.

## Entries and controls

Highlights are an ordered list. `title` is required; `body`, `emphasis`,
`artwork`, and `controls` are optional. Emphasis is `featured`, `important`, or
`requested` (shown as **USER REQUESTED**); it is independent of whether the entry
has actions. Omit it for an ordinary highlight. Artwork is
`{ texture = pathOrFileID, height = 120 }` or `{ atlas = name, height = 120 }`.

Emphasis adds a small tag without changing the title size. Below the title,
entries with controls place artwork and description on the left and controls
on the right. Entries without controls use the full width for their content.
The popup and embedded Settings page share this layout.

Controls pass `options` to LMS. Supported types and callbacks:

| Type | Consumer callback |
| --- | --- |
| `button` | `options.onClick(button, mouseButton, ...)` |
| `checkbox`, `slider`, `dropdown`, `color` | `options.onChanged(value)` |
| `textInput` | `options.onCommit(text)`; return accepted text or nil/false and an error |

`getValue()` is required for value controls. `enabled()` optionally returns a
boolean and disabled reason. A separate `description` is supported on slider,
dropdown and text-input Fields. Callback arguments and returns are passed
through unchanged, including color mode/custom data and text validation.
Slider track bounds do **not** clamp typed values; the consumer owns genuine
domain limits through LMS's parser/apply logic. Callbacks should use existing
setting validation/persistence/apply functions, never captured profile tables.

All setting/action controls are disabled in combat and revalidated on use.
The automatic-notice checkbox remains independent of gameplay settings.
Use `dismissBatch = true` only on a navigation button: the batch closes before
your callback opens Settings. Normal controls leave the window open.
An optional `successMessage` gives useful completion feedback; avoid it on
sliders or routine checkboxes. Thrown action errors show an error flash and go
to WoW's error handler; they do not escape through LMS's callback stack.

`examples/Controls.lua` is an optional development registration with every
control type; it is not loaded by `embed.xml` or packaged in the runtime.

## Notification behavior

- First installs and changed release IDs notify after world entry and a short
  collection delay. Unreleased (`unreleased = true`) is manual-preview only.
- **Show changelog for ADDON_NAME on login**, beside the addon title, controls future automatic
  notices for that addon. Manual browsing remains available when it is off.
- Every popup keeps the same independently scrollable addon list on the left,
  even for one addon. Alternating rows show the addon's icon beside its name and
  release/unread status. Icons come from `IconTexture` or `IconAtlas` TOC metadata,
  with a question-mark fallback. The first alphabetical addon opens immediately; displaying
  it does not mark it as read.
- Explicit selection, a control interaction, expanding notes or deliberately
  scrolling acknowledges that addon immediately. Hover, reflow, programmatic
  scroll/focus and initial display do not. Failed rendering is not acknowledged.
- **Dismiss all** at the bottom of the addon list, X, or Escape dismisses the
  displayed batch, including unread entries. Escape leaves menus/editors/dialogs
  their own dismissal first.
- Combat, loading, cinematics and ready checks suspend the window without
  dismissing it. The same batch resumes when safe. Later registrations wait
  for another batch. No background polling is used.
- Full notes start collapsed; highlights stay first. A release without highlights
  displays a short update notice and the full-notes expander.
- Compatible embedded copies share one coordinator and update retained
  controllers, bindings and views through persistent prototypes.

## Generate full notes

From the consumer repository, run the bundled development tool with Lua 5.1:

```text
lua Libs/LibChangelog-1.0/tools/generate.lua CHANGELOG.md ReleaseNotes.lua VERSION
lua Libs/LibChangelog-1.0/tools/generate.lua CHANGELOG.md ReleaseNotes.lua VERSION --check
```

It extracts exactly one `## [VERSION]` section and assigns `addon.ReleaseNotes`
using the addon's normal namespace. The result contains version/date/notes and
an Unreleased marker when applicable. Load it before registration, attach your
curated highlights, and bundle it in the consumer's TOC.

Supported Markdown: headings, paragraphs, wrapped bullets, code fences, inline
code/bold and links (including their destinations). Use these forms for notes;
this is not a general Markdown/browser engine. Missing/duplicate/empty release
sections and stale `--check` output fail rather than shipping misleading notes.

## Development and packaging

Run `lua tests/run.lua PATH/TO/LibStub.lua` from this directory. In RCC's embed,
the LibStub path defaults to `../LibStub/LibStub.lua`. Tests cover notification
state, lifecycle, callback/validation returns, owner changes, generator output,
and mixed-MINOR loading. Native geometry, input propagation, hit testing and
secure behavior require an in-game check; see the consumer's authoring guide.

Publish this repository independently before adding a consumer external pin.
Keep its API-family folder `LibChangelog-1.0` when releasing compatible SemVer
versions. Consumers supply LibStub and LMS; no separate installed addon is needed.

Publish LMS 1.10.0 before LibChangelog 1.0.0, then align consumer checkouts and
package pins to those releases or newer. LMS's higher LibStub revision replaces
older same-family embeds regardless of load order.
