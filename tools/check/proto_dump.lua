-- Gibt alle eigenen Prototypen als JSON zurück (für tools/check/proto_fields.py).
-- Läuft nach dem kompletten Data-Lifecycle (datastage.py --dump DATEI).
--
-- Eigen ist ein Prototyp, wenn sein Name arrakis, spice oder melange enthält oder
-- wenn er aus einer Datei dieser Mod per data:extend angelegt wurde (ARRAKIS_SOURCES,
-- von datastage.py vor der Settings-Stage eingehängt). Die Settings-Prototypen liegen
-- bei draftsman nach der Settings-Stage weiter in data.raw; das Feld "value" setzt
-- draftsman selbst (compatibility/settings.lua) und wird hier entfernt.

local raw = data.raw
local sources = ARRAKIS_SOURCES or {}
local SETTING_TYPES = {["bool-setting"] = true, ["int-setting"] = true, ["double-setting"] = true,
  ["string-setting"] = true, ["color-setting"] = true}

local function by_name(n) return n:find("arrakis") or n:find("spice") or n:find("melange") end
local function is_own(t, n) return type(n) == "string" and (by_name(n) or sources[t .. "\0" .. n] ~= nil) end

local ESC = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
local function str(s)
  return '"' .. (s:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end)) .. '"'
end

local function num(v)
  if v ~= v then return "NaN" end
  if v == math.huge then return "Infinity" end
  if v == -math.huge then return "-Infinity" end
  if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
  return string.format("%.17g", v)
end

local function key_name(k)
  if type(k) == "string" then return k end
  return "[" .. tostring(k) .. "]"
end

-- Arrays (Schlüssel genau 1..n) werden zu JSON-Listen, alles andere zu Objekten.
-- Zahlschlüssel in gemischten Tabellen heißen "[n]". Leere Tabelle: {}.
local function encode(v, buf, stack)
  local t = type(v)
  if t == "string" then buf[#buf + 1] = str(v)
  elseif t == "number" then buf[#buf + 1] = num(v)
  elseif t == "boolean" then buf[#buf + 1] = tostring(v)
  elseif t == "table" then
    if stack[v] then buf[#buf + 1] = '"<Zyklus>"' return end
    stack[v] = true
    local count, max_index, only_index = 0, 0, true
    for k in pairs(v) do
      count = count + 1
      if type(k) == "number" and k >= 1 and k == math.floor(k) then
        if k > max_index then max_index = k end
      else
        only_index = false
      end
    end
    if count > 0 and only_index and max_index == count then
      buf[#buf + 1] = "["
      for i = 1, count do
        if i > 1 then buf[#buf + 1] = "," end
        encode(v[i], buf, stack)
      end
      buf[#buf + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return key_name(a) < key_name(b) end)
      buf[#buf + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then buf[#buf + 1] = "," end
        buf[#buf + 1] = str(key_name(k))
        buf[#buf + 1] = ":"
        encode(v[k], buf, stack)
      end
      buf[#buf + 1] = "}"
    end
    stack[v] = nil
  else
    buf[#buf + 1] = str("<" .. t .. ">")
  end
end

local function sorted_keys(tbl)
  local keys = {}
  for k in pairs(tbl) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local prototypes, own_types = {}, {}
for _, t in ipairs(sorted_keys(raw)) do
  for _, n in ipairs(sorted_keys(raw[t])) do
    local p = raw[t][n]
    if type(p) == "table" and is_own(t, n) then
      local copy = p
      if SETTING_TYPES[t] then
        copy = {}
        for k, v in pairs(p) do if k ~= "value" then copy[k] = v end end
      end
      prototypes[#prototypes + 1] = {type = t, name = n, stage = SETTING_TYPES[t] and "settings" or "data",
        source = sources[t .. "\0" .. n], by_name = by_name(n) and true or false, data = copy}
      own_types[t] = true
    end
  end
end

-- Vanilla-Prototypen derselben Typen: proto_fields.py prüft sie mit und markiert Meldungen,
-- die Vanilla genauso hat (Lücke in der Typdatei oder Altlast in Vanilla).
local vanilla = {}
for t in pairs(own_types) do
  local list = {}
  for _, n in ipairs(sorted_keys(raw[t] or {})) do
    local p = raw[t][n]
    if type(p) == "table" and not is_own(t, n) then list[#list + 1] = {name = n, data = p} end
  end
  vanilla[t] = list
end

local startup = {}
for n, s in pairs(settings.startup or {}) do if by_name(n) then startup[n] = s.value end end

local buf = {}
encode({format = 1, base = mods["base"], mods = mods, startup_settings = startup,
  prototypes = prototypes, vanilla_prototypes = vanilla}, buf, {})
return table.concat(buf)
