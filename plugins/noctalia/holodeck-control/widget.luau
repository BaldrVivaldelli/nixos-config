--!nonstrict

function update()
  barWidget.setGlyph("cube-spark")
  barWidget.setGlyphColor("on_surface")
  barWidget.setTooltip(noctalia.tr("widget.tooltip"))
end

function onClick()
  noctalia.togglePanel("holodeck/control:control")
end
