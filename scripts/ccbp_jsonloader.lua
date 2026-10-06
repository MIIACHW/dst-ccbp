-- JSON 蓝图加载器
-- 读取 Base Projection 格式 JSON, 来源(按顺序尝试):
--   1. 游戏根目录 unsafedata/<name>.json   (Base Projection 约定目录)
--   2. 本MOD目录    blueprints/<name>.json
-- 文件发现方式(引擎没有目录枚举 API):
--   a. unsafedata/ccbp_index.json 索引: ["a.json", "b.json"]
--   b. 游戏内 UI 手动输入文件名 / c_ccbp_load 控制台命令
local CCBP = require "ccbp_config"
local Validator = require "ccbp_validator"

local Loader = {}

local function ReadFile(path)
    -- io 库在部分环境(某些专用服务器配置)下可能不可用, 做一层保护
    if type(io) ~= "table" or io.open == nil then
        return nil
    end
    local ok, f = pcall(io.open, path, "r")
    if ok and f ~= nil then
        local ok2, s = pcall(f.read, f, "*a")
        pcall(f.close, f)
        if ok2 then
            return s
        end
    end
    return nil
end

local function IsSafeName(name)
    if type(name) ~= "string" or #name == 0 or #name > 128 then
        return false
    end
    if string.find(name, "/", 1, true) or string.find(name, "\\", 1, true) then
        return false
    end
    if string.find(name, "..", 1, true) then
        return false
    end
    return true
end

local function NormalizeFileName(name)
    if string.sub(name, -5) ~= ".json" then
        name = name .. ".json"
    end
    return name
end

-- name: 文件名(可带可不带 .json), 返回 bp 或 nil, err
function Loader.ReadBlueprintFile(name)
    if not IsSafeName(name) then
        return nil, "文件名不合法"
    end
    local fname = NormalizeFileName(name)
    local stem = string.sub(fname, 1, -6)

    local raw_str = nil
    local dirs = { CCBP.JSON_DIR, CCBP.MOD_BP_DIR }
    for _, dir in ipairs(dirs) do
        if dir ~= nil and #dir > 0 then
            raw_str = ReadFile(dir .. fname)
            if raw_str ~= nil then
                break
            end
        end
    end
    if raw_str == nil then
        return nil, "找不到 " .. CCBP.JSON_DIR .. fname
    end

    local ok, raw = pcall(json.decode, raw_str)
    if not ok or type(raw) ~= "table" then
        return nil, "JSON 解析失败: " .. fname
    end

    return Validator.Validate(raw, stem)
end

local function LoadIndexNames()
    local names = {}
    local dirs = { CCBP.JSON_DIR, CCBP.MOD_BP_DIR }
    for _, dir in ipairs(dirs) do
        if dir ~= nil and #dir > 0 then
            local s = ReadFile(dir .. CCBP.INDEX_FILE)
            if s ~= nil then
                local ok, arr = pcall(json.decode, s)
                if ok and type(arr) == "table" then
                    for _, v in ipairs(arr) do
                        if type(v) == "string" then
                            names[#names + 1] = v
                        elseif type(v) == "table" and type(v.file) == "string" then
                            names[#names + 1] = v.file
                        end
                    end
                end
            end
        end
    end
    return names
end

-- 全量加载, 返回 bps(数组), errors({{name, err}})
function Loader.LoadAll()
    local names, seen = {}, {}
    local function add(n)
        if IsSafeName(n) then
            local key = string.lower(NormalizeFileName(n))
            if seen[key] == nil then
                seen[key] = true
                names[#names + 1] = n
            end
        end
    end

    for _, n in ipairs(LoadIndexNames()) do
        add(n)
    end

    local bps, errors = {}, {}
    for _, n in ipairs(names) do
        local bp, err = Loader.ReadBlueprintFile(n)
        if bp ~= nil then
            bps[#bps + 1] = bp
            if #bps >= CCBP.MAX_BLUEPRINTS then
                break
            end
        else
            errors[#errors + 1] = { name = n, err = err }
        end
    end
    return bps, errors
end

return Loader
