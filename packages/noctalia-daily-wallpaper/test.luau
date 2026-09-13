-- Exercise the patched service without downloading real images or setting a desktop.
local values = {}
local files = {}
local downloads = {}
local applied = {}
local requests = {}
local nasaImage = "https://www.nasa.gov/wp-content/uploads/galaxy.jpg"
local nasaFallback = ""
local bingImage = "/th?id=OHR.Forest_EN-US12345"
local deferHttp = false
local pendingHttp

noctalia = {
  getConfig = function(key) return key == "source" and "bing" or "en-US" end,
  setUpdateInterval = function() end,
  expandPath = function(path) return path end,
  wallpaperDirectory = function() return "/test/wallpapers" end,
  mkdirAll = function() return true end,
  fileExists = function(path) return files[path] == true end,
  notify = function() end,
  notifyError = function() end,
  log = function() end,
  tr = function(key) return key end,
  string = { trim = function(s) return s end, urlEncode = function(s) return s end },
  state = { get = function(key) return values[key] end, set = function(key, value) values[key] = value end },
  json = { decode = function(_)
    return { images = {{ urlbase = bingImage, copyright = "Forest (Photographer)", copyrightlink = "https://www.bing.com/" }} }
  end },
  http = function(request, callback)
    table.insert(requests, request.url)
    local body = "bing"
    if request.url == "https://www.nasa.gov/image-of-the-day/" then
      body = 'hds-gallery-item-single hds-gallery-image <img src="' .. nasaImage
        .. '"><div class="hds-gallery-item-caption">A galaxy</div>'
        .. '<meta property="og:image" content="' .. nasaFallback .. '">'
    end
    local result = { ok = true, status = 200, body = body }
    if deferHttp then pendingHttp = function() callback(result) end else callback(result) end
    return true
  end,
  download = function(url, path, callback)
    table.insert(downloads, url)
    files[path] = true
    callback(true)
    return true
  end,
  setWallpaper = function(path) table.insert(applied, path) end,
}

function testDailyService()
  assert(values.status.state == "ready" and values.today.source == "bing")
  assert(#applied == 0, "Enabling a browser must not change the wallpaper")
  assert(#downloads == 1 and downloads[1]:match("^https://www%.bing%.com/th%?id=OHR%."))
  onIpc("apply", "")
  assert(#applied == 1 and applied[1] == values.status.path)

  onIpc("source-nasa", "")
  assert(values.status.state == "ready" and values.today.source == "nasa")
  assert(downloads[#downloads] == nasaImage and #applied == 1)
  onIpc("apply", "")
  assert(#applied == 2 and applied[2] == values.status.path)
  local count = #downloads
  update()
  assert(#downloads == count and #applied == 2, "Background polling must not reapply a wallpaper")

  for _, badUrl in ipairs({ "https://nasa.gov.example.com/picture.jpg", "https://example.com/picture.jpg", "http://www.nasa.gov/picture.jpg" }) do
    nasaImage = badUrl
    onIpc("refresh", "")
    assert(values.status.state == "error" and #downloads == count)
    onIpc("apply", "")
    assert(#applied == 2, "Failed results cannot be applied")
  end
  nasaImage = "https://example.com/picture.jpg"
  nasaFallback = "https://images-assets.nasa.gov/image/space/space.jpg"
  onIpc("refresh", "")
  assert(values.status.state == "ready" and downloads[#downloads] == nasaFallback)

  count = #downloads
  bingImage = "/images/search?q=anything"
  onIpc("source-bing", "")
  assert(values.status.state == "error" and #downloads == count, "Bing must stay on its editorial image endpoint")
  bingImage = "/th?id=OHR.Forest_EN-US12345"
  deferHttp = true
  onIpc("refresh", "")
  assert(values.status.state == "checking")
  onIpc("source-nasa", "")
  onIpc("apply", "")
  assert(#applied == 2)
  pendingHttp()
  assert(values.status.source == "bing", "A concurrent provider click must not mix sources")
  assert(#applied == 2)
  deferHttp = false
  count = #requests
  onIpc("arbitrary-source", "https://example.com/")
  assert(#requests == count)
  print("OK: Bing/NASA editorial feeds, explicit apply, trusted image URLs, error and in-flight handling")
end
