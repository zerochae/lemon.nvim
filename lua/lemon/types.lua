---@meta

---@class Lemon.Config
---@field hover Lemon.HoverConfig
---@field diagnostic Lemon.DiagnosticConfig
---@field definition Lemon.DefinitionConfig
---@field code_action Lemon.CodeActionConfig
---@field symbol_icons table<string, string>
---@field parsers table<string, Lemon.TagDef>
---@field highlights table<string, table>
---@field glyph table
---@class Lemon.FooterConfig
---@field enabled boolean
---@field show_desc boolean

---@class Lemon.BasePanelConfig
---@field border string
---@field max_width number
---@field max_height number
---@field pad_right number
---@field scroll_indicator boolean
---@field close_events string[]
---@field close_key string
---@field show_server boolean
---@field show_filetype boolean
---@field hide_diagnostic boolean

---@class Lemon.HoverConfig : Lemon.BasePanelConfig
---@field show_symbol boolean

---@class Lemon.DiagnosticConfig : Lemon.BasePanelConfig
---@field confirm_key string
---@field footer Lemon.FooterConfig

---@class Lemon.CodeActionConfig : Lemon.BasePanelConfig
---@field footer Lemon.FooterConfig
---@field confirm_key string
---@field back_key string
---@field diff_context number
---@field show_code boolean

---@class Lemon.DefinitionConfig
---@field beacon Lemon.BeaconConfig
---@field tagstack boolean

---@class Lemon.BeaconConfig
---@field enabled boolean
---@field fade_interval number
---@field fade_step number

---@class Lemon.TagDef
---@field icon string
---@field hl string

---@class Lemon.FloatPanel
---@field name string
---@field win number|nil
---@field buf number|nil
---@field source_bufnr number|nil
---@field augroup number|nil
---@field _enter boolean
---@field close fun(self: Lemon.FloatPanel)
---@field is_open fun(self: Lemon.FloatPanel): boolean
---@field show fun(self: Lemon.FloatPanel, source_bufnr: number, ...)
---@field build_content fun(self: Lemon.FloatPanel, ...): string[], table[]
---@field get_config fun(self: Lemon.FloatPanel): Lemon.PanelConfig
---@field setup_keymaps fun(self: Lemon.FloatPanel)
---@field after_open fun(self: Lemon.FloatPanel)
---@field apply_extmarks fun(self: Lemon.FloatPanel, ext_list: table[], lines: string[])
---@field resize fun(self: Lemon.FloatPanel, w: number, h: number)
---@field append_lines fun(self: Lemon.FloatPanel, lines: string[])
---@field _actions table[]|nil
---@field _meta table[]|nil
---@field _meta_count number|nil
---@field _cursor_pos number[]|nil
---@field _action_start_line number

---@class Lemon.PanelConfig
---@field border string
---@field max_width number
---@field max_height number
---@field pad_right number
---@field min_width? number
---@field min_height? number
---@field extra_height? number
---@field close_key string
---@field close_events string[]
---@field scroll_indicator boolean
---@field conceal? boolean
---@field cursorline? boolean
---@field enter? boolean
---@field diff_context? number
---@field confirm_key? string
---@field back_key? string
---@field hide_diagnostic? boolean

---@class Lemon.PreviewManager
---@field panel Lemon.FloatPanel
---@field action_cache table[]
---@field resolve_cache table<number, table>
---@field diff_cache table<number, table>
---@field current_idx number
---@field updating boolean
---@field list_end_line number
