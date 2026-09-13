-- Run against the patched upstream panel, without fetching any real images.
local rendered
local requests = {}
local downloads = {}
local applied = {}
local response = {}
local httpOk = true

ui = setmetatable({}, { __index = function(_, kind)
  return function(props, children)
    return { kind = kind, props = props or {}, children = children or {} }
  end
end })
panel = { render = function(tree) rendered = tree end, close = function() end }
noctalia = {
  tr = function(key) return key end,
  getenv = function(key) return key == "HOME" and "/test/home" or "/test/state" end,
  getConfig = function(key) return key == "api_key" and "test-key" or "" end,
  wallpaperDirectory = function() return "/test/wallpapers" end,
  expandPath = function(path) return path end,
  notify = function() end,
  notifyError = function() end,
  string = {
    trim = function(s) return s end,
    urlEncode = function(s) return (s:gsub("[^%w%-_.~]", function(c)
      return string.format("%%%02X", string.byte(c))
    end)) end,
  },
  json = { decode = function(_) return response end },
  http = function(request, callback)
    table.insert(requests, request)
    callback({ ok = httpOk, body = "mock" })
    return true
  end,
  runAsync = function(_, callback) callback({ exitCode = 0 }); return true end,
  download = function(url, destination, callback)
    table.insert(downloads, { url = url, destination = destination })
    callback(true)
    return true
  end,
  setWallpaper = function(path) table.insert(applied, path) end,
}

local function findNode(predicate, node)
  node = node or rendered
  if predicate(node) then return node end
  for _, child in ipairs(node.children) do
    local found = findNode(predicate, child)
    if found then return found end
  end
end

function testSafeSearch()
  local function wallpaper(id, purity)
    return { id = id, purity = purity, resolution = "1920x1080",
      path = "https://example.test/full/" .. id,
      thumbs = { large = "https://example.test/thumb/" .. id } }
  end
  response = { data = {
    wallpaper("safe01", "sfw"), wallpaper("rated1", "sketchy"),
    wallpaper("rated2", "nsfw"), wallpaper("unknown", nil), false,
  }, meta = { last_page = 2 } }
  onOpen({})
  assert(#downloads == 1 and string.find(downloads[1].url, "safe01", 1, true))
  assert(string.find(downloads[1].destination, "/sfw-thumbs/", 1, true))
  assert(findNode(function(n) return n.props.key == "filter_purity_sfw" end).props.enabled == false)
  assert(not findNode(function(n) return n.props.key == "filter_purity_sketchy" or n.props.key == "filter_purity_nsfw" end))
  assert(not findNode(function(n) return n.props.key == "rated1" or n.props.key == "rated2" or n.props.key == "unknown" end))

  -- Applying the accepted result still downloads and sets the wallpaper normally.
  local preview = findNode(function(n) return n.kind == "image" end)
  assert(preview and type(preview.props.onClick) == "function")
  preview.props.onClick()
  assert(#applied == 1 and applied[1] == "/test/wallpapers/wallhaven-safe01.jpg")
  assert(#downloads == 2 and downloads[2].url == "https://example.test/full/safe01")

  -- Neither old handlers, pagination, search parameters nor an API key relax purity.
  onPuritySfw()
  onPuritySketchy()
  onPurityNsfw()
  onNextPage()
  onSearchSubmit("forest&purity=111")
  for _, request in ipairs(requests) do
    assert(string.find(request.url, "&purity=100&", 1, true))
    assert(not string.find(request.url, "&purity=111", 1, true))
  end
  assert(string.find(requests[#requests].url, "q=forest%26purity%3D111", 1, true))
  assert(#downloads == 2, "Rejected results must never download, including thumbnails")

  response = { data = { wallpaper("rated3", "nsfw"), wallpaper("unknown2", "") } }
  onSearchClicked()
  assert(findNode(function(n) return n.props.text == "empty" end))
  assert(not findNode(function(n) return n.kind == "image" end))
  assert(#downloads == 2)

  httpOk = false
  onSearchClicked()
  assert(findNode(function(n) return n.props.text == "error" end))
  assert(#downloads == 2)
  print("OK: SFW requests, response filtering, safe previews/downloads, pagination, API keys and errors")
end
