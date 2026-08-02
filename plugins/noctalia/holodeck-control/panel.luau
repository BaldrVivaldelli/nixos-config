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
  awsConfigure = CONFIGCTL .. " action aws-configure",
  awsLogin = CONFIGCTL .. " action aws-login",
  awsIdentity = CONFIGCTL .. " action aws-identity",
  windowsUp = CONFIGCTL .. " action windows-up",
  windowsStatus = CONFIGCTL .. " action windows-status",
  windowsRdp = CONFIGCTL .. " action windows-rdp",
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
local activeView = "overview"
local activeIntegration = "github"
local integrations = {
  aws = { available = false, configured = false, profiles = {} },
  github = { available = false, configured = false, profiles = {} },
  gitlab = { available = false, configured = false, profiles = {} },
  windowsVm = { available = false, configured = false },
}

local render

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
    notice = tr("notice.integration_terminal")
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
    statusExists = payload.exists == true
    irPath = type(payload.irPath) == "string" and payload.irPath or ""
    statusSource = type(payload.source) == "string" and payload.source or ""
    if type(payload.integrations) == "table" then
      integrations = payload.integrations
    end
    setSelectionsFromIr(payload.ir or payload.effective)
    recomputeDirty()
    busy = false
    notice = statusExists
      and (reportSuccess == true and tr("notice.status_loaded") or "")
      or tr("notice.ir_missing")
    render()
  end)
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

local function integrationDetail()
  local enabled = backendAvailable and not busy

  if activeIntegration == "gitlab" then
    local integration = integrations.gitlab or {}
    return card({
      integrationDetailHeader(tr("panel.integrations.gitlab.title"), "brand-gitlab", integration),
      ui.label({ text = tr("panel.integrations.gitlab.description"), color = "on_surface_variant", maxLines = 3 }),
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
        onClick = "onGitlabSetupClicked",
      }),
    })
  end

  if activeIntegration == "aws" then
    local integration = integrations.aws or {}
    return card({
      integrationDetailHeader(tr("panel.integrations.aws.title"), "cloud", integration),
      ui.label({ text = tr("panel.integrations.aws.description"), color = "on_surface_variant", maxLines = 3 }),
      ui.label({
        text = tr("panel.integrations.profiles", { profiles = integrationProfileNames(integration) }),
        fontSize = 13,
        color = "on_surface_variant",
      }),
      ui.row({ gap = 8 }, {
        ui.button({
          text = tr("panel.integrations.configure"),
          glyph = "settings",
          variant = integration.configured == true and "default" or "primary",
          controlSize = "sm",
          enabled = enabled and integration.available == true,
          flexGrow = 1,
          onClick = "onAwsConfigureClicked",
        }),
        ui.button({
          text = tr("panel.integrations.login"),
          variant = integration.configured == true and "primary" or "default",
          controlSize = "sm",
          enabled = enabled and integration.configured == true,
          flexGrow = 1,
          onClick = "onAwsLoginClicked",
        }),
        ui.button({
          text = tr("panel.integrations.identity"),
          variant = "ghost",
          controlSize = "sm",
          enabled = enabled and integration.configured == true,
          flexGrow = 1,
          onClick = "onAwsIdentityClicked",
        }),
      }),
    })
  end

  if activeIntegration == "windows" then
    local integration = integrations.windowsVm or {}
    local available = enabled and integration.available == true
    return card({
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
      ui.label({
        text = tr("panel.integrations.windows.display_title"),
        fontWeight = "bold",
        color = "on_surface",
      }),
      ui.label({
        text = tr("panel.integrations.windows.display_description"),
        fontSize = 13,
        color = "on_surface_variant",
        maxLines = 3,
      }),
      ui.select({
        key = "windows-rdp-display-mode",
        options = rdpDisplayModeOptions,
        selectedIndex = selectedRdpDisplayModeIndex,
        controlSize = "sm",
        enabled = available,
        onChange = "onWindowsRdpDisplayModeChanged",
      }),
      ui.separator({ spacing = 2 }),
      ui.row({ gap = 8 }, {
        ui.button({
          text = tr("panel.integrations.windows.open"),
          variant = "primary",
          controlSize = "sm",
          enabled = available,
          flexGrow = 1,
          onClick = "onWindowsUpClicked",
        }),
        ui.button({
          text = "RDP",
          controlSize = "sm",
          enabled = available,
          flexGrow = 1,
          onClick = "onWindowsRdpClicked",
        }),
        ui.button({
          text = tr("panel.integrations.windows.web"),
          controlSize = "sm",
          enabled = available,
          flexGrow = 1,
          onClick = "onWindowsWebClicked",
        }),
      }),
      ui.row({ gap = 8 }, {
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
      }),
    })
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
      ui.label({ text = "v0.4.6", fontSize = 11, color = "on_surface_variant" }),
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
  activeView = view
  if view ~= "system" then
    confirmingApply = false
    pendingPlan = nil
    planSummary = ""
  end
  render()
end

local function selectIntegration(id)
  activeIntegration = id
  render()
end

function onOpen(_context)
  backendAvailable = noctalia.fileExists(CONFIGCTL)
  activeView = "overview"
  render()
  loadStatus(false)
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

function onAwsConfigureClicked()
  openTerminalAction("awsConfigure")
end

function onAwsLoginClicked()
  openTerminalAction("awsLogin")
end

function onAwsIdentityClicked()
  openTerminalAction("awsIdentity")
end

function onWindowsUpClicked()
  openTerminalAction("windowsUp")
end

function onWindowsStatusClicked()
  openTerminalAction("windowsStatus")
end

function onWindowsRdpClicked()
  openGraphicalAction("windowsRdp")
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
  panel.close()
end
