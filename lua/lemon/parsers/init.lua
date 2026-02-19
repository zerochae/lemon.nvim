local M = {}

local registered = {}

---@param name string
---@param tags table<string, Lemon.TagDef>
function M.register(name, tags)
  registered[name] = tags
end

---@return table<string, Lemon.TagDef>
function M.get_all_tags()
  local merged = {}

  local builtins = { "jsdoc", "doxygen", "python" }
  for _, name in ipairs(builtins) do
    local ok, parser = pcall(require, "lemon.parsers." .. name)
    if ok then
      for pattern, tag_cfg in pairs(parser) do
        merged[pattern] = tag_cfg
      end
    end
  end

  for _, tags in pairs(registered) do
    for pattern, tag_cfg in pairs(tags) do
      merged[pattern] = tag_cfg
    end
  end

  local cfg = require("lemon.config").get()
  if cfg.parsers then
    for pattern, tag_cfg in pairs(cfg.parsers) do
      merged[pattern] = tag_cfg
    end
  end

  return merged
end

return M
