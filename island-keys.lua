-- Keyboard (and blur) for the Dynamic Island, Control Center and
-- Notification Center. Load from ~/.config/hypr/hyprland.lua:
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.himanshu-mlshra.dynamic-island/island-keys.lua")
--
-- To change a shortcut, set it before the dofile line, e.g.
--   island_keys = { notification_center = "SUPER + ALT + N" }
-- (set one to false to leave it unbound).
--
-- While any panel is open the bar puts Hyprland in the "island" submap, so
-- Escape / Tab reach the shell. If the shell is not running, the key still
-- leaves the submap, so the keyboard can never be stranded in it.

local keys = {
  island = "SUPER + B",                  -- open / close the island
  control_center = "SUPER + ALT + C",    -- open / close Control Center
  notification_center = "SUPER + N",     -- open / close Notification Center
}
for k, v in pairs(rawget(_G, "island_keys") or {}) do keys[k] = v end

local function island(action)
  return hl.dsp.exec_cmd("omarchy-shell omarchy.bar island " .. action
    .. " >/dev/null 2>&1 || hyprctl dispatch 'hl.dsp.submap(\"reset\")'")
end

local global = {
  { keys.island, "Dynamic Island", "toggle" },
  { keys.control_center, "Control Center", "cc" },
  { keys.notification_center, "Notification Center", "nc" },
}
for _, b in ipairs(global) do
  if b[1] then o.bind(b[1], b[2], island(b[3])) end
end

-- Omarchy's own panel shortcuts open popups of the stock bar, which this
-- island replaces, so they did nothing. Point them at the island's panes.
local remap = {
  { "SUPER + CTRL + W", "Network", "toggle:network" },
  { "SUPER + CTRL + B", "Bluetooth", "toggle:bluetooth" },
  { "SUPER + CTRL + D", "Display", "toggle:display" },
  { "SUPER + CTRL + A", "Audio", "toggle:audio" },
  { "SUPER + CTRL + ALT + D", "Calendar", "nc" },
}
if rawget(_G, "island_remap_omarchy") ~= false then
  for _, b in ipairs(remap) do
    hl.unbind(b[1])
    o.bind(b[1], b[2], island(b[3]))
  end
end

hl.define_submap("island", function()
  hl.bind("ESCAPE", island("back"))
  hl.bind("TAB", island("page:next"))
  hl.bind("RIGHT", island("page:next"))
  hl.bind("SHIFT + TAB", island("page:prev"))
  hl.bind("LEFT", island("page:prev"))
  -- The same shortcuts work from inside the submap (switch panel or close).
  for _, b in ipairs(global) do
    if b[1] then hl.bind(b[1], island(b[3])) end
  end
end)

-- Frosted glass behind the Notification Center panel. ignore_alpha keeps the
-- transparent rest of its full-screen surface unblurred.
hl.layer_rule({ match = { namespace = "^omarchy-island-nc$" }, blur = true, ignore_alpha = 0.3 })
