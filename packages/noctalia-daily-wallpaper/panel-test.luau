local rendered
local commands = {}
local values = {
  today = { source = "bing", title = "Forest", credit = "Photographer" },
  status = { state = "ready", source = "bing", path = "/test/preview.jpg" },
}
ui = setmetatable({}, { __index = function(_, kind)
  return function(props, children) return { kind = kind, props = props or {}, children = children or {} } end
end })
panel = { render = function(tree) rendered = tree end, close = function() end }
noctalia = {
  tr = function(key) return key end,
  state = { get = function(key) return values[key] end, watch = function() end },
  runAsync = function(command) table.insert(commands, command); return true end,
  notifyError = function() end,
}
local function findNode(predicate, node)
  node = node or rendered
  if predicate(node) then return node end
  for _, child in ipairs(node.children) do
    local found = findNode(predicate, child)
    if found then return found end
  end
end
function testDailyPanel()
  onOpen({})
  assert(#commands == 0)
  assert(findNode(function(n) return n.kind == "image" and n.props.path == "/test/preview.jpg" end))
  assert(findNode(function(n) return n.props.onClick == "onApply" end))
  onNasa()
  assert(commands[1] == "noctalia msg plugin 'nzlov/daily-wallpaper:service' all source-nasa")
  onApply()
  assert(commands[2] == "noctalia msg plugin 'nzlov/daily-wallpaper:service' all apply")
  values.status.state = "checking"
  onOpen({})
  assert(findNode(function(n) return n.props.onClick == "onNasa" end).props.enabled == false)
  assert(not findNode(function(n) return n.kind == "image" end))
  assert(not findNode(function(n) return n.props.onClick == "onApply" end))
  values.status = { state = "error", message = "Network failed" }
  onOpen({})
  assert(findNode(function(n) return n.props.text == "Network failed" end))
  assert(not findNode(function(n) return n.kind == "image" end))
  print("OK: provider selection, preview, manual application and loading/error views")
end
