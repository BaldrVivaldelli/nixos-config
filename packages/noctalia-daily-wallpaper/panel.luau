--!nonstrict
-- Both providers use their editorial daily feeds. Applying a preview is explicit.
local function tr(key) return noctalia.tr(key) end
local render
local COMMANDS = {
  bing = "noctalia msg plugin 'nzlov/daily-wallpaper:service' all source-bing",
  nasa = "noctalia msg plugin 'nzlov/daily-wallpaper:service' all source-nasa",
  refresh = "noctalia msg plugin 'nzlov/daily-wallpaper:service' all refresh",
  apply = "noctalia msg plugin 'nzlov/daily-wallpaper:service' all apply",
}

local function request(action)
  if not noctalia.runAsync(COMMANDS[action]) then
    noctalia.notifyError(tr("panel.title"), tr("panel.error"))
  end
end

render = function()
  local today = noctalia.state.get("today") or {}
  local status = noctalia.state.get("status") or {}
  local loading = status.state == "checking"
  local ready = (status.state == "ready" or status.state == "applied")
    and type(status.path) == "string" and status.source == today.source
  local selected = status.source or today.source or "bing"
  local rows = {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "Bing / NASA", fontSize = 18, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", onClick = "onRefresh", enabled = not loading }),
      ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
    }),
    ui.row({ gap = 8 }, {
      ui.button({ text = "Bing", variant = selected == "bing" and "primary" or "outline", onClick = "onBing", enabled = not loading }),
      ui.button({ text = "NASA", variant = selected == "nasa" and "primary" or "outline", onClick = "onNasa", enabled = not loading }),
    }),
    ui.label({ text = tr("panel.editorial_hint"), maxWidth = 364, maxLines = 2, fontSize = 12, color = "on_surface_variant" }),
  }
  if ready then
    table.insert(rows, ui.image({ path = status.path, width = 364, height = 205, fit = "cover", radius = 10 }))
    table.insert(rows, ui.label({ text = today.title or "", maxWidth = 364, maxLines = 3, fontWeight = "medium" }))
    if today.credit and today.credit ~= "" then
      table.insert(rows, ui.label({ text = today.credit, maxWidth = 364, maxLines = 2, fontSize = 12, color = "on_surface_variant" }))
    end
    table.insert(rows, ui.row({ gap = 8 }, {
      ui.button({ text = tr("panel.apply"), variant = "primary", onClick = "onApply" }),
      ui.button({ text = tr("panel.source"), variant = "ghost", onClick = "onOpenLink" }),
    }))
    if status.state == "applied" then
      table.insert(rows, ui.label({ text = tr("notify.applied"), fontSize = 12, color = "on_surface_variant" }))
    end
  else
    local message = status.state == "error" and (status.message or tr("panel.error")) or tr("panel.loading")
    table.insert(rows, ui.label({ text = message, maxWidth = 364, maxLines = 4, color = status.state == "error" and "error" or "on_surface_variant" }))
  end
  panel.render(ui.column({ padding = 14, gap = 10, flexGrow = 1 }, {
    ui.scroll({ gap = 12, flexGrow = 1 }, rows),
  }))
end

function onOpen(_context) render() end
function onCloseClicked() panel.close() end
function onRefresh() request("refresh") end
function onBing() request("bing") end
function onNasa() request("nasa") end
function onApply() request("apply") end
function onOpenLink()
  local today = noctalia.state.get("today") or {}
  local command = today.source == "nasa"
    and "xdg-open 'https://www.nasa.gov/image-of-the-day/'"
    or "xdg-open 'https://www.bing.com/'"
  noctalia.runAsync(command)
end

noctalia.state.watch("today", render)
noctalia.state.watch("status", render)
