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
  if command == nil then
    fail(tr("error.command_not_allowed"))
    return
  end

  local opened = noctalia.runInTerminal(command)
  if opened then
    if action == "awsSync" then
      awsSyncPolling = true
      awsSyncPollInFlight = false
      awsSyncPollCount = 0
      notice = tr("notice.aws_sync_waiting")
    else
      notice = tr("notice.integration_terminal")
    end
    currentError = ""
  else
    if action == "awsSync" then
      awsSyncPolling = false
    end
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
  if not prepareWindowsCredentials(integration.credentialStored ~= true) then
    return
  end

  local opened = noctalia.runAsync(command)
  if opened then
    notice = tr("notice.graphical_action_started")
    currentError = ""
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
    notice = statusExists
      and (reportSuccess == true and tr("notice.status_loaded") or "")
      or tr("notice.ir_missing")
    render()
  end)
end

local function pollAwsSyncStatus()
  if not awsSyncPolling or awsSyncPollInFlight or busy then
    return
  end

  awsSyncPollInFlight = true
  local accepted = noctalia.runAsync(COMMANDS.status, function(result)
    awsSyncPollInFlight = false
    if not awsSyncPolling then
      return
    end

    local payload = decodeCommandResult(result)
    if payload ~= nil then
      applyStatusPayload(payload)
      local aws = integrations.aws or {}
      local aliases = type(aws.aliases) == "table" and aws.aliases or {}
      if #aliases > 0 then
        awsSyncPolling = false
        awsAliasEditorOpen = true
        notice = tr("notice.aws_sync_ready")
        currentError = ""
        render()
        return
      end
    end

    awsSyncPollCount += 1
    if awsSyncPollCount >= AWS_SYNC_POLL_LIMIT then
      awsSyncPolling = false
      notice = ""
      currentError = tr("error.aws_sync_not_detected")
      render()
    end
  end)

  if not accepted then
    awsSyncPollInFlight = false
    awsSyncPolling = false
    notice = ""
    currentError = tr("error.command_not_started")
    render()
  end
end

local function integrationProfileNames(integration)
  if type(integration) ~= "table" or type(integration.profiles) ~= "table" then
    return tr("panel.integrations.none")
  end

  local names = {}
  for _, profile in ipairs(integration.profiles) do
    if type(profile) == "string" and profile ~= "" then
      table.insert(names, profile)
    elseif type(profile) == "table" and type(profile.name) == "string" and profile.name ~= "" then
      table.insert(names, profile.name)
    end
  end
  if #names == 0 then
    return tr("panel.integrations.none")
  end
  return table.concat(names, ", ")
end

local function integrationHostNames(integration)
  if type(integration) ~= "table" or type(integration.hosts) ~= "table" then
    return tr("panel.integrations.none")
  end

  local hosts = {}
  for _, host in ipairs(integration.hosts) do
    if type(host) == "string" and host ~= "" then
      table.insert(hosts, host)
    end
  end
  if #hosts == 0 then
    return tr("panel.integrations.none")
  end
  return table.concat(hosts, ", ")
end

local function card(children, fill)
  return ui.column({ fill = fill or "surface_variant/0.72", radius = 9, padding = 12, gap = 8 }, children)
end

local function section(title, description, control)
  return ui.column({ gap = 8 }, {
    ui.label({ text = title, fontWeight = "bold", color = "on_surface" }),
    ui.label({ text = description, fontSize = 13, color = "on_surface_variant", maxLines = 3 }),
    control,
  })
end

local function integrationState(integration)
  local available = type(integration) == "table" and integration.available == true
  local configured = type(integration) == "table" and integration.configured == true
  if configured then
    return "configured", "primary", "circle-check"
  end
  if available then
    return "available", "on_surface_variant", "info-circle"
  end
  return "unavailable", "on_surface_variant", "circle-minus"
end

local function integrationStateLabel(integration)
  local stateKey = integrationState(integration)
  return tr("panel.integrations.state." .. stateKey)
end

local function integrationSummaryRow(title, glyph, integration)
  local _, color, stateGlyph = integrationState(integration)
  return ui.row({ key = "summary-" .. title, align = "center", gap = 8, minHeight = 32 }, {
    ui.glyph({ name = glyph, size = 16, color = "on_surface" }),
    ui.label({ text = title, color = "on_surface", flexGrow = 1 }),
    ui.glyph({ name = stateGlyph, size = 14, color = color }),
    ui.label({ text = integrationStateLabel(integration), fontSize = 13, color = color }),
  })
end

local function configuredIntegrationCount()
  local count = 0
  for _, integration in pairs(integrations) do
    if type(integration) == "table" and integration.configured == true then
      count += 1
    end
  end
  return count
end

local function statusCard(showTechnicalDetails)
  local stateLabel = statusExists and tr("panel.status.ready") or tr("panel.status.not_created")
  local stateColor = statusExists and "primary" or "tertiary"
  local currentKey = statusExists and "panel.status.current" or "panel.status.defaults"
  local children = {
    ui.row({ align = "center", gap = 8, minHeight = 32 }, {
      ui.glyph({ name = statusExists and "circle-check" or "alert-circle", size = 18, color = stateColor }),
      ui.label({ text = stateLabel, fontWeight = "bold", color = stateColor, flexGrow = 1 }),
    }),
    ui.label({
      text = tr(currentKey, { target = persistedTarget, mode = persistedMode }),
      fontSize = 13,
      color = "on_surface_variant",
    }),
  }

  if showTechnicalDetails and irPath ~= "" then
    table.insert(children, ui.separator({ spacing = 2 }))
    table.insert(children, ui.label({
      text = tr("panel.status.path", { path = irPath }),
      fontSize = 11,
      color = "on_surface_variant",
      maxLines = 2,
    }))
  end
  if showTechnicalDetails and statusSource ~= "" then
    table.insert(children, ui.label({
      text = tr("panel.status.source", { source = statusSource }),
      fontSize = 11,
      color = "on_surface_variant",
    }))
  end

  return card(children)
end

local function feedbackCards()
  local cards = {}
  if notice ~= "" then
    table.insert(cards, ui.column({ fill = "primary/0.14", radius = 9, padding = 10, gap = 6 }, {
      ui.row({ align = "center", gap = 8 }, {
        ui.glyph({ name = "circle-check", size = 16, color = "primary" }),
        ui.label({ text = notice, color = "on_surface", maxLines = 4, flexGrow = 1 }),
      }),
    }))
  end
  if currentError ~= "" then
    table.insert(cards, ui.column({ fill = "error/0.14", radius = 9, padding = 10, gap = 6 }, {
      ui.row({ align = "center", gap = 8 }, {
        ui.glyph({ name = "alert-circle", size = 16, color = "error" }),
        ui.label({ text = tr("panel.error_title"), color = "error", fontWeight = "bold" }),
      }),
      ui.label({ text = currentError, color = "on_surface", maxLines = 8 }),
    }))
  end
  return cards
end

local function confirmationCard()
  if not confirmingApply or pendingPlan == nil then
    return nil
  end

  return card({
    ui.row({ align = "center", gap = 8 }, {
      ui.glyph({ name = "alert-circle", size = 17, color = "secondary" }),
      ui.label({ text = tr("panel.confirm.title"), color = "on_surface", fontWeight = "bold" }),
    }),
    ui.label({ text = planSummary, color = "on_surface", maxLines = 8 }),
    ui.label({ text = tr("panel.confirm.warning"), fontSize = 13, color = "on_surface_variant", maxLines = 3 }),
    ui.row({ gap = 8, justify = "end" }, {
      ui.button({
        text = tr("panel.cancel"),
        variant = "ghost",
        controlSize = "sm",
        onClick = "onCancelApply",
      }),
      ui.button({
        text = tr("panel.apply_terminal"),
        glyph = "terminal-2",
        variant = "primary",
        controlSize = "sm",
        onClick = "onConfirmApply",
      }),
    }),
  }, "secondary/0.16")
end

local function overviewView()
  local github = integrations.github or {}
  local gitlab = integrations.gitlab or {}
  local aws = integrations.aws or {}
  local windowsVm = integrations.windowsVm or {}

  return {
    statusCard(false),
    card({
      ui.row({ align = "center", gap = 8 }, {
        ui.glyph({ name = "device-desktop-cog", size = 18, color = "primary" }),
        ui.label({ text = tr("panel.system.title"), fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      }),
      ui.label({
        text = tr("panel.overview.system_summary", { target = persistedTarget, mode = persistedMode }),
        fontSize = 13,
        color = "on_surface_variant",
      }),
      ui.button({
        text = tr("panel.overview.open_system"),
        variant = "ghost",
        contentAlign = "start",
        controlSize = "sm",
        onClick = "onShowSystem",
      }),
    }),
    card({
      ui.row({ align = "center", gap = 8 }, {
        ui.glyph({ name = "plug-connected", size = 18, color = "primary" }),
        ui.label({ text = tr("panel.integrations.title"), fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
        ui.label({
          text = tr("panel.overview.configured_count", { count = configuredIntegrationCount() }),
          fontSize = 13,
          color = "on_surface_variant",
        }),
      }),
      integrationSummaryRow(tr("panel.integrations.github.title"), "brand-github", github),
      integrationSummaryRow(tr("panel.integrations.gitlab.title"), "brand-gitlab", gitlab),
      integrationSummaryRow(tr("panel.integrations.aws.title"), "cloud", aws),
      integrationSummaryRow(tr("panel.integrations.windows.title"), "device-desktop", windowsVm),
      ui.button({
        text = tr("panel.overview.open_integrations"),
        variant = "ghost",
        contentAlign = "start",
        controlSize = "sm",
        onClick = "onShowIntegrations",
      }),
    }),
  }
end

local function systemView()
  local nodes = {
    statusCard(true),
    card({
      section(
        tr("panel.target.title"),
        tr("panel.target.description"),
        ui.select({
          key = "deployment-target",
          options = targetOptions,
          selectedIndex = selectedTargetIndex,
          controlSize = "sm",
          enabled = backendAvailable and not busy,
          onChange = "onTargetChanged",
        })
      ),
      ui.separator({ spacing = 2 }),
      section(
        tr("panel.mode.title"),
        tr("panel.mode.description"),
        ui.select({
          key = "theme-mode",
          options = modeOptions,
          selectedIndex = selectedModeIndex,
          controlSize = "sm",
          enabled = backendAvailable and not busy,
          onChange = "onModeChanged",
        })
      ),
      ui.row({ align = "center", gap = 8 }, {
        ui.label({
          text = dirty and tr("panel.unsaved") or tr("panel.saved"),
          fontSize = 13,
          color = dirty and "tertiary" or "on_surface_variant",
          flexGrow = 1,
          maxLines = 2,
        }),
        ui.button({
          text = busy and tr("panel.working") or tr("panel.save_ir"),
          glyph = "device-floppy",
          variant = "primary",
          controlSize = "sm",
          enabled = backendAvailable and dirty and not busy,
          onClick = "onSaveClicked",
        }),
      }),
    }),
    card({
      ui.label({ text = tr("panel.plan.title"), fontWeight = "bold", color = "on_surface" }),
      ui.label({
        text = tr("panel.plan.description"),
        fontSize = 13,
        color = "on_surface_variant",
        maxLines = 4,
      }),
      ui.button({
        text = tr("panel.plan.button"),
        glyph = "list-check",
        variant = "primary",
        controlSize = "sm",
        enabled = backendAvailable and statusExists and not dirty and not busy,
        onClick = "onPlanClicked",
      }),
    }),
  }

  local confirmation = confirmationCard()
  if confirmation ~= nil then
    table.insert(nodes, confirmation)
  elseif planSummary ~= "" then
    table.insert(nodes, card({
      ui.label({ text = planSummary, color = "on_surface_variant", maxLines = 8 }),
    }))
  end

  return nodes
end

local function integrationPickerButton(id, title, glyph, callback)
  return ui.button({
    key = "integration-" .. id,
    text = title,
    glyph = glyph,
    variant = "ghost",
    selected = activeIntegration == id,
    controlSize = "sm",
    flexGrow = 1,
    onClick = callback,
  })
end

local function integrationDetailHeader(title, glyph, integration)
  local _, color, stateGlyph = integrationState(integration)
  return ui.row({ align = "center", gap = 8, minHeight = 32 }, {
    ui.glyph({ name = glyph, size = 18, color = "on_surface" }),
    ui.label({ text = title, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
    ui.glyph({ name = stateGlyph, size = 14, color = color }),
    ui.label({ text = integrationStateLabel(integration), fontSize = 13, color = color }),
  })
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

local function awsRegionSelected(assignment, region)
  for _, selected in ipairs(parseAwsRegionDraft(awsRegionDraft[assignment.key])) do
    if selected == region then
      return true
    end
  end
  return false
end

local function toggleAwsRegionDraft(assignment, region)
  local regions = parseAwsRegionDraft(awsRegionDraft[assignment.key])
  local updated = {}
  local removed = false
  for _, selected in ipairs(regions) do
    if selected == region then
      removed = true
    else
      table.insert(updated, selected)
    end
  end
  if not removed then
    table.insert(updated, region)
  end
  awsRegionDraft[assignment.key] = table.concat(updated, ", ")
  awsAliasRevision[assignment.key] = (awsAliasRevision[assignment.key] or 0) + 1
  render()
end

local function setAwsAliasDraft(assignment, value)
  awsAliasDraft[assignment.key] = value
  awsAliasRevision[assignment.key] = (awsAliasRevision[assignment.key] or 0) + 1
  render()
end

local function awsAliasProfileEditor(assignment, enabled)
  local alias = awsAliasDraft[assignment.key] or assignment.alias
  local regions = awsRegionDraft[assignment.key] or awsRegionDraftValue(assignment)
  local revision = awsAliasRevision[assignment.key] or 0
  local suggestedRegions = type(assignment.suggestedRegions) == "table"
    and table.concat(assignment.suggestedRegions, ", ")
    or ""
  local profileNames = {}
  for _, profile in ipairs(assignment.profiles) do
    if type(profile) == "table" and type(profile.name) == "string" then
      table.insert(profileNames, profile.name)
    end
  end
  return ui.column({
    key = "aws-alias-card-" .. assignment.key,
    fill = "surface/0.66",
    radius = 8,
    padding = 10,
    gap = 7,
  }, {
    ui.label({
      text = assignment.accountName .. " · " .. assignment.roleName,
      color = "on_surface",
      fontWeight = "bold",
      maxLines = 2,
    }),
    ui.label({ text = tr("panel.integrations.aws.alias_field"), color = "on_surface_variant", fontSize = 11 }),
    ui.input({
      key = "aws-alias-input-" .. assignment.key .. "-" .. tostring(revision),
      value = alias,
      placeholder = assignment.suggestedAlias,
      controlSize = "sm",
      enabled = enabled,
      onChange = function(value)
        awsAliasDraft[assignment.key] = value
      end,
    }),
    ui.label({ text = tr("panel.integrations.aws.region_field"), color = "on_surface_variant", fontSize = 11 }),
    ui.input({
      key = "aws-region-input-" .. assignment.key .. "-" .. tostring(revision),
      value = regions,
      placeholder = "us-east-1, us-east-2",
      controlSize = "sm",
      enabled = enabled,
      onChange = function(value)
        awsRegionDraft[assignment.key] = value
      end,
    }),
    ui.row({ gap = 6 }, {
      ui.button({
        text = "us-east-1",
        variant = awsRegionSelected(assignment, "us-east-1") and "primary" or "secondary",
        controlSize = "sm",
        enabled = enabled,
        flexGrow = 1,
        onClick = function()
          toggleAwsRegionDraft(assignment, "us-east-1")
        end,
      }),
      ui.button({
        text = "us-east-2",
        variant = awsRegionSelected(assignment, "us-east-2") and "primary" or "secondary",
        controlSize = "sm",
        enabled = enabled,
        flexGrow = 1,
        onClick = function()
          toggleAwsRegionDraft(assignment, "us-east-2")
        end,
      }),
    }),
    ui.label({
      text = assignment.pending == true
        and tr("panel.integrations.aws.region_pending", {
          regions = suggestedRegions ~= "" and suggestedRegions or "—",
        })
        or tr("panel.integrations.aws.region_help"),
      color = "on_surface_variant",
      fontSize = 11,
      maxLines = 3,
    }),
    ui.label({
      text = #profileNames > 0
        and tr("panel.integrations.aws.alias_current", { profile = table.concat(profileNames, ", ") })
        or tr("panel.integrations.aws.alias_pending"),
      color = "on_surface_variant",
      fontSize = 11,
      maxLines = 2,
    }),
    ui.row({ gap = 6 }, {
      ui.button({
        text = tr("panel.integrations.aws.recommend"),
        glyph = "sparkles",
        variant = "secondary",
        controlSize = "sm",
        enabled = enabled,
        flexGrow = 1,
        onClick = function()
          setAwsAliasDraft(assignment, assignment.suggestedAlias)
        end,
      }),
      ui.button({
        text = tr("panel.integrations.aws.original"),
        variant = "ghost",
        controlSize = "sm",
        enabled = enabled,
        flexGrow = 1,
        onClick = function()
          setAwsAliasDraft(assignment, assignment.defaultAlias)
        end,
      }),
    }),
  })
end

local function appendAwsAliasEditor(children, integration, enabled)
  local records = awsAliasRecords(integration)
  if #records == 0 then
    table.insert(children, ui.button({
      text = tr("panel.integrations.aws.manage_aliases"),
      glyph = "tags",
      variant = "ghost",
      controlSize = "sm",
      enabled = false,
    }))
    table.insert(children, ui.label({
      text = awsSyncPolling
        and tr("panel.integrations.aws.alias_waiting")
        or tr("panel.integrations.aws.alias_requires_sync"),
      color = "on_surface_variant",
      fontSize = 12,
      maxLines = 3,
    }))
    return
  end

  table.insert(children, ui.button({
    text = awsAliasEditorOpen
      and tr("panel.integrations.aws.hide_aliases")
      or tr("panel.integrations.aws.manage_aliases"),
    glyph = "tags",
    variant = "ghost",
    controlSize = "sm",
    enabled = enabled,
    onClick = "onAwsAliasEditorClicked",
  }))
  if not awsAliasEditorOpen then
    return
  end

  table.insert(children, ui.separator({ spacing = 2 }))
  table.insert(children, ui.label({
    text = tr("panel.integrations.aws.alias_title"),
    color = "on_surface",
    fontWeight = "bold",
  }))
  table.insert(children, ui.label({
    text = tr("panel.integrations.aws.alias_description"),
    color = "on_surface_variant",
    fontSize = 13,
    maxLines = 4,
  }))
  local pendingCount = 0
  for _, assignment in ipairs(records) do
    if assignment.pending == true then
      pendingCount += 1
    end
  end
  if pendingCount > 0 then
    table.insert(children, ui.label({
      text = tr("panel.integrations.aws.pending_count", { count = pendingCount }),
      color = "error",
      fontSize = 12,
      fontWeight = "bold",
      maxLines = 2,
    }))
  end
  table.insert(children, ui.row({ gap = 8 }, {
    ui.button({
      text = tr("panel.integrations.aws.recommend_all"),
      glyph = "sparkles",
      variant = "secondary",
      controlSize = "sm",
      enabled = enabled,
      flexGrow = 1,
      onClick = "onAwsRecommendAllClicked",
    }),
    ui.button({
      text = tr("panel.integrations.aws.original_all"),
      variant = "ghost",
      controlSize = "sm",
      enabled = enabled,
      flexGrow = 1,
      onClick = "onAwsOriginalAllClicked",
    }),
  }))
  for _, assignment in ipairs(records) do
    table.insert(children, awsAliasProfileEditor(assignment, enabled))
  end
  table.insert(children, ui.button({
    text = tr("panel.integrations.aws.save_aliases"),
    glyph = "device-floppy",
    variant = "primary",
    controlSize = "sm",
    enabled = enabled,
    onClick = "onAwsAliasesSaveClicked",
  }))
end

local function integrationDetail()
  local enabled = backendAvailable and not busy

  if activeIntegration == "gitlab" then
    local integration = integrations.gitlab or {}
    return card({
      integrationDetailHeader(tr("panel.integrations.gitlab.title"), "brand-gitlab", integration),
      ui.label({ text = tr("panel.integrations.gitlab.description"), color = "on_surface_variant", maxLines = 4 }),
      ui.label({
        text = tr("panel.integrations.gitlab.session", { hosts = integrationHostNames(integration) }),
        fontSize = 13,
        color = "on_surface_variant",
      }),
      ui.button({
        text = integration.configured == true
          and tr("panel.integrations.gitlab.resync")
          or tr("panel.integrations.gitlab.setup"),
        glyph = "login",
        variant = "primary",
        controlSize = "sm",
        enabled = enabled and integration.available == true,
        onClick = "onGitlabSetupClicked",
      }),
    })
  end

  if activeIntegration == "aws" then
    local integration = integrations.aws or {}
    local children = {
      integrationDetailHeader(tr("panel.integrations.aws.title"), "cloud", integration),
      ui.label({ text = tr("panel.integrations.aws.description"), color = "on_surface_variant", maxLines = 3 }),
      ui.label({
        text = tr("panel.integrations.profiles", { profiles = integrationProfileNames(integration) }),
        fontSize = 13,
        color = "on_surface_variant",
      }),
      ui.button({
        text = integration.configured == true
          and tr("panel.integrations.aws.resync")
          or tr("panel.integrations.aws.setup"),
        glyph = "cloud-upload",
        variant = "primary",
        controlSize = "sm",
        enabled = enabled and integration.available == true,
        onClick = "onAwsSyncClicked",
      }),
    }
    appendAwsAliasEditor(children, integration, enabled)
    return card(children)
  end

  if activeIntegration == "windows" then
    local integration = integrations.windowsVm or {}
    local available = enabled and integration.available == true
    local credentialStored = integration.credentialStored == true
    local showCredentialEditor = not credentialStored or windowsCredentialEditorOpen
    local children = {
      integrationDetailHeader(tr("panel.integrations.windows.title"), "device-desktop", integration),
      ui.label({ text = tr("panel.integrations.windows.description"), color = "on_surface_variant", maxLines = 3 }),
      ui.label({
        text = integration.available == true
          and tr("panel.integrations.windows.ready")
          or tr("panel.integrations.windows.install"),
        fontSize = 13,
        color = "on_surface_variant",
        maxLines = 3,
      }),
      ui.separator({ spacing = 2 }),
    }

    table.insert(children, ui.label({
      text = credentialStored
        and tr("panel.integrations.windows.access_ready_title")
        or tr("panel.integrations.windows.access_title"),
      fontWeight = "bold",
      color = "on_surface",
    }))

    if credentialStored and not showCredentialEditor then
      table.insert(children, ui.label({
        text = integration.rdpResilience == true
          and tr("panel.integrations.windows.access_ready_description")
          or tr("panel.integrations.windows.access_pending_resilience"),
        fontSize = 13,
        color = "on_surface_variant",
        maxLines = 4,
      }))
      table.insert(children, ui.button({
        text = tr("panel.integrations.windows.manage_access"),
        glyph = "key",
        variant = "ghost",
        controlSize = "sm",
        enabled = available,
        onClick = "onWindowsCredentialManageClicked",
      }))
    else
      table.insert(children, ui.label({
        text = credentialStored
          and tr("panel.integrations.windows.manage_access_description")
          or tr("panel.integrations.windows.onboarding_description"),
        fontSize = 13,
        color = "on_surface_variant",
        maxLines = 4,
      }))
      table.insert(children, ui.label({
        text = tr("panel.integrations.windows.username"),
        color = "on_surface_variant",
        fontSize = 11,
      }))
      table.insert(children, ui.input({
        key = "windows-rdp-username",
        value = rdpUsername,
        placeholder = tr("panel.integrations.windows.username_placeholder"),
        controlSize = "sm",
        enabled = available,
        onChange = function(value)
          rdpUsername = value
          confirmingWindowsUnlock = false
          confirmingWindowsPasswordReset = false
          confirmingWindowsWipe = false
        end,
      }))
      table.insert(children, ui.label({
        text = tr("panel.integrations.windows.password"),
        color = "on_surface_variant",
        fontSize = 11,
      }))
      table.insert(children, ui.input({
        key = "windows-rdp-password-" .. tostring(rdpPasswordRevision),
        value = rdpPassword,
        placeholder = credentialStored
          and tr("panel.integrations.windows.password_new_placeholder")
          or tr("panel.integrations.windows.password_once_placeholder"),
        password = true,
        controlSize = "sm",
        enabled = available,
        onChange = function(value)
          rdpPassword = value
          confirmingWindowsUnlock = false
          confirmingWindowsPasswordReset = false
          confirmingWindowsWipe = false
        end,
      }))

      if credentialStored then
        table.insert(children, ui.row({ gap = 8 }, {
          ui.button({
            text = tr("panel.integrations.windows.password_reset"),
            glyph = "key",
            variant = "secondary",
            controlSize = "sm",
            enabled = available and windowsRdpCredentialsReady(),
            flexGrow = 1,
            onClick = "onWindowsPasswordResetClicked",
          }),
          ui.button({
            text = "WIPE WindowsVM",
            glyph = "trash",
            variant = "destructive",
            controlSize = "sm",
            enabled = available and windowsRdpCredentialsReady(),
            flexGrow = 1,
            onClick = "onWindowsWipeClicked",
          }),
        }))
        table.insert(children, ui.button({
          text = tr("panel.integrations.windows.manage_access_cancel"),
          variant = "ghost",
          controlSize = "sm",
          onClick = "onWindowsCredentialManageCancelClicked",
        }))
      end
    end

    if confirmingWindowsPasswordReset then
      table.insert(children, ui.column({
        fill = "error/0.10",
        radius = 8,
        padding = 10,
        gap = 8,
      }, {
        ui.label({
          text = tr("panel.integrations.windows.password_reset_confirm_title"),
          color = "on_surface",
          fontWeight = "bold",
        }),
        ui.label({
          text = tr("panel.integrations.windows.password_reset_confirm_body"),
          color = "on_surface_variant",
          fontSize = 12,
          maxLines = 6,
        }),
        ui.row({ gap = 8 }, {
          ui.button({
            text = tr("panel.integrations.windows.password_reset_cancel"),
            variant = "ghost",
            controlSize = "sm",
            flexGrow = 1,
            onClick = "onWindowsPasswordResetCancelClicked",
          }),
          ui.button({
            text = tr("panel.integrations.windows.password_reset_confirm"),
            variant = "destructive",
            controlSize = "sm",
            flexGrow = 1,
            onClick = "onWindowsPasswordResetConfirmClicked",
          }),
        }),
      }))
    end

    if confirmingWindowsWipe then
      table.insert(children, ui.column({
        fill = "error/0.14",
        radius = 8,
        padding = 10,
        gap = 8,
      }, {
        ui.label({
          text = tr("panel.integrations.windows.wipe_confirm_title"),
          color = "error",
          fontWeight = "bold",
        }),
        ui.label({
          text = tr("panel.integrations.windows.wipe_confirm_body"),
          color = "on_surface_variant",
          fontSize = 12,
          maxLines = 7,
        }),
        ui.input({
          key = "windows-wipe-confirmation-" .. tostring(windowsWipeConfirmationRevision),
          value = windowsWipeConfirmation,
          placeholder = "WIPE",
          controlSize = "sm",
          onChange = function(value)
            windowsWipeConfirmation = value
            render()
          end,
        }),
        ui.row({ gap = 8 }, {
          ui.button({
            text = tr("panel.integrations.windows.wipe_cancel"),
            variant = "ghost",
            controlSize = "sm",
            flexGrow = 1,
            onClick = "onWindowsWipeCancelClicked",
          }),
          ui.button({
            text = tr("panel.integrations.windows.wipe_confirm"),
            variant = "destructive",
            controlSize = "sm",
            enabled = windowsWipeConfirmation == "WIPE",
            flexGrow = 1,
            onClick = "onWindowsWipeConfirmClicked",
          }),
        }),
      }))
    end

    table.insert(children, ui.separator({ spacing = 2 }))
    table.insert(children, ui.label({
      text = tr("panel.integrations.windows.display_title"),
      fontWeight = "bold",
      color = "on_surface",
    }))
    table.insert(children, ui.label({
      text = tr("panel.integrations.windows.display_description"),
      fontSize = 13,
      color = "on_surface_variant",
      maxLines = 3,
    }))
    table.insert(children, ui.select({
      key = "windows-rdp-display-mode",
      options = rdpDisplayModeOptions,
      selectedIndex = selectedRdpDisplayModeIndex,
      controlSize = "sm",
      enabled = available,
      onChange = "onWindowsRdpDisplayModeChanged",
    }))
    table.insert(children, ui.separator({ spacing = 2 }))
    table.insert(children, ui.row({ gap = 8 }, {
      ui.button({
        text = credentialStored
          and tr("panel.integrations.windows.open")
          or tr("panel.integrations.windows.onboarding_open"),
        glyph = "device-desktop",
        variant = "primary",
        controlSize = "sm",
        enabled = available and (credentialStored or windowsRdpCredentialsReady()),
        flexGrow = 2,
        onClick = "onWindowsUpClicked",
      }),
      ui.button({
        text = tr("panel.integrations.windows.web"),
        controlSize = "sm",
        enabled = available,
        flexGrow = 1,
        onClick = "onWindowsWebClicked",
      }),
    }))
    table.insert(children, ui.row({ gap = 8 }, {
      ui.button({
        text = tr("panel.integrations.windows.status"),
        variant = "ghost",
        controlSize = "sm",
        enabled = available,
        flexGrow = 1,
        onClick = "onWindowsStatusClicked",
      }),
      ui.button({
        text = tr("panel.integrations.windows.logs"),
        variant = "ghost",
        controlSize = "sm",
        enabled = available,
        flexGrow = 1,
        onClick = "onWindowsLogsClicked",
      }),
      ui.button({
        text = tr("panel.integrations.windows.stop"),
        variant = "destructive",
        controlSize = "sm",
        enabled = available,
        flexGrow = 1,
        onClick = "onWindowsDownClicked",
      }),
    }))

    return card(children)
  end

  local integration = integrations.github or {}
  return card({
    integrationDetailHeader(tr("panel.integrations.github.title"), "brand-github", integration),
    ui.label({ text = tr("panel.integrations.github.description"), color = "on_surface_variant", maxLines = 3 }),
    ui.label({
      text = tr("panel.integrations.profiles", { profiles = integrationProfileNames(integration) }),
      fontSize = 13,
      color = "on_surface_variant",
    }),
    ui.button({
      text = tr("panel.integrations.configure"),
      glyph = "settings",
      variant = "primary",
      controlSize = "sm",
      enabled = enabled and integration.available == true,
      onClick = "onGithubSetupClicked",
    }),
  })
end

local function integrationsView()
  return {
    ui.column({ fill = "surface_variant/0.52", radius = 9, padding = 4, gap = 4 }, {
      ui.row({ gap = 4 }, {
        integrationPickerButton("github", tr("panel.integrations.github.title"), "brand-github", "onSelectGithub"),
        integrationPickerButton("gitlab", tr("panel.integrations.gitlab.title"), "brand-gitlab", "onSelectGitlab"),
      }),
      ui.row({ gap = 4 }, {
        integrationPickerButton("aws", tr("panel.integrations.aws.title"), "cloud", "onSelectAws"),
        integrationPickerButton("windows", tr("panel.integrations.windows.short_title"), "device-desktop", "onSelectWindows"),
      }),
    }),
    integrationDetail(),
    card({
      ui.label({ text = tr("panel.integrations.tools"), fontWeight = "bold", color = "on_surface" }),
      ui.label({
        text = tr("panel.integrations.tools_description"),
        fontSize = 13,
        color = "on_surface_variant",
        maxLines = 3,
      }),
      ui.row({ gap = 8 }, {
        ui.button({
          text = tr("panel.integrations.setup_all"),
          variant = "secondary",
          controlSize = "sm",
          enabled = backendAvailable and not busy,
          flexGrow = 1,
          onClick = "onHolodeckSetupClicked",
        }),
        ui.button({
          text = tr("panel.integrations.doctor"),
          variant = "ghost",
          controlSize = "sm",
          enabled = backendAvailable and not busy,
          flexGrow = 1,
          onClick = "onHolodeckDoctorClicked",
        }),
      }),
    }),
  }
end

local function navigationButton(id, tooltip, glyph, callback)
  return ui.button({
    key = "nav-" .. id,
    glyph = glyph,
    tooltip = tooltip,
    variant = "ghost",
    selected = activeView == id,
    controlSize = "sm",
    width = 32,
    onClick = callback,
  })
end

local function activeViewTitle()
  if activeView == "system" then
    return tr("panel.system.title")
  end
  if activeView == "integrations" then
    return tr("panel.integrations.title")
  end
  return tr("panel.overview.title")
end

local function activeViewDescription()
  if activeView == "system" then
    return tr("panel.system.description")
  end
  if activeView == "integrations" then
    return tr("panel.integrations.description")
  end
  return tr("panel.overview.description")
end

render = function()
  local body = feedbackCards()
  local viewNodes = overviewView()
  if activeView == "system" then
    viewNodes = systemView()
  elseif activeView == "integrations" then
    viewNodes = integrationsView()
  end
  for _, node in ipairs(viewNodes) do
    table.insert(body, node)
  end

  panel.render(ui.row({ flexGrow = 1, gap = 14, align = "stretch" }, {
    ui.column({ fill = "surface_variant/0.72", radius = 12, padding = 12, gap = 6, width = 56, align = "center" }, {
      ui.image({
        path = "assets/holodeck-control-compact.png",
        width = 28,
        height = 28,
        radius = 5,
        fit = "contain",
      }),
      ui.separator({ spacing = 4 }),
      navigationButton("overview", tr("panel.nav.overview"), "layout-dashboard", "onShowOverview"),
      navigationButton("system", tr("panel.nav.system"), "device-desktop-cog", "onShowSystem"),
      navigationButton("integrations", tr("panel.nav.integrations"), "plug-connected", "onShowIntegrations"),
      ui.spacer({ flexGrow = 1 }),
      ui.label({ text = "v0.8.0", fontSize = 11, color = "on_surface_variant" }),
    }),
    ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
      ui.row({ align = "center", gap = 8 }, {
        ui.image({
          path = "assets/holodeck-control.png",
          width = 34,
          height = 34,
          radius = 7,
          fit = "contain",
        }),
        ui.column({ gap = 2, flexGrow = 1 }, {
          ui.label({ text = activeViewTitle(), fontSize = 16, fontWeight = "bold", color = "primary" }),
          ui.label({ text = activeViewDescription(), fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
        }),
        ui.label({
          text = tr("panel.working"),
          fontSize = 11,
          color = "on_surface_variant",
          visible = busy,
        }),
        ui.button({
          glyph = "refresh",
          tooltip = tr("panel.refresh"),
          variant = "ghost",
          controlSize = "sm",
          enabled = not busy,
          onClick = "onRefreshClicked",
        }),
        ui.button({
          glyph = "close",
          tooltip = tr("panel.close"),
          variant = "ghost",
          controlSize = "sm",
          onClick = "onCloseClicked",
        }),
      }),
      ui.scroll({ flexGrow = 1, gap = 12 }, body),
    }),
  }))
end

local function showView(view)
  if activeView == "integrations" and activeIntegration == "windows" and view ~= "integrations" then
    clearWindowsRdpPassword()
  end
  activeView = view
  if view ~= "system" then
    confirmingApply = false
    pendingPlan = nil
    planSummary = ""
  end
  render()
end

local function selectIntegration(id)
  if activeIntegration == "windows" and id ~= "windows" then
    clearWindowsRdpPassword()
  end
  activeIntegration = id
  render()
end

function onOpen(_context)
  noctalia.setUpdateInterval(2000)
  backendAvailable = noctalia.fileExists(CONFIGCTL)
  local pluginData = noctalia.pluginDataDir()
  if type(pluginData) == "string" and pluginData ~= "" then
    awsAliasRequestPath = pluginData .. "/aws-alias-request.json"
  end
  local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
  if type(runtimeDir) == "string" and string.sub(runtimeDir, 1, 1) == "/" then
    rdpCredentialRequestPath = runtimeDir .. "/holodeck-control-windows-rdp.json"
  else
    rdpCredentialRequestPath = ""
  end
  rdpUsername = "Docker"
  clearWindowsRdpPassword()
  activeView = "overview"
  render()
  loadStatus(false)
end

function update()
  pollAwsSyncStatus()
end

function onShowOverview()
  showView("overview")
end

function onShowSystem()
  showView("system")
end

function onShowIntegrations()
  showView("integrations")
end

function onSelectGithub()
  selectIntegration("github")
end

function onSelectGitlab()
  selectIntegration("gitlab")
end

function onSelectAws()
  selectIntegration("aws")
end

function onSelectWindows()
  selectIntegration("windows")
end

function onTargetChanged(index, _text)
  local parsed = tonumber(index)
  if parsed == 0 or parsed == 1 then
    selectedTargetIndex = parsed
    recomputeDirty()
    confirmingApply = false
    pendingPlan = nil
    planSummary = ""
    render()
  end
end

function onModeChanged(index, _text)
  local parsed = tonumber(index)
  if parsed == 0 or parsed == 1 then
    selectedModeIndex = parsed
    recomputeDirty()
    confirmingApply = false
    pendingPlan = nil
    planSummary = ""
    render()
  end
end

function onRefreshClicked()
  loadStatus(true)
end

function onSaveClicked()
  if busy or not backendAvailable then
    return
  end

  busy = true
  currentError = ""
  notice = ""
  confirmingApply = false
  pendingPlan = nil
  planSummary = ""
  render()

  local targetAction = selectedTargetIndex == 1 and "targetExisting" or "targetHome"
  local modeAction = selectedModeIndex == 1 and "modeLight" or "modeDark"

  runAllowed("init", function(initPayload)
    if type(initPayload.irPath) == "string" then
      irPath = initPayload.irPath
    end
    runAllowed(targetAction, function(_targetPayload)
      runAllowed(modeAction, function(modePayload)
        setSelectionsFromIr(modePayload.ir)
        statusExists = true
        statusSource = "file"
        recomputeDirty()
        busy = false
        notice = tr("notice.ir_saved")
        render()
      end)
    end)
  end)
end

function onPlanClicked()
  if busy or dirty or not statusExists then
    return
  end

  busy = true
  currentError = ""
  notice = ""
  confirmingApply = false
  pendingPlan = nil
  planSummary = ""
  render()

  runAllowed("plan", function(payload)
    local plan = payload.plan
    if type(plan) ~= "table"
      or (plan.target ~= "home-manager" and plan.target ~= "existing-nixos") then
      fail(tr("error.invalid_plan"))
      return
    end

    local elevation = plan.requiresElevation == true and tr("common.yes") or tr("common.no")
    local digest = type(plan.irDigest) == "string" and plan.irDigest or "-"
    planSummary = tr("panel.plan.summary", {
      target = plan.target,
      elevation = elevation,
      digest = digest,
    })
    pendingPlan = plan
    confirmingApply = true
    busy = false
    render()
  end)
end

function onCancelApply()
  confirmingApply = false
  pendingPlan = nil
  notice = tr("notice.apply_cancelled")
  render()
end

function onConfirmApply()
  if busy or not confirmingApply or pendingPlan == nil then
    return
  end

  -- The plan is informational. Never execute plan.argv: the only executable
  -- path is the fixed allowlisted backend command declared above.
  local opened = noctalia.runInTerminal(COMMANDS.apply)
  confirmingApply = false
  pendingPlan = nil
  if opened then
    notice = tr("notice.terminal_opened")
    currentError = ""
  else
    notice = ""
    currentError = tr("error.terminal_not_started")
  end
  render()
end

function onHolodeckSetupClicked()
  openTerminalAction("holodeckSetup")
end

function onHolodeckDoctorClicked()
  openTerminalAction("holodeckDoctor")
end

function onGithubSetupClicked()
  openTerminalAction("githubSetup")
end

function onGitlabSetupClicked()
  openTerminalAction("gitlabSetup")
end

function onAwsSyncClicked()
  awsAliasEditorOpen = false
  openTerminalAction("awsSync")
end

function onAwsAliasEditorClicked()
  awsAliasEditorOpen = not awsAliasEditorOpen
  render()
end

function onAwsRecommendAllClicked()
  for _, profile in ipairs(awsAliasRecords(integrations.aws or {})) do
    awsAliasDraft[profile.key] = profile.suggestedAlias
    awsAliasRevision[profile.key] = (awsAliasRevision[profile.key] or 0) + 1
  end
  render()
end

function onAwsOriginalAllClicked()
  for _, profile in ipairs(awsAliasRecords(integrations.aws or {})) do
    awsAliasDraft[profile.key] = profile.defaultAlias
    awsAliasRevision[profile.key] = (awsAliasRevision[profile.key] or 0) + 1
  end
  render()
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
    notice = tr("notice.aws_aliases_saved")
    render()
  end)
end

function onWindowsUpClicked()
  openWindowsRdpAction("windowsUp")
end

function onWindowsStatusClicked()
  openTerminalAction("windowsStatus")
end

function onWindowsRdpClicked()
  openWindowsRdpAction("windowsRdp")
end

function onWindowsCredentialManageClicked()
  windowsCredentialEditorOpen = true
  confirmingWindowsUnlock = false
  confirmingWindowsPasswordReset = false
  confirmingWindowsWipe = false
  currentError = ""
  notice = ""
  render()
end

function onWindowsCredentialManageCancelClicked()
  clearWindowsRdpPassword()
  notice = tr("notice.windows_credentials_unchanged")
  render()
end

function onWindowsUnlockClicked()
  confirmingWindowsUnlock = true
  confirmingWindowsPasswordReset = false
  confirmingWindowsWipe = false
  currentError = ""
  notice = ""
  render()
end

function onWindowsUnlockCancelClicked()
  confirmingWindowsUnlock = false
  notice = tr("notice.windows_unlock_cancelled")
  render()
end

function onWindowsUnlockConfirmClicked()
  if not confirmingWindowsUnlock then
    return
  end
  openWindowsUnlockAction()
end

function onWindowsPasswordResetClicked()
  if not windowsRdpCredentialsReady() then
    fail(tr("error.rdp_credentials_required"))
    return
  end
  confirmingWindowsUnlock = false
  confirmingWindowsPasswordReset = true
  confirmingWindowsWipe = false
  currentError = ""
  notice = ""
  render()
end

function onWindowsPasswordResetCancelClicked()
  confirmingWindowsPasswordReset = false
  notice = tr("notice.windows_password_reset_cancelled")
  render()
end

function onWindowsPasswordResetConfirmClicked()
  if not confirmingWindowsPasswordReset then
    return
  end
  openWindowsPasswordResetAction()
end

function onWindowsWipeClicked()
  if not windowsRdpCredentialsReady() then
    fail(tr("error.rdp_credentials_required"))
    return
  end
  confirmingWindowsUnlock = false
  confirmingWindowsPasswordReset = false
  confirmingWindowsWipe = true
  windowsWipeConfirmation = ""
  windowsWipeConfirmationRevision = windowsWipeConfirmationRevision + 1
  currentError = ""
  notice = ""
  render()
end

function onWindowsWipeCancelClicked()
  confirmingWindowsWipe = false
  windowsWipeConfirmation = ""
  windowsWipeConfirmationRevision = windowsWipeConfirmationRevision + 1
  notice = tr("notice.windows_wipe_cancelled")
  render()
end

function onWindowsWipeConfirmClicked()
  if not confirmingWindowsWipe then
    return
  end
  if windowsWipeConfirmation ~= "WIPE" then
    currentError = tr("error.windows_wipe_confirmation_required")
    notice = ""
    render()
    return
  end
  openWindowsWipeAction()
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
    notice = tr("notice.windows_rdp_display_saved")
    render()
  end)
end

function onWindowsWebClicked()
  openGraphicalAction("windowsWeb")
end

function onWindowsLogsClicked()
  openTerminalAction("windowsLogs")
end

function onWindowsDownClicked()
  openTerminalAction("windowsDown")
end

function onCloseClicked()
  clearWindowsRdpPassword()
  panel.close()
end
