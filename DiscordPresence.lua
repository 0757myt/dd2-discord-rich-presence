-- DiscordPresence.lua (REFramework autorun)
-- Decides what Discord shows and writes it to reframework/data/DiscordPresence/presence.json;
-- reframework/plugins/DiscordPresence.dll sends it to Discord. Read-only: nothing in the game is changed
-- (the GuiManager hooks below only note which enemies get an HP bar and the text of place-name banners).
-- Game calls: CharacterManager / PawnManager / BattleManager / MainFlowManager (as PartyBox uses them),
-- TimeManager (as NickCore uses it), via.gui.GUISystem for the game's text language.
-- Settings: reframework/data/DiscordPresence/config.json (created on first run, kept on mod reinstall).

local CONFIG_FILE = "DiscordPresence/config.json"
local OUT_FILE = "DiscordPresence/presence.json"
local STATE_FILE = "DiscordPresence/state.json" -- last place name, so it survives a restart
local INTERVAL = 2.0 -- seconds between writes
local CONFIG_VERSION = 8
local GAME_TITLE = "Dragon's Dogma 2" -- image hover text when nothing else can be filled in
-- Art asset uploaded to the Discord application (Developer Portal -> Rich Presence -> Art Assets)
local COVER_ASSET = "dd2_cover"
local OLD_STEAM_COVER = "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/2054970/header.jpg"

-- Texts per game language. A language missing here (or a key missing in it) falls back to "en".
-- Placeholders: see README.md or the "Discord Presence" node in the REFramework menu.
-- A list rotates over time; a line whose placeholder is unknown right now is skipped (e.g. "Quest: {quest}"
-- while no quest is selected). "*_fallback" keys are used when nothing in the main key could be filled in.
-- The second line is state_format: {place} is the last place-name banner, {activity} the first of
-- dead / down / climbing / combat / status / carry-grapple-glide that applies, else the "state" rotation.
local DEFAULT_TEXTS = {
    en = {
        details = "{name} · {job} · Lv. {level}",
        details_fallback = "{job} · Lv. {level}",
        state_format = "{place} · {activity}",
        state_format_fallback = "{activity}",
        state = { "Pawn: {pawn_name}", "Quest: {quest}", "On the Arisen's path" },
        state_night = { "Braving the night" },
        activity_combat = "Fighting: {enemy}",
        activity_combat_fallback = "In combat!",
        activity_climb = "Climbing: {climb_target}",
        activity_climb_fallback = "Climbing",
        activity_dead = "Fallen",
        activity_down = "Knocked down",
        activity_carry = "Carrying",
        activity_grapple = "Grappling",
        activity_glide = "Gliding",
        status = {
            burning = "Burning", poisoned = "Poisoned", frostbitten = "Frostbitten", frozen = "Frozen",
            petrified = "Petrified", asleep = "Asleep", unconscious = "Unconscious", silenced = "Silenced",
            shocked = "Shocked", tarred = "Tarred", blinded = "Blinded", bewitched = "Bewitched",
            possessed = "Possessed", soaked = "Soaked",
        },
        weather = { clear = "Clear", partly_cloudy = "Partly cloudy", cloudy = "Cloudy", drizzle = "Drizzle", downpour = "Downpour" },
        state_menu = "In the main menu",
        large_text = "Pawn {pawn_name}: {pawn_job}, Lv. {pawn_level}",
        large_text_fallback = GAME_TITLE,
        small_text = "{place} · {time} · {weather}",
        small_text_fallback = "{time} · {weather}",
        buttons = { { label = "View on Steam", url = "https://store.steampowered.com/app/2054970/" } },
    },
    ru = {
        details = "{name} · {job} · Ур. {level}",
        details_fallback = "{job} · Ур. {level}",
        state_format = "{place} · {activity}",
        state_format_fallback = "{activity}",
        state = { "Пешка: {pawn_name}", "Квест: {quest}", "Арисен в пути" },
        state_night = { "Бросает вызов ночи" },
        activity_combat = "Бой: {enemy}",
        activity_combat_fallback = "В бою!",
        activity_climb = "Лазанье: {climb_target}",
        activity_climb_fallback = "Лазанье",
        activity_dead = "Гибель",
        activity_down = "На земле",
        activity_carry = "Несёт",
        activity_grapple = "В захвате",
        activity_glide = "Парит",
        status = {
            burning = "Горение", poisoned = "Отравление", frostbitten = "Обморожение", frozen = "Заморозка",
            petrified = "Окаменение", asleep = "Сон", unconscious = "Обморок", silenced = "Безмолвие",
            shocked = "Электрошок", tarred = "Смола", blinded = "Слепота", bewitched = "Чары",
            possessed = "Одержимость", soaked = "Промокание",
        },
        weather = { clear = "Ясно", partly_cloudy = "Переменная облачность", cloudy = "Облачно", drizzle = "Морось", downpour = "Ливень" },
        state_menu = "В главном меню",
        large_text = "Пешка {pawn_name}: {pawn_job}, ур. {pawn_level}",
        large_text_fallback = GAME_TITLE,
        small_text = "{place} · {time} · {weather}",
        small_text_fallback = "{time} · {weather}",
        buttons = { { label = "Страница в Steam", url = "https://store.steampowered.com/app/2054970/" } },
    },
}

-- Small icon (art asset names in the Discord application): climbing, fallen, otherwise day or night
local DEFAULT_ICONS = { climb = "act_climb", dead = "act_dead", day = "wx_sun", night = "wx_night" }
-- Icons of 2.0 pre-releases that are no longer used; dropped from the config unless the user changed them
local OLD_ICONS = {
    combat = "act_combat", down = "act_down", burning = "st_fire", poisoned = "st_poison", frost = "st_frost",
    status = "st_other", clear = "wx_sun", cloudy = "wx_cloud", rain = "wx_rain", lantern = "act_lantern",
}

-- Defaults of earlier versions. On upgrade a text still equal to one of these is replaced by the
-- current default; anything the user wrote is kept.
local OLD_DEFAULT_TEXTS = {
    en = {
        details = { "{job} · Lv. {level}" },
        details_fallback = { { "Roaming Vermund", "Exploring Battahl", "Hunting monsters" } },
        state = {
            { "On the Arisen's path", "With loyal pawns", "Seeking the Dragon" },
            { "On the Arisen's path", "Traveling with {pawn_name}", "Seeking the Dragon" },
        },
        state_night = { { "Braving the night", "Lantern lit, blade drawn" } },
        state_combat = { "In combat!" },
        large_text = { "{job}, Lv. {level} · HP {hp_percent}%", "{name} · {job}, Lv. {level} · HP {hp_percent}%" },
        large_text_fallback = { "{job}, Lv. {level} · HP {hp_percent}%" },
        small_text = { "", "{time} · {weather}" },
        small_text_fallback = { "{time}" },
    },
    ru = {
        details = { "{job} · Ур. {level}" },
        details_fallback = { { "Странствует по Вермунду", "Исследует Баттахл", "Охотится на чудовищ" } },
        state = {
            { "Арисен в пути", "С верными пешками", "В поисках дракона" },
            { "Арисен в пути", "Пешка {pawn_name} рядом", "В поисках дракона" },
        },
        state_night = { { "Бросает вызов ночи", "С фонарём и клинком" } },
        state_combat = { "В бою!" },
        large_text = { "{job}, ур. {level} · HP {hp_percent}%", "{name} · {job}, ур. {level} · HP {hp_percent}%" },
        large_text_fallback = { "{job}, ур. {level} · HP {hp_percent}%" },
        small_text = { "", "{time} · {weather}" },
        small_text_fallback = { "{time}" },
    },
}

-- Keys renamed in version 6: a text the user changed moves to its new key, the old key goes away
local RENAMED_KEYS = { state_combat = "activity_combat", state_combat_fallback = "activity_combat_fallback" }

local DEFAULTS = {
    config_version = CONFIG_VERSION,
    enabled = true,
    client_id = "1566751565925322802",
    language = "auto", -- "auto" = follow the game's text language, or a key of "texts" ("en", "ru", ...)
    rotate_interval_sec = 20,
    night_start_hour = 19,
    night_end_hour = 5,
    large_image = COVER_ASSET,
    small_image = "", -- a fixed small icon; empty = activity / weather icons below
    show_icons = true,
    icons = DEFAULT_ICONS,
    show_party = true,
    party_max = 4,
    -- Discord's profile pop-out cuts lines after about 30 characters; longer lines drop the party size,
    -- then the place (or use details_fallback) until they fit. 0 = never shorten.
    max_line_length = 30,
    place_timeout_min = 10, -- outside towns, forget the place this long after its banner (0 = never)
    texts = DEFAULT_TEXTS,
}

-- Settings that survive the move from the first (flat, Russian-only) config format
local KEEP_ON_MIGRATION = { "enabled", "client_id", "rotate_interval_sec", "large_image", "small_image", "show_party", "party_max" }

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do if not same(a[i], b[i]) then return false end end
    return true
end

local function load_config()
    local cfg = json.load_file(CONFIG_FILE)
    local changed = false
    if type(cfg) ~= "table" then
        cfg, changed = {}, true
    elseif type(cfg.config_version) == "number" and cfg.config_version >= 2
        and cfg.config_version < CONFIG_VERSION and type(cfg.texts) == "table" then
        for lang, oldKeys in pairs(OLD_DEFAULT_TEXTS) do
            local t = cfg.texts[lang]
            if type(t) == "table" then
                for k, olds in pairs(oldKeys) do
                    for _, old in ipairs(olds) do
                        if same(t[k], old) then t[k] = DEFAULT_TEXTS[lang][k]; break end
                    end
                end
            end
        end
        for _, t in pairs(cfg.texts) do
            if type(t) == "table" then
                for oldKey, newKey in pairs(RENAMED_KEYS) do
                    if t[oldKey] ~= nil and t[newKey] == nil then t[newKey] = t[oldKey] end
                    t[oldKey] = nil
                end
            end
        end
        if cfg.large_image == OLD_STEAM_COVER then cfg.large_image = COVER_ASSET end
        if type(cfg.icons) == "table" then
            for k, v in pairs(OLD_ICONS) do
                if cfg.icons[k] == v then cfg.icons[k] = nil end
            end
        end
        cfg.config_version, changed = CONFIG_VERSION, true
    elseif cfg.config_version ~= CONFIG_VERSION then
        local old = cfg
        cfg, changed = {}, true
        for _, k in ipairs(KEEP_ON_MIGRATION) do cfg[k] = old[k] end
    end
    if cfg.texts ~= nil and type(cfg.texts) ~= "table" then cfg.texts = nil end
    for k, v in pairs(DEFAULTS) do
        if cfg[k] == nil then cfg[k] = v; changed = true end
    end
    -- fill keys added in later versions into the default languages
    for lang, defaults in pairs(DEFAULT_TEXTS) do
        if type(cfg.texts[lang]) ~= "table" then cfg.texts[lang] = defaults; changed = true end
        for k, v in pairs(defaults) do
            if cfg.texts[lang][k] == nil then cfg.texts[lang][k] = v; changed = true end
        end
    end
    if type(cfg.icons) ~= "table" then cfg.icons = {}; changed = true end
    for k, v in pairs(DEFAULT_ICONS) do
        if cfg.icons[k] == nil then cfg.icons[k] = v; changed = true end
    end
    if changed then json.dump_file(CONFIG_FILE, cfg) end
    return cfg
end

local config = load_config()

-- ---------------------------------------------------------------- reading the game

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function call(obj, name, ...)
    if obj == nil then return nil end
    local args = { ... }
    local ok, v = pcall(function() return obj:call(name, table.unpack(args)) end)
    if ok then return v end
    return nil
end

local function int(v)
    if type(v) == "number" then return math.floor(v) end
    return nil
end

-- via.Language -> key in config.texts
local LANGUAGE_KEYS = {
    [0] = "ja", [1] = "en", [2] = "fr", [3] = "it", [4] = "de", [5] = "es", [6] = "ru", [7] = "pl",
    [8] = "nl", [9] = "pt", [10] = "ptbr", [11] = "ko", [12] = "zh-tw", [13] = "zh-cn",
}

local function game_language(jobText)
    local gs = sdk.get_native_singleton("via.gui.GUISystem")
    local td = sdk.find_type_definition("via.gui.GUISystem")
    if gs and td then
        local v = try(function() return sdk.call_native_func(gs, td, "get_MessageLanguage") end)
        if type(v) == "number" and LANGUAGE_KEYS[v] then return LANGUAGE_KEYS[v] end
    end
    -- fallback: the vocation name comes from the game's own localization
    if type(jobText) == "string" then
        if jobText:find("[\208\209]") then return "ru" end -- Cyrillic lead bytes in UTF-8
        return "en"
    end
    return nil
end

local function read_job(char)
    local human = call(char, "get_Human")
    local ctx = call(human, "get_JobContext")
    local job = call(ctx, "get_Job")
    if type(job) ~= "number" and ctx ~= nil then
        job = try(function() return ctx:get_field("CurrentJob") end)
    end
    if type(job) == "number" and job % 1 == 0 and job >= 1 and job <= 10 then return job end
    return nil
end

-- Localized vocation name from the game itself (cache is cleared when the language changes)
local jobMethod, jobNames = nil, {}
local function job_name(id)
    if not id then return nil end
    if jobNames[id] then return jobNames[id] end
    if not jobMethod then
        local td = sdk.find_type_definition("app.GUIBase")
        jobMethod = td and td:get_method("getJobName(app.Character.JobEnum)")
    end
    local name = jobMethod and try(function() return jobMethod:call(nil, id) end)
    if type(name) == "string" and name ~= "" then
        jobNames[id] = name
        return name
    end
    return nil
end

-- Character names (the Arisen's and pawns' own names), same call PawnCompanion uses:
-- static app.GUIBase.getName(app.CharacterID)
local nameMethod, names = nil, {}
local function chara_name(char)
    local cid = call(char, "get_CharaID")
    if cid == nil then return nil end
    local key = type(cid) == "number" and cid or nil -- CharacterID is an enum; anything else is not cached
    if key and names[key] then return names[key] end
    if not nameMethod then
        local td = sdk.find_type_definition("app.GUIBase")
        nameMethod = td and td:get_method("getName(app.CharacterID)")
    end
    local result = nameMethod and try(function() return nameMethod:call(nil, cid) end)
    if result ~= nil and type(result) ~= "string" then
        result = try(function() return result:call("ToString") end)
    end
    if type(result) == "string" and result ~= "" then
        if key then names[key] = result end
        return result
    end
    return nil
end

-- Name of the quest set as destination in the quest log (PawnCompanion reads the same field,
-- QuestTracker reads QuestName the same way). nil when no quest is selected.
local questNames = {}
local function tracked_quest()
    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
    if qlm == nil then return nil end
    local qid = try(function() return qlm:get_field("_CurrentDestinationTargetQuestID") end)
    if type(qid) ~= "number" or qid <= 0 then return nil end
    if questNames[qid] then return questNames[qid] end
    local log = call(qlm, "getQuestLog", qid)
    local name = log and try(function() return log:get_field("QuestName") end)
    if type(name) == "string" and name ~= "" then
        questNames[qid] = name
        return name
    end
    return nil
end

-- Values of a System.Collections.Generic.Dictionary (read from its entry array; empty slots have no value)
local function dict_values(dict)
    local out = {}
    if dict == nil then return out end
    local entries = try(function() return dict:get_field("_entries") end)
        or try(function() return dict:get_field("entries") end)
    local n = entries and try(function() return entries:get_size() end)
    if type(n) ~= "number" then return out end
    for i = 0, n - 1 do
        local v = try(function() return entries:get_element(i):get_field("value") end)
        if v ~= nil then out[#out + 1] = v end
    end
    return out
end

local enemySource = "-" -- where {enemy} came from last time (shown in the REFramework menu)
local lastEnemyNote = nil -- last enemy/source written to the REFramework log

local function type_name(obj)
    return try(function() return obj:get_type_definition():get_full_name() end)
end

local function as_character(obj)
    if obj == nil then return nil end
    local tn = type_name(obj)
    if tn == "app.Character" then return obj end
    if tn == "via.GameObject" then
        return try(function() return obj:call("getComponent(System.Type)", sdk.typeof("app.Character")) end)
    end
    return nil
end

local function alive_enemy(chara)
    return chara ~= nil and call(chara, "get_IsDead") ~= true and call(chara, "get_Valid") ~= false
end

local function max_hp(chara)
    local hp = call(chara, "get_OriginalMaxHp") or call(chara, "get_ReducedMaxHp")
    return type(hp) == "number" and hp or 0
end

-- Enemies the HUD shows an HP bar for (the ones the party hits). The game registers/unregisters them in
-- app.GuiManager; these hooks only take note of the argument and change nothing.
local attackTargets = {} -- address -> app.Character
pcall(function()
    local td = sdk.find_type_definition("app.GuiManager")
    local function arg_chara(args)
        local c = try(function() return sdk.to_managed_object(args[3]) end)
        local addr = c and try(function() return c:get_address() end)
        return c, addr
    end
    sdk.hook(td:get_method("registAttackTarget(app.Character)"), function(args)
        local c, addr = arg_chara(args)
        if addr then attackTargets[addr] = c end
    end, nil)
    sdk.hook(td:get_method("unregistAttackTarget(app.Character)"), function(args)
        local _, addr = arg_chara(args)
        if addr then attackTargets[addr] = nil end
    end, nil)
end)

-- The main enemy of the current fight, from the most to the least telling source:
-- the boss HP gauge, the strongest enemy with an HP bar, the Arisen's lock-on target,
-- the strongest enemy that noticed the party (BattleManager keeps those as EnemyControllers).
local function current_enemy(bm, cm)
    local gm = sdk.get_managed_singleton("app.GuiManager")
    local boss = as_character(call(gm, "getBossGaugeTarget"))
    if alive_enemy(boss) then
        local name = chara_name(boss)
        if name then enemySource = "boss gauge"; return name end
    end

    local best, bestHp = nil, -1
    for addr, chara in pairs(attackTargets) do
        if alive_enemy(chara) then
            local hp = max_hp(chara)
            if hp > bestHp then best, bestHp = chara, hp end
        else
            attackTargets[addr] = nil
        end
    end
    if best then
        local name = chara_name(best)
        if name then enemySource = "attack target"; return name end
    end

    local lockOn = call(call(cm, "get_ManualPlayerPlayer"), "get_LockOnCtrl")
    local target = call(lockOn, "get_Target")
    local chara = target and try(function() return target:get_field("<Character>k__BackingField") end)
    if alive_enemy(chara) and try(function() return chara:get_field("EnemyCtrl") end) ~= nil then
        local name = chara_name(chara)
        if name then enemySource = "lock-on"; return name end
    end

    best, bestHp = nil, -1
    for _, field in ipairs({ "_BattleNoticeCharacterUniqueIDDict", "_DetectArizenPartyAndInCameraEnemyDict" }) do
        local dict = try(function() return bm:get_field(field) end)
        for _, ec in ipairs(dict_values(dict)) do
            local c = try(function() return ec:get_field("Chara") end)
            if alive_enemy(c) and max_hp(c) > bestHp then best, bestHp = c, max_hp(c) end
        end
    end
    if best then
        local name = chara_name(best)
        if name then enemySource = "noticed"; return name end
    end
    enemySource = "-"
    return nil
end

-- The place the game last announced with its place-name banner ("Vernworth", "Guerco Mountain Road", an inn...).
-- GuiManager.requestPlaceName gets the banner's message ID; via.gui.message turns it into text (as QuestTracker does).
-- The game shows a banner when you enter a place but not when you leave it, so the place is dropped when the
-- Arisen's town area (Character.AITownArea: one value in the field, another inside a town) changes, and after
-- place_timeout_min outside towns.
local FIELD_TOWN_AREA = 1   -- AITownArea while out in the open world
local AREA_SETTLE_SEC = 4   -- the banner can come a moment before the area switches; wait before noting the area
local place = { name = nil, town = nil, at = 0 }
do
    local saved = json.load_file(STATE_FILE)
    if type(saved) == "table" and type(saved.place) == "string" and saved.place ~= "" and type(saved.town) == "number" then
        place = { name = saved.place, town = saved.town, at = os.clock(), restored = true }
    end
end

local function save_place()
    pcall(json.dump_file, STATE_FILE, { place = place.name, town = place.town })
end

pcall(function()
    local mt = sdk.find_type_definition("via.gui.message")
    local msgGet = mt and mt:get_method("get(System.Guid)")
    local td = sdk.find_type_definition("app.GuiManager")
    sdk.hook(td:get_method("requestPlaceName(System.Guid, System.Boolean, System.Boolean)"), function(args)
        local guid = try(function() return sdk.to_valuetype(args[3], "System.Guid") end)
        local name = guid and msgGet and try(function() return msgGet:call(nil, guid) end)
        if type(name) == "string" and name ~= "" then
            place = { name = name, town = nil, at = os.clock() } -- town area is noted once it has settled
        end
    end, nil)
end)

-- keeps place.name valid for where the Arisen is now; returns it or nil
local function current_place(townArea)
    if not place.name then return nil end
    local now = os.clock()
    if place.town == nil then
        if townArea and now - place.at >= AREA_SETTLE_SEC then
            place.town = townArea
            save_place()
        end
        return place.name
    end
    local timeout = (tonumber(config.place_timeout_min) or 10) * 60
    local leftArea = townArea ~= nil and townArea ~= place.town
    local stale = timeout > 0 and now - place.at > timeout and townArea == FIELD_TOWN_AREA
    if leftArea or stale then
        place = { name = nil, town = nil, at = 0 }
        save_place()
        return nil
    end
    return place.name
end

-- app.WeatherManager.WeatherEnum -> key in texts.weather
local WEATHER_KEYS = { [1] = "clear", [2] = "partly_cloudy", [3] = "cloudy", [4] = "drizzle", [5] = "downpour" }

-- app.StatusConditionDef.StatusConditionEnum (bit N of the active-condition mask, as PartyBox reads it),
-- most noticeable first. Weapon enchantments are left out: they are buffs, not afflictions.
local STATUS_ORDER = {
    { 12, "petrified" }, { 9, "frozen" }, { 5, "burning" }, { 7, "poisoned" }, { 1, "poisoned" },
    { 21, "bewitched" }, { 22, "possessed" }, { 2, "asleep" }, { 3, "unconscious" }, { 13, "shocked" },
    { 14, "shocked" }, { 8, "frostbitten" }, { 11, "silenced" }, { 23, "blinded" }, { 10, "tarred" },
    { 6, "tarred" }, { 4, "soaked" },
}

local function top_status(char)
    local ctrl = call(char, "get_StatusConditionCtrl")
    local mask = call(ctrl, "get_ActiveStatusConditionFlagProp")
    if type(mask) ~= "number" and ctrl then mask = try(function() return ctrl:get_field("ActiveStatusConditionFlag") end) end
    mask = type(mask) == "number" and math.tointeger(mask) or nil
    if not mask or mask == 0 then return nil end
    for _, st in ipairs(STATUS_ORDER) do
        if ((mask >> st[1]) & 1) == 1 then return st[2] end
    end
    return nil
end

-- app.Human.ActionTypeEnum -> activity
local ACTION_KINDS = { [5] = "carry", [11] = "carry", [15] = "carry", [6] = "grapple", [7] = "grapple", [8] = "glide" }

local function read_state()
    local s = {}
    local mfm = sdk.get_managed_singleton("app.MainFlowManager")
    s.in_game = call(mfm, "get_IsInGamePhase") ~= false

    local tm = sdk.get_managed_singleton("app.TimeManager")
    s.hour = int(call(tm, "get_InGameHour"))
    s.minute = int(call(tm, "get_InGameMinute"))
    s.day = int(call(tm, "get_InGameDay"))
    if s.hour and s.minute then s.time = string.format("%02d:%02d", s.hour, s.minute) end

    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local player = call(cm, "get_ManualPlayer")
    if player == nil then
        s.in_game = false
        return s
    end

    s.name = chara_name(player)
    s.level = int(call(call(player, "get_Context"), "get_Level"))
    s.job = job_name(read_job(player))

    local hp = call(player, "get_Hp")
    local maxHp = call(player, "get_ReducedMaxHp")
    if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
        s.hp, s.max_hp = int(hp + 0.5), int(maxHp + 0.5)
        s.hp_percent = int(hp / maxHp * 100 + 0.5)
    end

    local pm = sdk.get_managed_singleton("app.PawnManager")
    s.pawns = int(call(call(pm, "getAllPartyPawn"), "get_Count"))
    if s.pawns then s.party = 1 + s.pawns end
    local mainPawn = call(call(pm, "get_MainPawn"), "get_CachedCharacter")
    if mainPawn then
        s.pawn_name = chara_name(mainPawn)
        s.pawn_level = int(call(call(mainPawn, "get_Context"), "get_Level"))
        s.pawn_job = job_name(read_job(mainPawn))
    end

    local bm = sdk.get_managed_singleton("app.BattleManager")
    local battle = call(bm, "get_IsBattleMode")
    s.enemies = int(call(bm, "get_CombatEnemyCount"))
    s.in_combat = battle == true or (s.enemies ~= nil and s.enemies > 0)
    if s.in_combat then s.enemy = current_enemy(bm, cm) end
    local enemyNote = s.in_combat and (tostring(s.enemy) .. " (" .. enemySource .. ")") or nil
    if enemyNote ~= lastEnemyNote and log then
        pcall(log.info, enemyNote and ("[DiscordPresence] enemy: " .. enemyNote) or "[DiscordPresence] combat over")
        lastEnemyNote = enemyNote
    end

    s.quest = tracked_quest()

    local field = function(obj, name) return obj and try(function() return obj:get_field(name) end) end
    s.town_area = int(field(player, "<AITownArea>k__BackingField"))
    s.place = current_place(s.town_area)
    local human = call(player, "get_Human")
    s.weather_id = int(field(player, "<CurrentSpaceWeather>k__BackingField"))
    if field(player, "<IsClimbOnCharacter>k__BackingField") == true then
        s.climbing = true
        s.climb_target = chara_name(field(player, "ClimbTargetCharacter"))
    end
    s.status_key = top_status(player)

    -- what the Arisen is doing, most telling first
    if call(player, "get_IsDead") == true then s.kind = "dead"
    elseif call(player, "get_IsDown") == true then s.kind = "down"
    elseif s.climbing then s.kind = "climb"
    elseif s.in_combat then s.kind = "combat"
    elseif s.status_key and s.status_key ~= "soaked" then s.kind = "status" -- rain soaks you too often to report
    else s.kind = ACTION_KINDS[int(field(human, "<ActionType>k__BackingField")) or -1] end
    return s
end

-- ---------------------------------------------------------------- building the activity

local language = "en" -- current texts language (shown in the REFramework menu)

local function text(key)
    local t = config.texts[language]
    if type(t) == "table" and t[key] ~= nil then return t[key] end
    return config.texts.en and config.texts.en[key]
end

-- one entry of a nested text table (texts.<lang>.status / .weather), falling back to English
local function text_in(key, sub)
    for _, t in ipairs({ text(key), config.texts.en and config.texts.en[key], DEFAULT_TEXTS.en[key] }) do
        if type(t) == "table" and type(t[sub]) == "string" then return t[sub] end
    end
    return nil
end

-- "{job} · Lv. {level}" -> "Warfarer · Lv. 107"; nil if any field is unknown
local function fill(template, s)
    if type(template) ~= "string" or template == "" then return nil end
    local missing = false
    local out = template:gsub("{([%w_]+)}", function(key)
        local v = s[key]
        if v == nil then missing = true; return "" end
        return tostring(v)
    end)
    if missing then return nil end
    return out
end

-- adds the lines of a string or list that can be filled in right now
local function collect(out, values, s)
    if type(values) == "string" then values = { values } end
    if type(values) ~= "table" then return out end
    for _, v in ipairs(values) do
        local line = fill(v, s)
        if line then out[#out + 1] = line end
    end
    return out
end

-- a string, or a list of strings rotated over time; lines with unknown fields are left out of the rotation
local function pick(values, index, s)
    local lines = collect({}, values, s)
    if #lines == 0 then return nil end
    return lines[(index % #lines) + 1]
end

local function is_night(s)
    if not s.hour then return false end
    local from, to = config.night_start_hour or 19, config.night_end_hour or 5
    if from > to then return s.hour >= from or s.hour < to end
    return s.hour >= from and s.hour < to
end

local function nonempty(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local current, lastState = {}, {} -- shown in the REFramework menu
local PARTY_SUFFIX_LENGTH = 9 -- Discord appends " (4 of 4)" to the state line

-- {activity} text for what the Arisen is doing; the "state" rotation when nothing special is going on
local function activity_text(s, index)
    local k = s.kind
    if k == "combat" then return pick(text("activity_combat"), index, s) or pick(text("activity_combat_fallback"), index, s) end
    if k == "climb" then return pick(text("activity_climb"), index, s) or pick(text("activity_climb_fallback"), index, s) end
    if k == "status" then return s.status end
    if k then
        local line = pick(text("activity_" .. k), index, s)
        if line then return line end
    end
    local lines = collect({}, text("state"), s)
    if is_night(s) then collect(lines, text("state_night"), s) end
    if #lines > 0 then return lines[(index % #lines) + 1] end
    return nil
end

-- small icon: climbing or fallen, otherwise the time of day
local function icon_key(s)
    if s.kind == "climb" or s.kind == "dead" then return s.kind end
    if not s.hour then return nil end
    return is_night(s) and "night" or "day"
end

local function build_activity(s)
    local index = math.floor(os.clock() / math.max(15, config.rotate_interval_sec or 20))
    local a = { assets = {} }

    s.weather = WEATHER_KEYS[s.weather_id or -1] and text_in("weather", WEATHER_KEYS[s.weather_id])
    s.status = s.status_key and text_in("status", s.status_key)

    if not s.in_game then
        a.details = pick(text("state_menu"), index, s)
    else
        local limit = tonumber(config.max_line_length) or 0
        local function length(line) return line and (utf8.len(line) or #line) or math.huge end
        local function fits(line, extra) return limit <= 0 or length(line) + (extra or 0) <= limit end

        local details = pick(text("details"), index, s)
        local shorter = pick(text("details_fallback"), index, s)
        a.details = (details and (fits(details) or not shorter)) and details or shorter

        s.activity = activity_text(s, index)
        local full = pick(text("state_format"), index, s)
        local short = pick(text("state_format_fallback"), index, s)
        local partyLen = (config.show_party and s.party) and PARTY_SUFFIX_LENGTH or nil
        -- most complete first: place + activity + party, without party, activity + party, activity alone
        local options = { { full, true }, { full, false }, { short, true }, { short, false } }
        local withParty = false
        for _, o in ipairs(options) do
            local line, party = o[1], o[2] and partyLen ~= nil
            if line and (not o[2] or partyLen) and fits(line, party and partyLen or 0) then
                a.state, withParty = line, party
                break
            end
        end
        if not a.state then a.state = short or full end
        if withParty then
            local max = math.floor(config.party_max or 4)
            a.party = { size = { math.min(s.party, max), max } }
        end
    end

    a.assets.large_image = nonempty(config.large_image)
    a.assets.large_text = (s.in_game and pick(text("large_text"), index, s))
        or pick(text("large_text_fallback"), index, s) or GAME_TITLE
    a.assets.small_image = nonempty(config.small_image)
    if not a.assets.small_image and s.in_game and config.show_icons ~= false then
        local key = icon_key(s)
        a.assets.small_image = key and type(config.icons) == "table" and nonempty(config.icons[key]) or nil
        s.icon = key
    end
    if a.assets.small_image then
        a.assets.small_text = pick(text("small_text"), index, s) or pick(text("small_text_fallback"), index, s)
    end
    if next(a.assets) == nil then a.assets = nil end

    local buttons = text("buttons")
    if type(buttons) == "table" and #buttons > 0 then
        a.buttons = {}
        for i = 1, math.min(2, #buttons) do a.buttons[i] = buttons[i] end
    end
    return a
end

-- ---------------------------------------------------------------- main loop

local nextWrite = 0
re.on_frame(function()
    local now = os.clock()
    if now < nextWrite then return end
    nextWrite = now + INTERVAL

    if not config.enabled then return end -- the plugin clears the status once the file goes stale
    local ok, state = pcall(read_state)
    if not ok or not state then return end

    local wanted = config.language
    if wanted == nil or wanted == "auto" then wanted = game_language(state.job) or language end
    if wanted ~= language then
        language = wanted
        jobNames, questNames = {}, {} -- localized: read them again in the new language
        ok, state = pcall(read_state)
        if not ok or not state then return end
    end

    local okA, activity = pcall(build_activity, state)
    if not okA then return end
    current, lastState = activity, state
    pcall(json.dump_file, OUT_FILE, {
        client_id = tostring(config.client_id),
        updated = os.time(),
        activity = activity,
    })
end)

local FIELDS = { "name", "job", "level", "place", "activity", "pawn_name", "pawn_job", "pawn_level", "quest",
                 "enemy", "enemies", "climb_target", "status", "weather", "time", "hour", "minute", "day",
                 "pawns", "party", "hp", "max_hp", "hp_percent" }

re.on_draw_ui(function()
    if not imgui.tree_node("Discord Presence") then return end
    local changed, v = imgui.checkbox("Enabled", config.enabled)
    if changed then
        config.enabled = v
        json.dump_file(CONFIG_FILE, config)
    end
    imgui.text("Language: " .. language .. (config.language == "auto" and " (auto)" or ""))
    imgui.text("Details: " .. tostring(current.details or "-"))
    imgui.text("State:   " .. tostring(current.state or "-"))
    if imgui.tree_node("Placeholders (current values)") then
        for _, k in ipairs(FIELDS) do imgui.text("{" .. k .. "} = " .. tostring(lastState[k])) end
        imgui.text("{enemy} source: " .. enemySource)
        imgui.text("activity: " .. tostring(lastState.kind or "-") .. ", icon: " .. tostring(lastState.icon or "-"))
        imgui.tree_pop()
    end
    if imgui.button("Reload config.json") then config = load_config() end
    imgui.text("Settings: reframework/data/DiscordPresence/config.json")
    imgui.tree_pop()
end)
