local Markdown = dofile("tools/Markdown.lua")
local source = [==[# Changelog

## [Unreleased]
- Not released

## [opaque-version] - 2026-10-12
### Added
- A **wrapped** change with `code`
  and [a link](https://example.test).

Text with "quotes", \slashes, and ]] or ]=].

```lua
print("example")
```

## [old-version]
- Do not include
]==]
local release = Markdown.Extract(source:gsub("\n", "\r\n"), "opaque-version")
assert(release.date == "2026-10-12" and not release.unreleased)
assert(#release.notes == 4 and release.notes[1].kind == "heading")
assert(release.notes[2].text == "A wrapped change with code and a link (https://example.test).")
assert(release.notes[4].kind == "code" and release.notes[4].text == 'print("example")')
local generated = Markdown.Generate(release)
local addon = {}
assert(loadstring(generated))("Example", addon)
assert(addon.ReleaseNotes.version == "opaque-version")
assert(addon.ReleaseNotes.notes[3].text == release.notes[3].text, "Lua literals round-trip safely")
assert(not generated:find("Do not include", 1, true))
assert(Markdown.Extract(source, "Unreleased").unreleased)
assert(not pcall(Markdown.Extract, source, "absent"))
assert(not pcall(Markdown.Extract, source .. "\n## [old-version]\n- duplicate", "old-version"))
assert(not pcall(Markdown.Generate, release, "x; error()"))
