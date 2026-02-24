---@meta

---@class Lemon.Config
---@field hover Lemon.HoverConfig
---@field definition Lemon.DefinitionConfig
---@field code_action Lemon.CodeActionConfig
---@field meta Lemon.MetaConfig
---@field symbol_icons table<string, string>
---@field parsers table<string, Lemon.TagDef>
---@field highlights table<string, table>

---@class Lemon.HoverConfig
---@field border string
---@field max_width number
---@field max_height number
---@field pad_right number
---@field scroll_indicator boolean
---@field close_events string[]
---@field close_key string

---@class Lemon.DefinitionConfig
---@field beacon Lemon.BeaconConfig
---@field tagstack boolean

---@class Lemon.BeaconConfig
---@field enabled boolean
---@field fade_interval number
---@field fade_step number

---@class Lemon.MetaConfig
---@field show_server boolean
---@field show_filetype boolean
---@field show_symbol boolean

---@class Lemon.CodeActionConfig
---@field border string
---@field max_width number
---@field max_height number
---@field pad_right number
---@field scroll_indicator boolean
---@field close_events string[]
---@field close_key string
---@field confirm_key string
---@field back_key string
---@field diff_context number

---@class Lemon.TagDef
---@field icon string
---@field hl string
