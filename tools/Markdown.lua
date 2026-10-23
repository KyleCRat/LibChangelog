local Markdown = {}

local function plainText(text)
    -- Changelogs use a small Markdown subset. Keep link destinations and code
    -- contents; remove only presentation delimiters unsupported by FontStrings.
    return text:gsub("%[([^%]]+)%]%(([^%)]+)%)", "%1 (%2)")
        :gsub("`([^`]+)`", "%1")
        :gsub("%*%*([^*]+)%*%*", "%1")
end

function Markdown.Extract(source, version)
    assert(
        type(version) == "string" and version ~= "",
        "a release version is required"
    )
    source = source:gsub("^\239\187\191", ""):gsub("\r\n", "\n")

    local release = {
        version = version,
        notes = {},
        unreleased = version:lower() == "unreleased",
    }
    local found, active, fenced = false, false, false
    local pending

    local function flush()
        if not pending then return end

        if pending.kind ~= "code" then
            pending.text = plainText(pending.text)
        end

        release.notes[#release.notes + 1] = pending
        pending = nil
    end

    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        local heading = not fenced
            and (
                line:match("^## %[(.-)%]") or line:match("^## (Unreleased)%s*$")
            )

        if heading then
            flush()
            active = heading == version

            if active then
                assert(not found, "duplicate release heading: " .. version)
                found = true
                release.date = line:match("(%d%d%d%d%-%d%d%-%d%d)")
            end
        elseif active then
            if line:match("^```") then
                if fenced then
                    flush()
                    fenced = false
                else
                    flush()
                    fenced = true
                    pending = { kind = "code", text = "" }
                end
            elseif fenced then
                pending.text = pending.text == "" and line
                    or (pending.text .. "\n" .. line)
            elseif line:match("^%s*$") then
                flush()
            else
                local section = line:match("^###+%s+(.+)")
                local bullet = line:match("^%s*[-*]%s+(.+)")

                if section then
                    flush()
                    release.notes[#release.notes + 1] =
                        { kind = "heading", text = plainText(section) }
                elseif bullet then
                    flush()
                    pending = { kind = "bullet", text = bullet }
                elseif pending then
                    pending.text = pending.text
                        .. " "
                        .. line:match("^%s*(.-)%s*$")
                else
                    pending = { kind = "paragraph", text = line }
                end
            end
        end
    end

    assert(not fenced, "unclosed code fence in " .. version)
    flush()
    assert(found, "release not found: " .. version)
    assert(#release.notes > 0, "release has no notes: " .. version)

    return release
end

local function quote(value)
    value = value
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
    return '"' .. value .. '"'
end

function Markdown.Generate(release, field)
    field = field or "ReleaseNotes"
    assert(
        field:match("^[%a_][%w_]*$"),
        "output field must be a Lua identifier"
    )

    local lines = {
        "-- Generated from CHANGELOG.md; do not edit by hand.",
        "local _, addon = ...",
        "",
        "addon." .. field .. " = {",
        "    version = " .. quote(release.version) .. ",",
    }

    if release.unreleased then lines[#lines + 1] = "    unreleased = true," end

    if release.date then
        lines[#lines + 1] = "    date = " .. quote(release.date) .. ","
    end

    lines[#lines + 1] = "    notes = {"

    for _, block in ipairs(release.notes) do
        lines[#lines + 1] = "        { kind = "
            .. quote(block.kind)
            .. ", text = "
            .. quote(block.text)
            .. " },"
    end

    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    return table.concat(lines, "\n")
end

return Markdown
