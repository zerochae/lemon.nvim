local M = {}

local color = require "lemon.ui.color"

local type_hl_sources = {
  number = { "@number", "Number" },
  string = { "@string", "String" },
  boolean = { "@boolean", "Boolean" },
  null = { "@constant.builtin", "Constant" },
  undefined = { "@constant.builtin", "Constant" },
  unknown = { "DiagnosticWarn", "@type" },
  never = { "DiagnosticError", "@constant.builtin" },
  array = { "@type", "Type" },
  object = { "@type", "Type" },
  ["function"] = { "@function", "Function" },
  promise = { "@type", "Type" },
}

local function resolve_hl_fg(sources, fallback)
  for _, name in ipairs(sources) do
    local fg = color.get_hl_color(name, "fg")
    if fg then
      return fg
    end
  end
  return fallback
end

local function create_badge_highlights()
  local normal_bg = color.get_hl_color("Normal", "bg") or "#1e1e2e"
  local comment_fg = color.get_hl_color("Comment", "fg") or "#6c7086"

  local cfg = require("lemon.config").get()
  local alpha = cfg.inlay_hint.badge_alpha

  local blue_tint = "#4fc1ff"
  local warm_tint = "#e5c07b"

  local blended_blue_bg = color.blend(blue_tint, normal_bg, alpha)
  local blended_warm_bg = color.blend(warm_tint, normal_bg, alpha)
  local blended_blue_fg = color.blend(blue_tint, comment_fg, 0.4)
  local blended_warm_fg = color.blend(warm_tint, comment_fg, 0.4)

  local badge_groups = {
    LemonInlayType = { fg = blended_blue_fg, bg = blended_blue_bg, italic = true },
    LemonInlayParam = { fg = blended_warm_fg, bg = blended_warm_bg, italic = true },
  }

  for kind, sources in pairs(type_hl_sources) do
    local src_fg = resolve_hl_fg(sources, blue_tint)
    local name = "LemonInlayType_" .. kind
    badge_groups[name] = {
      fg = color.blend(src_fg, comment_fg, 0.4),
      bg = color.blend(src_fg, normal_bg, alpha),
      italic = true,
    }
  end

  local fn_bg = badge_groups["LemonInlayType_function"].bg
  local operator_fg = resolve_hl_fg({ "@operator.tsx", "@operator" }, comment_fg)
  badge_groups["LemonInlayTypeOperator"] = {
    fg = color.blend(operator_fg, fn_bg, 0.7),
    bg = fn_bg,
  }

  for kind, sources in pairs(type_hl_sources) do
    if kind ~= "function" then
      local src_fg = resolve_hl_fg(sources, blue_tint)
      badge_groups["LemonInlayTypeFnRet_" .. kind] = {
        fg = color.blend(src_fg, comment_fg, 0.4),
        bg = fn_bg,
        italic = true,
      }
    end
  end

  local obj_bg = badge_groups["LemonInlayType_object"].bg
  for kind, sources in pairs(type_hl_sources) do
    local src_fg = resolve_hl_fg(sources, blue_tint)
    badge_groups["LemonInlayTypeObjField_" .. kind] = {
      fg = color.blend(src_fg, comment_fg, 0.4),
      bg = obj_bg,
      italic = true,
    }
  end

  badge_groups["LemonInlayTypeObjOperator"] = {
    fg = color.blend(operator_fg, obj_bg, 0.7),
    bg = obj_bg,
  }

  local user_overrides = cfg.highlights or {}

  for name, opts in pairs(badge_groups) do
    if not user_overrides[name] then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end
end

function M.setup()
  local highlights = {
    LemonNormal = { link = "NormalFloat" },
    LemonBorder = { link = "FloatBorder" },
    LemonTitle = { link = "Title" },
    LemonBeacon = { link = "Search" },
    LemonActionNumber = { link = "Number" },
    LemonDiffAdd = { link = "DiffAdd" },
    LemonDiffAddSign = { link = "Added" },
    LemonDiffDelete = { link = "DiffDelete" },
    LemonDiffDeleteSign = { link = "Removed" },
    LemonDiffHunk = { link = "Comment" },
    LemonDiffFile = { link = "Normal" },
    LemonFooterIcon = { link = "Function" },
    LemonFooterDesc = { link = "Comment" },
    LemonFooterKey = { link = "Function" },
    LemonSignatureActiveParam = { link = "LspSignatureActiveParameter" },
  }

  for name, opts in pairs(highlights) do
    local existing = vim.api.nvim_get_hl(0, { name = name })
    if vim.tbl_isempty(existing) then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  local cfg = require("lemon.config").get()
  if cfg.highlights then
    for name, opts in pairs(cfg.highlights) do
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  create_badge_highlights()

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("lemon_badge_colors", { clear = true }),
    callback = create_badge_highlights,
  })
end

return M
