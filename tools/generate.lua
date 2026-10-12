-- Usage: lua tools/generate.lua CHANGELOG.md Output.lua VERSION [--check]
local directory = arg[0]:match("^(.*[/\\])") or ""
local Markdown = dofile(directory .. "Markdown.lua")
local inputPath, outputPath, version, mode = unpack(arg)
assert(inputPath and outputPath and version,
    "Usage: lua tools/generate.lua CHANGELOG.md Output.lua VERSION [--check]")
assert(mode == nil or mode == "--check", "the only optional argument is --check")

local input = assert(io.open(inputPath, "rb"))
local source = input:read("*a")
input:close()

local release = Markdown.Extract(source, version)
local generated = Markdown.Generate(release)

if mode == "--check" then
    local output = assert(io.open(outputPath, "rb"))
    local current = output:read("*a")
    output:close()
    assert(current == generated, "bundled release notes are stale; run the generator without --check")
    print("Bundled changelog matches " .. version)
else
    local output = assert(io.open(outputPath, "wb"))
    assert(output:write(generated))
    assert(output:close())
    print("Generated " .. outputPath .. " for " .. version)
end
