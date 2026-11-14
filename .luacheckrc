-- WoW addons run on Lua 5.1. The client's API is thousands of globals, so reading an
-- undefined global (113) isn't flagged; *writing* one is, because a leaked global is how
-- an addon taints Blizzard's UI.
std = "lua51"
max_line_length = false
exclude_files = {"Flipper/Data/*.lua"}
ignore = {
    "113",      -- reading an undefined global (the WoW API)
    "212",      -- unused argument (event handlers, callbacks)
    "211/_.*",  -- unused locals named _something
    "213",      -- unused loop variable
    "542",      -- empty if branch
}
-- Globals Flipper is meant to write: saved variables and the slash command.
globals = {"FlipperDB", "FlipperCharDB", "SLASH_FLIPPER1", "SLASH_FLIPPER2", "SlashCmdList"}
-- Test files reuse short names (r, price) from one case to the next.
files["tests/"] = {ignore = {"431"}}
