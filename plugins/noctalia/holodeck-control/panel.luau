--!nonstrict

-- Keep this map closed: UI values select a predeclared command and are never
-- interpolated into a shell string. Only holodeckctl is allowed to write IR.
-- Nix replaces this exact token with the immutable backend wrapper store path.
local CONFIGCTL = "@holodeckctl@"
local COMMANDS = {
  status = CONFIGCTL .. " --json status",
  init = CONFIGCTL .. " --json init",
  targetHome = CONFIGCTL .. " --json set deployment.target home-manager",
  targetExisting = CONFIGCTL .. " --json set deployment.target existing-nixos",
  modeDark = CONFIGCTL .. " --json set appearance.theme.mode dark",
  modeLight = CONFIGCTL .. " --json set appearance.theme.mode light",
  rdpModeHalf = CONFIGCTL .. " --json set integrations.windows.rdp.displayMode half",
  rdpModeFullscreen = CONFIGCTL .. " --json set integrations.windows.rdp.displayMode fullscreen",
  plan = CONFIGCTL .. " --json plan",
  apply = CONFIGCTL .. " apply",
  holodeckSetup = CONFIGCTL .. " action holodeck-setup",
  holodeckDoctor = CONFIGCTL .. " action holodeck-doctor",
  githubSetup = CONFIGCTL .. " action github-setup",
  gitlabSetup = CONFIGCTL .. " action gitlab-setup",
  awsSync = CONFIGCTL .. " action aws-sync",
  awsLogin = CONFIGCTL .. " action aws-login",
  awsProfileSelect = CONFIGCTL .. " --json aws-profile-select",
  applyDark = CONFIGCTL .. " apply-change theme-dark",
  applyLight = CONFIGCTL .. " apply-change theme-light",
  applyUser = CONFIGCTL .. " apply-change scope-user",
  applySystem = CONFIGCTL .. " apply-change scope-system",
  applySaved = CONFIGCTL .. " apply-change saved",
  awsAliasesApply = CONFIGCTL .. " --json aws-aliases-apply",
  windowsUp = CONFIGCTL .. " action windows-up",
  windowsStatus = CONFIGCTL .. " action windows-status",
  windowsRdp = CONFIGCTL .. " action windows-rdp",
  windowsUnlock = CONFIGCTL .. " action windows-unlock",
  windowsPasswordReset = CONFIGCTL .. " action windows-password-reset",
  windowsWipe = CONFIGCTL .. " action windows-wipe",
  windowsWeb = CONFIGCTL .. " action windows-web",
  windowsLogs = CONFIGCTL .. " action windows-logs",
  windowsDown = CONFIGCTL .. " action windows-down",
}

local targetOptions = {
  noctalia.tr("panel.target.home_manager"),
  noctalia.tr("panel.target.existing_nixos"),
}
local modeOptions = {
  noctalia.tr("panel.mode.dark"),
  noctalia.tr("panel.mode.light"),
}
local rdpDisplayModeOptions = {
  noctalia.tr("panel.integrations.windows.display_half"),
  noctalia.tr("panel.integrations.windows.display_fullscreen"),
}

local backendAvailable = false
local busy = false
local statusExists = false
local selectedTargetIndex = 0
local selectedModeIndex = 0
local selectedRdpDisplayModeIndex = 0
local rdpUsername = "Docker"
local rdpPassword = ""
local rdpPasswordRevision = 0
local rdpCredentialRequestPath = ""
local persistedTarget = "home-manager"
local persistedMode = "dark"
local irPath = ""
local statusSource = ""
local dirty = true
local notice = ""
local currentError = ""
local planSummary = ""
local pendingPlan = nil
local confirmingApply = false
local confirmingWindowsUnlock = false
local confirmingWindowsPasswordReset = false
local confirmingWindowsWipe = false
local windowsCredentialEditorOpen = false
local windowsWipeConfirmation = ""
local windowsWipeConfirmationRevision = 0
local activeView = "overview"
local activeIntegration = "github"
local awsAliasEditorOpen = false
local awsAliasDraft = {}
local awsRegionDraft = {}
local awsAliasRevision = {}
local awsAliasRequestPath = ""
local awsSyncPolling = false
local awsSyncPollInFlight = false
local awsSyncPollCount = 0
local AWS_SYNC_POLL_LIMIT = 150
local integrations = {
  aws = { aliases = {}, available = false, configured = false, profiles = {} },
  github = { available = false, configured = false, profiles = {} },
  gitlab = { available = false, configured = false, profiles = {} },
  windowsVm = {
    available = false,
    configured = false,
    credentialStored = false,
    credentialUsername = "",
    rdpResilience = false,
  },
}

local render

local function awsRegionDraftValue(assignment)
  local regions = type(assignment.regions) == "table" and assignment.regions or {}
  return table.concat(regions, ", ")
end

local function resetAwsAliasDraft()
  awsAliasDraft = {}
  awsRegionDraft = {}
  awsAliasRevision = {}
  local aws = integrations.aws or {}
  local aliases = type(aws.aliases) == "table" and aws.aliases or {}
  for _, assignment in ipairs(aliases) do
    if type(assignment) == "table"
      and type(assignment.key) == "string"
      and type(assignment.alias) == "string"
      and type(assignment.regions) == "table"
      and type(assignment.suggestedRegions) == "table" then
      awsAliasDraft[assignment.key] = assignment.alias
      awsRegionDraft[assignment.key] = awsRegionDraftValue(assignment)
      awsAliasRevision[assignment.key] = 0
    end
  end
end

local function tr(key, substitutions)
  if substitutions == nil then
    return noctalia.tr(key)
  end
  return noctalia.tr(key, substitutions)
end

local function selectedTarget()
  if selectedTargetIndex == 1 then
    return "existing-nixos"
  end
  return "home-manager"
end

local function selectedMode()
  if selectedModeIndex == 1 then
    return "light"
  end
  return "dark"
end

local function recomputeDirty()
  dirty = not statusExists
    or selectedTarget() ~= persistedTarget
    or selectedMode() ~= persistedMode
end

local function setSelectionsFromIr(ir)
  if type(ir) ~= "table" then
    return
  end

  local deployment = ir.deployment
  if type(deployment) == "table" then
    if deployment.target == "existing-nixos" then
      selectedTargetIndex = 1
      persistedTarget = "existing-nixos"
    elseif deployment.target == "home-manager" then
      selectedTargetIndex = 0
      persistedTarget = "home-manager"
    end
  end

  local appearance = ir.appearance
  local theme = type(appearance) == "table" and appearance.theme or nil
  if type(theme) == "table" then
    if theme.mode == "light" then
      selectedModeIndex = 1
      persistedMode = "light"
    elseif theme.mode == "dark" then
      selectedModeIndex = 0
      persistedMode = "dark"
    end
  end

  local irIntegrations = ir.integrations
  local windows = type(irIntegrations) == "table" and irIntegrations.windows or nil
  local rdp = type(windows) == "table" and windows.rdp or nil
  if type(rdp) == "table" then
    if rdp.displayMode == "fullscreen" then
      selectedRdpDisplayModeIndex = 1
    elseif rdp.displayMode == "half" then
      selectedRdpDisplayModeIndex = 0
    end
  end
end

local function payloadError(payload)
  if type(payload) ~= "table" then
    return nil
  end
  if type(payload.error) == "string" and payload.error ~= "" then
    return payload.error
  end
  if type(payload.error) == "table" and type(payload.error.message) == "string" then
    return payload.error.message
  end
  return nil
end

local function decodeCommandResult(result)
  if result.timedOut == true then
    return nil, tr("error.timeout")
  end

  local stdout = noctalia.string.trim(result.stdout or "")
  local stderr = noctalia.string.trim(result.stderr or "")
  local raw = stdout ~= "" and stdout or stderr
  local payload, decodeError = noctalia.json.decode(raw)
  local reportedError = payloadError(payload)

  if result.exitCode ~= 0 then
    return nil, reportedError or (stderr ~= "" and stderr or raw)
  end
  if payload == nil then
    return nil, tr("error.invalid_json", { detail = tostring(decodeError or "") })
  end
  if payload.ok ~= true then
    return nil, reportedError or tr("error.backend_rejected")
  end
  return payload, nil
end

local function fail(message)
  busy = false
  confirmingApply = false
  confirmingWindowsPasswordReset = false
  confirmingWindowsWipe = false
  currentError = message ~= nil and tostring(message) or tr("error.unknown")
  notice = ""
  render()
end

local function runAllowed(action, onSuccess)
  local command = COMMANDS[action]
  if command == nil then
    fail(tr("error.command_not_allowed"))
    return
  end

  local accepted = noctalia.runAsync(command, function(result)
    local payload, err = decodeCommandResult(result)
    if payload == nil then
      fail(err)
      return
    end
    onSuccess(payload)
  end)

  if not accepted then
    fail(tr("error.command_not_started"))
  end
end

local function openTerminalAction(action)
  local command = COMMANDS[action]
  if command == nil then fail(tr("error.command_not_allowed")); return end
  if noctalia.runInTerminal(command) then
    notice = tr("ux.terminal_started")
    currentError = ""
  else
    notice = ""
    currentError = tr("error.terminal_not_started")
  end
  render()
end

local function openGraphicalAction(action)
  local command = COMMANDS[action]
  if command == nil then
    fail(tr("error.command_not_allowed"))
    return
  end

  local opened = noctalia.runAsync(command)
  if opened then
    notice = tr("notice.graphical_action_started")
    currentError = ""
  else
    notice = ""
    currentError = tr("error.command_not_started")
  end
  render()
end

local function clearWindowsRdpPassword()
  rdpPassword = ""
  rdpPasswordRevision = rdpPasswordRevision + 1
  confirmingWindowsUnlock = false
  confirmingWindowsPasswordReset = false
  confirmingWindowsWipe = false
  windowsCredentialEditorOpen = false
  windowsWipeConfirmation = ""
  windowsWipeConfirmationRevision = windowsWipeConfirmationRevision + 1
end

local function windowsRdpCredentialsReady()
  return rdpCredentialRequestPath ~= ""
    and rdpUsername ~= ""
    and rdpPassword ~= ""
    and string.find(rdpUsername, "\n", 1, true) == nil
    and string.find(rdpUsername, "\r", 1, true) == nil
    and string.find(rdpPassword, "\n", 1, true) == nil
    and string.find(rdpPassword, "\r", 1, true) == nil
end

local function prepareWindowsCredentials(requirePassword)
  if rdpPassword == "" then
    if rdpCredentialRequestPath ~= "" then
      noctalia.removeFile(rdpCredentialRequestPath)
    end
    if requirePassword then
      fail(tr("error.rdp_credentials_required"))
      return false
    end
    return true
  end
  if rdpCredentialRequestPath == "" then
    fail(tr("error.rdp_request_unavailable"))
    return false
  end
  if not windowsRdpCredentialsReady() then
    fail(tr("error.rdp_credentials_required"))
    return false
  end

  local encoded, encodeError = noctalia.json.encode({
    schemaVersion = 1,
    createdAtMs = noctalia.nowMs(),
    username = rdpUsername,
    password = rdpPassword,
  })
  if type(encoded) ~= "string" then
    fail(tr("error.rdp_request_failed", { detail = tostring(encodeError or "") }))
    return false
  end
  local written, writeError = noctalia.writeFile(rdpCredentialRequestPath, encoded)
  if written ~= true then
    fail(tr("error.rdp_request_failed", { detail = tostring(writeError or "") }))
    return false
  end
  return true
end

local function openWindowsRdpAction(action)
  local command = COMMANDS[action]
  if command == nil then
    fail(tr("error.command_not_allowed"))
    return
  end
  local integration = integrations.windowsVm or {}
  if not prepareWindowsCredentials(integration.credentialStored ~= true and integration.installed ~= true) then
    return
  end

  notice = tr("ux.windows_opening")
  currentError = ""
  local opened = noctalia.runAsync(command, function(result)
    if result.exitCode ~= 0 then
      local detail = noctalia.string.trim(result.stderr or "")
      if detail == "" then detail = noctalia.string.trim(result.stdout or "") end
      activeView = "windows"
      fail(tr("ux.windows_failed", { detail = string.sub(detail, -1000) }))
    else
      notice = tr("ux.windows_finished")
      currentError = ""
      render()
    end
  end)
  if opened then
    clearWindowsRdpPassword()
  else
    noctalia.removeFile(rdpCredentialRequestPath)
    notice = ""
    currentError = tr("error.command_not_started")
  end
  render()
end

local function openWindowsUnlockAction()
  local command = COMMANDS.windowsUnlock
  if command == nil then
    fail(tr("error.command_not_allowed"))
    return
  end
  if not prepareWindowsCredentials(false) then
    return
  end

  confirmingWindowsUnlock = false
  local opened = noctalia.runInTerminal(command)
  if opened then
    notice = tr("notice.windows_unlock_started")
    currentError = ""
  else
    noctalia.removeFile(rdpCredentialRequestPath)
    notice = ""
    currentError = tr("error.terminal_not_started")
  end
  render()
end

local function openWindowsPasswordResetAction()
  local command = COMMANDS.windowsPasswordReset
  if command == nil then
    fail(tr("error.command_not_allowed"))
    return
  end
  if not prepareWindowsCredentials(true) then
    return
  end

  confirmingWindowsPasswordReset = false
  local opened = noctalia.runInTerminal(command)
  if opened then
    notice = tr("notice.windows_password_reset_started")
    currentError = ""
  else
    noctalia.removeFile(rdpCredentialRequestPath)
    notice = ""
    currentError = tr("error.terminal_not_started")
  end
  render()
end

local function openWindowsWipeAction()
  local command = COMMANDS.windowsWipe
  if command == nil then
    fail(tr("error.command_not_allowed"))
    return
  end
  if not prepareWindowsCredentials(true) then
    return
  end

  confirmingWindowsWipe = false
  windowsWipeConfirmation = ""
  windowsWipeConfirmationRevision = windowsWipeConfirmationRevision + 1
  local opened = noctalia.runInTerminal(command)
  if opened then
    notice = tr("notice.windows_wipe_started")
    currentError = ""
  else
    noctalia.removeFile(rdpCredentialRequestPath)
    notice = ""
    currentError = tr("error.terminal_not_started")
  end
  render()
end

local function applyStatusPayload(payload)
  statusExists = payload.exists == true
  irPath = type(payload.irPath) == "string" and payload.irPath or ""
  statusSource = type(payload.source) == "string" and payload.source or ""
  if type(payload.integrations) == "table" then
    integrations = payload.integrations
    resetAwsAliasDraft()
    local windows = integrations.windowsVm or {}
    if windows.credentialStored == true then
      if type(windows.credentialUsername) == "string" and windows.credentialUsername ~= "" then
        rdpUsername = windows.credentialUsername
      end
      rdpPassword = ""
      rdpPasswordRevision = rdpPasswordRevision + 1
      windowsCredentialEditorOpen = false
    end
  end
  setSelectionsFromIr(payload.ir or payload.effective)
  recomputeDirty()
end

local function loadStatus(reportSuccess)
  if busy then
    return
  end

  backendAvailable = noctalia.fileExists(CONFIGCTL)
  currentError = ""
  notice = ""
  planSummary = ""
  pendingPlan = nil
  confirmingApply = false

  if not backendAvailable then
    currentError = tr("error.backend_missing")
    render()
    return
  end

  busy = true
  render()
  runAllowed("status", function(payload)
    applyStatusPayload(payload)
    busy = false
    notice = reportSuccess == true and tr("notice.status_loaded") or ""
    render()
  end)
end

local function awsAliasRecords(integration)
  if type(integration) ~= "table" or type(integration.aliases) ~= "table" then
    return {}
  end
  local records = {}
  for _, assignment in ipairs(integration.aliases) do
    if type(assignment) == "table"
      and type(assignment.key) == "string"
      and type(assignment.accountName) == "string"
      and type(assignment.roleName) == "string"
      and type(assignment.regions) == "table"
      and type(assignment.suggestedRegions) == "table"
      and type(assignment.profiles) == "table"
      and type(assignment.alias) == "string"
      and type(assignment.defaultAlias) == "string"
      and type(assignment.suggestedAlias) == "string" then
      table.insert(records, assignment)
    end
  end
  return records
end

local function parseAwsRegionDraft(value)
  local regions = {}
  local seen = {}
  for region in string.gmatch(string.lower(tostring(value or "")), "[a-z0-9-]+") do
    if seen[region] ~= true then
      seen[region] = true
      table.insert(regions, region)
    end
  end
  return regions
end

local searchQuery = ""
local profileQuery = ""
local selectedAliasKey = ""
local awsProfileRequestPath = ""
local awsLoginAfterSelect = false
local pendingAwsSetup = false
local statusPollInFlight = false
local panelIsOpen = false
local dispatch

local function button(text, callback, glyph, variant, enabled)
  return ui.button({
    text = text, glyph = glyph, variant = variant or "ghost", controlSize = "md",
    contentAlign = "start", enabled = enabled ~= false and backendAvailable and not busy,
    onClick = callback,
  })
end

local function label(text, secondary)
  return ui.label({ text = text, color = secondary and "on_surface_variant" or "on_surface", fontSize = secondary and 12 or 14, maxLines = 3 })
end

local function group(title, children)
  local nodes = { ui.label({ text = title, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }) }
  for _, node in ipairs(children) do table.insert(nodes, node) end
  return ui.column({ gap = 8, flexGrow = 1 }, nodes)
end

local TASKS = {
  { id = "aws", glyph = "cloud", section = "work" },
  { id = "windows", glyph = "device-desktop", section = "work" },
  { id = "github", glyph = "brand-github", section = "work" },
  { id = "gitlab", glyph = "brand-gitlab", section = "work" },
  { id = "theme", glyph = "sun", section = "equipment" },
  { id = "scope", glyph = "device-desktop-cog", section = "equipment" },
  { id = "apply", glyph = "refresh", section = "equipment" },
  { id = "display", glyph = "device-desktop", section = "equipment" },
  { id = "profiles", glyph = "users", section = "accounts" },
  { id = "aliases", glyph = "tags", section = "accounts" },
  { id = "sync", glyph = "cloud-upload", section = "more" },
  { id = "doctor", glyph = "stethoscope", section = "more" },
  { id = "windowsStatus", glyph = "info-circle", section = "more" },
  { id = "windowsWeb", glyph = "world", section = "more" },
  { id = "windowsLogs", glyph = "terminal-2", section = "more" },
  { id = "stop", glyph = "player-stop", section = "more" },
  { id = "password", glyph = "key", section = "more" },
  { id = "wipe", glyph = "trash", section = "more" },
}

local function taskAvailable(id)
  local provider = ({aws = "aws", profiles = "aws", aliases = "aws", sync = "aws", github = "github", gitlab = "gitlab"})[id]
  if provider ~= nil then return (integrations[provider] or {}).available == true end
  if id == "windows" or id == "display" or id == "stop" or id == "password" or id == "wipe" or string.sub(id, 1, 7) == "windows" then
    return (integrations.windowsVm or {}).available == true
  end
  return true
end

local function context(id)
  if not taskAvailable(id) then return tr("ux.unavailable") end
  local aws = integrations.aws or {}
  if id == "aws" then return aws.activeProfile ~= nil and aws.activeProfile ~= "" and aws.activeProfile or tr("ux.choose_profile") end
  if id == "windows" then
    local windows = integrations.windowsVm or {}
    return (windows.credentialStored == true or windows.installed == true) and tr("ux.ready") or tr("ux.first_use")
  end
  if id == "github" or id == "gitlab" then return (integrations[id] or {}).configured == true and tr("ux.configured") or tr("ux.first_use") end
  if id == "theme" then return modeOptions[persistedMode == "light" and 2 or 1] end
  if id == "scope" or id == "apply" then return tr(persistedTarget == "existing-nixos" and "ux.scope_system" or "ux.scope_user") end
  if id == "display" then return rdpDisplayModeOptions[selectedRdpDisplayModeIndex + 1] end
  return ""
end

local function actionButton(task, compact)
  local callback = function() dispatch(task.id) end
  if compact then
    return ui.column({ fill = "surface_variant/0.65", radius = 9, padding = 7, gap = 0 }, {
      button(tr("ux.tasks." .. task.id), callback, task.glyph, "ghost", taskAvailable(task.id)),
      ui.label({ text = context(task.id), color = "on_surface_variant", fontSize = 11, maxLines = 1, padding = 4 }),
    })
  end
  return button(tr("ux.tasks." .. task.id), callback, task.glyph, task.id == "wipe" and "destructive" or "ghost", taskAvailable(task.id))
end

local function homeView()
  local nodes = {}
  local query = string.lower(searchQuery)
  if query ~= "" then
    for _, task in ipairs(TASKS) do
      if string.find(string.lower(tr("ux.tasks." .. task.id) .. " " .. tr("ux.keywords." .. task.id)), query, 1, true) ~= nil then
        table.insert(nodes, actionButton(task, false))
      end
    end
    if #nodes == 0 then table.insert(nodes, label(tr("ux.no_results"), true)) end
    return nodes
  end
  local work, equipment = {}, {}
  for _, task in ipairs(TASKS) do
    if task.section == "work" then table.insert(work, actionButton(task, true)) end
    if task.section == "equipment" then table.insert(equipment, actionButton(task, true)) end
  end
  table.insert(nodes, ui.row({ gap = 12, align = "start" }, { group(tr("ux.work"), work), group(tr("ux.equipment"), equipment) }))
  for _, section in ipairs({ "accounts", "more" }) do
    local children = {}
    for _, task in ipairs(TASKS) do
      if task.section == section then table.insert(children, actionButton(task, false)) end
    end
    table.insert(nodes, group(tr("ux." .. section), children))
  end
  return nodes
end

local function goHome()
  if busy then return end
  activeView = "home"
  searchQuery = ""
  profileQuery = ""
  selectedAliasKey = ""
  selectedTargetIndex = persistedTarget == "existing-nixos" and 1 or 0
  selectedModeIndex = persistedMode == "light" and 1 or 0
  clearWindowsRdpPassword()
  resetAwsAliasDraft()
  render()
end

local function chooseProfile(profile)
  if busy or awsProfileRequestPath == "" then return end
  local encoded = noctalia.json.encode({ schemaVersion = 1, profile = profile })
  if type(encoded) ~= "string" or noctalia.writeFile(awsProfileRequestPath, encoded) ~= true then
    fail(tr("ux.profile_write_error"))
    return
  end
  busy = true
  render()
  runAllowed("awsProfileSelect", function(payload)
    integrations.aws.activeProfile = payload.activeProfile
    busy = false
    local login = awsLoginAfterSelect
    awsLoginAfterSelect = false
    notice = tr("ux.profile_saved", { profile = payload.activeProfile })
    goHome()
    if login then openTerminalAction("awsLogin") end
  end)
end

local function profileSearch()
  return ui.input({ key = "aws-profile-search", value = profileQuery, placeholder = tr("ux.filter_accounts"), controlSize = "md", onChange = function(value)
    profileQuery = value
    render()
  end })
end

local function profilesView()
  local nodes = { profileSearch() }
  local aws = integrations.aws or {}
  local profiles = type(aws.profiles) == "table" and aws.profiles or {}
  for _, profile in ipairs(profiles) do
    if type(profile) == "string" and string.find(string.lower(profile), string.lower(profileQuery), 1, true) ~= nil then
      table.insert(nodes, button(profile, function() chooseProfile(profile) end, profile == aws.activeProfile and "circle-check" or "user", "ghost"))
    end
  end
  if #profiles == 0 then
    table.insert(nodes, label(tr("ux.no_accounts"), true))
    table.insert(nodes, button(tr("ux.tasks.sync"), function() pendingAwsSetup = true; openTerminalAction("awsSync") end, "cloud-upload", "primary"))
  end
  return nodes
end

local function aliasesView()
  local records = awsAliasRecords(integrations.aws or {})
  if selectedAliasKey ~= "" then
    for _, assignment in ipairs(records) do
      if assignment.key == selectedAliasKey then
        return {
          label(assignment.accountName .. " · " .. assignment.roleName, true),
          label(tr("panel.integrations.aws.alias_field")),
          ui.input({ key = "alias-name-" .. assignment.key, value = awsAliasDraft[assignment.key], placeholder = assignment.suggestedAlias, controlSize = "md", onChange = function(value) awsAliasDraft[assignment.key] = value end }),
          label(tr("panel.integrations.aws.region_field")),
          ui.input({ key = "alias-regions-" .. assignment.key, value = awsRegionDraft[assignment.key], placeholder = "us-east-1, us-east-2", controlSize = "md", onChange = function(value) awsRegionDraft[assignment.key] = value end }),
          label(tr("ux.region_hint"), true),
          button(tr("ux.save"), "onAwsAliasesSaveClicked", "device-floppy", "primary"),
        }
      end
    end
  end
  local nodes = { profileSearch() }
  if #records == 0 then
    table.insert(nodes, label(tr("ux.no_accounts"), true))
    table.insert(nodes, button(tr("ux.tasks.sync"), function() openTerminalAction("awsSync") end, "cloud-upload", "primary"))
  else
    table.insert(nodes, button(tr("ux.recommend_aliases"), function()
      for _, assignment in ipairs(records) do awsAliasDraft[assignment.key] = assignment.suggestedAlias end
      onAwsAliasesSaveClicked()
    end, "sparkles"))
    for _, assignment in ipairs(records) do
      local name = assignment.accountName .. " · " .. assignment.roleName
      if string.find(string.lower(name .. " " .. assignment.alias), string.lower(profileQuery), 1, true) ~= nil then
        table.insert(nodes, button(name, function() selectedAliasKey = assignment.key; render() end, "tag"))
      end
    end
  end
  return nodes
end

local function applyChoice()
  if busy then return end
  local action = "applySaved"
  if activeView == "theme" then action = selectedModeIndex == 1 and "applyLight" or "applyDark" end
  if activeView == "scope" then action = selectedTargetIndex == 1 and "applySystem" or "applyUser" end
  openTerminalAction(action)
end

local function configurationView()
  local nodes = {}
  if activeView == "theme" then
    table.insert(nodes, ui.row({ gap = 10 }, {
      button(modeOptions[1], function() selectedModeIndex = 0; render() end, "moon", selectedModeIndex == 0 and "primary" or "secondary"),
      button(modeOptions[2], function() selectedModeIndex = 1; render() end, "sun", selectedModeIndex == 1 and "primary" or "secondary"),
    }))
  elseif activeView == "scope" then
    table.insert(nodes, button(tr("ux.scope_user"), function() selectedTargetIndex = 0; render() end, "user", selectedTargetIndex == 0 and "primary" or "secondary"))
    table.insert(nodes, button(tr("ux.scope_system"), function() selectedTargetIndex = 1; render() end, "device-desktop", selectedTargetIndex == 1 and "primary" or "secondary"))
  end
  local target = activeView == "scope" and selectedTarget() or persistedTarget
  table.insert(nodes, label(tr(target == "existing-nixos" and "ux.apply_system_summary" or "ux.apply_user_summary"), true))
  if activeView == "theme" then table.insert(nodes, label(tr("ux.theme_summary", { mode = modeOptions[selectedModeIndex + 1] }), true)) end
  table.insert(nodes, button(tr("ux.apply_confirm"), applyChoice, "check", "primary"))
  return nodes
end

local function windowsView()
  if activeView == "display" then
    return {
      label(tr("ux.display_hint"), true),
      button(rdpDisplayModeOptions[1], function() onWindowsRdpDisplayModeChanged(0) end, "device-desktop", selectedRdpDisplayModeIndex == 0 and "primary" or "secondary"),
      button(rdpDisplayModeOptions[2], function() onWindowsRdpDisplayModeChanged(1) end, "maximize", selectedRdpDisplayModeIndex == 1 and "primary" or "secondary"),
    }
  end
  if activeView == "stop" then
    return { label(tr("ux.stop_hint"), true), button(tr("ux.stop_confirm"), function() openTerminalAction("windowsDown") end, "player-stop", "destructive") }
  end
  local wipe = activeView == "wipe"
  local replacing = activeView == "password"
  local nodes = {
    label(tr(wipe and "ux.wipe_hint" or replacing and "ux.password_hint" or "ux.windows_setup_hint"), true),
    label(tr("panel.integrations.windows.username")),
    ui.input({ key = "windows-username", value = rdpUsername, controlSize = "md", onChange = function(value)
      local ready = windowsRdpCredentialsReady()
      rdpUsername = value
      if ready ~= windowsRdpCredentialsReady() then render() end
    end }),
    label(tr("panel.integrations.windows.password")),
    ui.input({ key = "windows-password-" .. tostring(rdpPasswordRevision), value = rdpPassword, password = true, controlSize = "md", onChange = function(value)
      local ready = windowsRdpCredentialsReady()
      rdpPassword = value
      if ready ~= windowsRdpCredentialsReady() then render() end
    end }),
  }
  if wipe then
    table.insert(nodes, label(tr("ux.wipe_type"), true))
    table.insert(nodes, ui.input({ key = "windows-wipe-check-" .. tostring(windowsWipeConfirmationRevision), value = windowsWipeConfirmation, placeholder = "WIPE", controlSize = "md", onChange = function(value)
      local ready = windowsWipeConfirmation == "WIPE"
      windowsWipeConfirmation = value
      if ready ~= (value == "WIPE") then render() end
    end }))
  end
  table.insert(nodes, button(tr(wipe and "ux.wipe_confirm" or replacing and "ux.password_confirm" or "ux.windows_setup_confirm"), function()
    if not windowsRdpCredentialsReady() then return end
    if wipe then
      if windowsWipeConfirmation ~= "WIPE" then return end
      openWindowsWipeAction()
    elseif replacing then openWindowsPasswordResetAction()
    else openWindowsRdpAction("windowsUp") end
    if currentError == "" then goHome() end
  end, wipe and "trash" or "device-desktop", wipe and "destructive" or "primary", windowsRdpCredentialsReady() and (not wipe or windowsWipeConfirmation == "WIPE")))
  return nodes
end

render = function()
  local body = {}
  if activeView == "home" then body = homeView()
  elseif activeView == "profiles" then body = profilesView()
  elseif activeView == "aliases" then body = aliasesView()
  elseif activeView == "theme" or activeView == "scope" or activeView == "apply" then body = configurationView()
  else body = windowsView() end
  local header = {}
  if activeView ~= "home" then table.insert(header, button("", goHome, "arrow-left", "ghost")) end
  table.insert(header, ui.glyph({ name = "cube-spark", size = 23, color = "primary" }))
  table.insert(header, ui.label({ text = activeView == "home" and "Holodeck" or tr("ux.tasks." .. activeView), fontSize = 18, fontWeight = "bold", flexGrow = 1, maxLines = 1 }))
  table.insert(header, ui.button({ glyph = "close", tooltip = tr("panel.close"), variant = "ghost", controlSize = "sm", onClick = "onCloseClicked" }))
  local nodes = { ui.row({ gap = 9, align = "center" }, header) }
  if activeView == "home" then
    table.insert(nodes, ui.input({ key = "holodeck-search", value = searchQuery, placeholder = tr("ux.search"), controlSize = "md", onChange = function(value) searchQuery = value; render() end }))
  end
  table.insert(nodes, ui.scroll({ flexGrow = 1, gap = 14 }, body))
  local feedback = currentError ~= "" and currentError or busy and tr("panel.working") or notice
  if feedback ~= "" then
    table.insert(nodes, ui.label({ text = feedback, fontSize = 12, maxLines = currentError ~= "" and 4 or 2, color = currentError ~= "" and "error" or "on_surface_variant" }))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 14, padding = 8 }, nodes))
end

dispatch = function(id)
  if busy or not taskAvailable(id) then return end
  notice = ""
  currentError = ""
  local windows = integrations.windowsVm or {}
  if id == "windows" and (windows.credentialStored == true or windows.installed == true) then openWindowsRdpAction("windowsUp"); return end
  if id == "aws" then
    local aws = integrations.aws or {}
    local profiles = type(aws.profiles) == "table" and aws.profiles or {}
    if #profiles == 0 then pendingAwsSetup = true; openTerminalAction("awsSync"); return end
    if type(aws.activeProfile) == "string" and aws.activeProfile ~= "" then openTerminalAction("awsLogin"); return end
    awsLoginAfterSelect = true
    id = "profiles"
  end
  local terminal = ({ github = "githubSetup", gitlab = "gitlabSetup", sync = "awsSync", doctor = "holodeckDoctor", windowsStatus = "windowsStatus", windowsLogs = "windowsLogs" })[id]
  if terminal ~= nil then openTerminalAction(terminal); return end
  if id == "windowsWeb" then openGraphicalAction("windowsWeb"); return end
  activeView = id
  profileQuery = ""
  selectedAliasKey = ""
  render()
end

function onOpen(_context)
  panelIsOpen = true
  noctalia.setUpdateInterval(8000)
  local pluginData = noctalia.pluginDataDir()
  if type(pluginData) == "string" and pluginData ~= "" then
    awsAliasRequestPath = pluginData .. "/aws-alias-request.json"
    awsProfileRequestPath = pluginData .. "/aws-profile-request.json"
  end
  local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
  rdpCredentialRequestPath = type(runtimeDir) == "string" and string.sub(runtimeDir, 1, 1) == "/" and runtimeDir .. "/holodeck-control-windows-rdp.json" or ""
  activeView = "home"
  searchQuery = ""
  clearWindowsRdpPassword()
  loadStatus(false)
end

function update()
  if not panelIsOpen or busy or statusPollInFlight or activeView ~= "home" then return end
  statusPollInFlight = true
  local accepted = noctalia.runAsync(COMMANDS.status, function(result)
    statusPollInFlight = false
    if not panelIsOpen or activeView ~= "home" or busy then return end
    local payload = decodeCommandResult(result)
    if payload ~= nil then
      applyStatusPayload(payload)
      if pendingAwsSetup and #(integrations.aws.profiles or {}) > 0 then
        pendingAwsSetup = false
        awsLoginAfterSelect = false
        activeView = "profiles"
        notice = tr("ux.choose_profile")
      end
      render()
    end
  end)
  if not accepted then statusPollInFlight = false end
end

function onCloseClicked()
  panelIsOpen = false
  clearWindowsRdpPassword()
  panel.close()
end

function onAwsAliasesSaveClicked()
  if busy or not backendAvailable then
    return
  end
  if awsAliasRequestPath == "" then
    fail(tr("error.alias_request_unavailable"))
    return
  end

  local profiles = {}
  for _, assignment in ipairs(awsAliasRecords(integrations.aws or {})) do
    local regions = parseAwsRegionDraft(awsRegionDraft[assignment.key])
    if #regions == 0 then
      fail(tr("error.aws_region_required", {
        account = assignment.accountName,
        role = assignment.roleName,
      }))
      return
    end
    profiles[assignment.key] = {
      alias = awsAliasDraft[assignment.key] or assignment.alias,
      regions = regions,
    }
  end
  local encoded, encodeError = noctalia.json.encode({
    schemaVersion = 3,
    profiles = profiles,
  })
  if type(encoded) ~= "string" then
    fail(tr("error.alias_request_failed", { detail = tostring(encodeError or "") }))
    return
  end
  local written, writeError = noctalia.writeFile(awsAliasRequestPath, encoded)
  if written ~= true then
    fail(tr("error.alias_request_failed", { detail = tostring(writeError or "") }))
    return
  end

  busy = true
  currentError = ""
  notice = ""
  render()
  runAllowed("awsAliasesApply", function(payload)
    if type(payload.profiles) ~= "table" or type(payload.assignments) ~= "table" then
      fail(tr("error.backend_rejected"))
      return
    end
    local integration = integrations.aws or {}
    integration.aliases = payload.assignments
    integration.profiles = {}
    for _, profile in ipairs(payload.profiles) do
      if type(profile) == "table" and type(profile.name) == "string" then
        table.insert(integration.profiles, profile.name)
      end
    end
    integration.configured = #integration.aliases > 0
    integration.pendingRegionCount = payload.pendingRegionCount or 0
    integrations.aws = integration
    resetAwsAliasDraft()
    busy = false
    activeView = "home"
    selectedAliasKey = ""
    notice = tr("ux.aliases_saved")
    render()
  end)
end

function onWindowsRdpDisplayModeChanged(index, _text)
  if busy or not backendAvailable then
    return
  end

  local parsed = tonumber(index)
  if parsed ~= 0 and parsed ~= 1 then
    return
  end

  busy = true
  currentError = ""
  notice = ""
  render()

  local action = parsed == 1 and "rdpModeFullscreen" or "rdpModeHalf"
  runAllowed(action, function(payload)
    setSelectionsFromIr(payload.ir)
    statusExists = true
    statusSource = "file"
    recomputeDirty()
    busy = false
    activeView = "home"
    notice = tr("notice.windows_rdp_display_saved")
    render()
  end)
end
