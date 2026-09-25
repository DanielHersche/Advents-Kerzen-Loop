-- Kerzen Loop Player
-- Jeder Film wird fuer die eingestellte Dauer nahtlos geloopt,
-- danach folgt der naechste Film. Am Ende beginnt die Liste von vorne.

gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local playlist = {}
local fade = 1.0
local rotation = 0

local idx = 0          -- Index des aktuellen Films
local cur = nil        -- aktuell laufender Film
local prev = nil       -- vorheriger Film (waehrend Ueberblendung)
local nxt = nil        -- vorgeladener naechster Film
local nxt_idx = nil
local cur_end = 0      -- Zeitpunkt, an dem gewechselt wird
local fade_start = 0

local function dispose(obj)
    if obj then obj:dispose() end
end

local function reset()
    dispose(cur); dispose(prev); dispose(nxt)
    cur, prev, nxt, nxt_idx, idx = nil, nil, nil, nil, 0
end

-- Zeitplan: der Service meldet "on" oder "off"
local screen_on = true
util.data_mapper{
    power = function(state)
        local new_state = (state ~= "off")
        if new_state ~= screen_on then
            screen_on = new_state
            if not screen_on then
                -- Filme freigeben, solange der Bildschirm aus ist
                reset()
            end
        end
    end,
}

local function load(item)
    if item.kind == "video" then
        return resource.load_video{
            file = item.file:copy(),
            looped = true,
            audio = false,
        }
    else
        return resource.load_image{
            file = item.file:copy(),
        }
    end
end

util.json_watch("config.json", function(config)
    local new = {}
    for _, item in ipairs(config.playlist or {}) do
        if item.file and item.file.asset_name then
            new[#new+1] = {
                file = resource.open_file(item.file.asset_name),
                kind = item.file.type,
                duration = math.max(1, item.duration or 60),
            }
        end
    end
    fade = math.max(0, config.fade or 1.0)
    rotation = config.rotation or 0
    reset()
    playlist = new
end)

local function is_ready(obj)
    local ok, state = pcall(obj.state, obj)
    return not ok or state ~= "loading"
end

local function tick(now)
    if #playlist == 0 then return end

    -- Start: ersten Film laden
    if not cur then
        idx = 1
        cur = load(playlist[idx])
        cur_end = now + playlist[idx].duration
        return
    end

    -- Nur ein Film: einfach endlos weiterloopen
    if #playlist == 1 then return end

    -- Naechsten Film 3 Sekunden vorher laden, damit der Wechsel nahtlos ist
    if not nxt and now >= cur_end - 3 then
        nxt_idx = idx % #playlist + 1
        nxt = load(playlist[nxt_idx])
    end

    -- Wechseln, sobald die Zeit um ist und der neue Film bereit ist
    if nxt and now >= cur_end and is_ready(nxt) then
        dispose(prev)
        prev = cur
        fade_start = now
        cur = nxt
        idx = nxt_idx
        nxt, nxt_idx = nil, nil
        cur_end = now + playlist[idx].duration
    end

    -- Vorherigen Film nach der Ueberblendung freigeben
    if prev and now - fade_start >= fade then
        dispose(prev)
        prev = nil
    end
end

local function apply_rotation()
    local w, h = WIDTH, HEIGHT
    if rotation == 90 then
        gl.translate(WIDTH, 0)
        gl.rotate(90, 0, 0, 1)
        w, h = HEIGHT, WIDTH
    elseif rotation == 180 then
        gl.translate(WIDTH, HEIGHT)
        gl.rotate(180, 0, 0, 1)
    elseif rotation == 270 then
        gl.translate(0, HEIGHT)
        gl.rotate(270, 0, 0, 1)
        w, h = HEIGHT, WIDTH
    end
    return w, h
end

function node.render()
    gl.clear(0, 0, 0, 1)
    if not screen_on then
        return
    end
    local now = sys.now()
    tick(now)

    local w, h = apply_rotation()

    if prev then
        util.draw_correct(prev, 0, 0, w, h, 1)
    end
    if cur then
        local alpha = 1
        if prev and fade > 0 then
            alpha = math.min(1, (now - fade_start) / fade)
        end
        util.draw_correct(cur, 0, 0, w, h, alpha)
    end
end
