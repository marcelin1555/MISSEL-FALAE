-- ============================================
-- MISSIL TELEGUIADO - SCRIPT PRINCIPAL DO MÍSSIL
-- Arquitetura: Motores Sólidos (Propulsão) + 1 Vector Thruster (Direção)
-- ============================================

local config = require("config")

-- ======== ESTADO DO MÍSSIL ========
local estado = {
    status       = "idle",      -- idle, lancado, armado, detonado, destruido
    throttle     = config.THROTTLE_INICIAL,
    pitch        = 0,           -- comando pitch da estacao
    yaw          = 0,           -- comando yaw da estacao
    gyro_pitch   = 0,           -- pitch real (Norte)
    gyro_yaw     = 0,           -- yaw real (Leste)
    armado       = false,
    tempo_voo    = 0,
    combustivel  = 100,
    pos_x        = 0, pos_y = 0, pos_z = 0,
    vel_x        = 0, vel_y = 0, vel_z = 0,
    alvo_x       = nil, alvo_y = nil, alvo_z = nil,
    modo         = config.MODO_PADRAO,
    conectado    = false,
    ultimo_ping  = 0,
}

-- ======== PERIFÉRICOS ========
local modem = nil
local gimbal = nil
local vetor = nil
local solidos = {}

local calib = {}
local pid_state = {
    t0 = 0,
    n0 = 0,
    l0 = 0
}

-- ======== FUNÇÕES AUXILIARES ========
local function log(msg)
    local timestamp = string.format("[%.1f]", os.clock())
    print(timestamp .. " " .. msg)
end

local function limitar(v) return math.max(-1, math.min(1, v)) end

local function lerCalibracao()
    if fs.exists("calib.txt") then
        local f = fs.open("calib.txt", "r")
        calib = textutils.unserialize(f.readAll()) or {}
        f.close()
    end
    if not calib.eixoN then log("AVISO: gimbal nao calibrado (calibrar_gimbal.lua)") end
    if not calib.eixoX then log("AVISO: bocal nao calibrado (calibrar.lua)") end
    calib.offX = calib.offX or 0; calib.offZ = calib.offZ or 0
    calib.eixoN = calib.eixoN or 1; calib.sinalN = calib.sinalN or 1
    calib.eixoL = calib.eixoL or 2; calib.sinalL = calib.sinalL or 1
    calib.eixoX = calib.eixoX or 2; calib.sinalX = calib.sinalX or 1
    calib.eixoY = calib.eixoY or 1; calib.sinalY = calib.sinalY or 1
end

local function inicializarPeripherals()
    log("Inicializando periféricos...")
    
    -- Modem
    local modems = { peripheral.find("modem") }
    for _, m in ipairs(modems) do
        if m.isWireless and m.isWireless() then modem = m break end
    end
    if modem then
        modem.open(config.CANAL_RECEBER)
        modem.open(config.CANAL_ENVIO)
        log("Modem wireless inicializado")
    end
    
    gimbal = peripheral.find("gimbal_sensor")
    if not gimbal then log("AVISO: Gimbal Sensor nao encontrado!") end
    
    vetor = peripheral.find("vector_thruster") or peripheral.find("liquid_vector_thruster") or peripheral.find("creative_vector_thruster")
    if not vetor then log("AVISO: Vector Thruster nao encontrado!") end
    
    local nomes = peripheral.getNames()
    for _, nome in ipairs(nomes) do
        local tipo = peripheral.getType(nome) or ""
        if string.find(tipo, "thruster") and not string.find(tipo, "vector") then
            table.insert(solidos, { nome = nome, p = peripheral.wrap(nome) })
        end
    end
    log(("Motores Principais encontrados: %d"):format(#solidos))
    
    lerCalibracao()
    return modem ~= nil
end

-- ======== ESTABILIZAÇÃO & VOO ========

local function lerAngulos()
    if not gimbal then return 0, 0 end
    local r = { gimbal.getAngles() }
    if type(r[1]) == "table" then r = r[1] end
    local a = { (r[1] or 0) - calib.offX, (r[2] or 0) - calib.offZ }
    return a[calib.eixoN] * calib.sinalN, a[calib.eixoL] * calib.sinalL
end

local function setMotoresSolidos(pot)
    for _, m in ipairs(solidos) do
        pcall(function() 
            if m.p.setPowerNormalized then m.p.setPowerNormalized(pot) 
            elseif m.p.setThrustNormalized then m.p.setThrustNormalized(pot)
            elseif m.p.setThrust then m.p.setThrust(pot * 15)
            elseif m.p.setThrottle then m.p.setThrottle(pot * 15)
            end
        end)
    end
end

local function motoresEstaoQueimando()
    for _, m in ipairs(solidos) do
        local isBurning = false
        pcall(function() isBurning = m.p.isBurning() or (m.p.getFuelAmount and m.p.getFuelAmount() > 0) or (m.p.getFluidAmount and m.p.getFluidAmount() > 0) end)
        if isBurning then return true end
    end
    return false
end

local function atualizarCombustivel()
    if #solidos == 0 then return end
    local total_fuel = 0
    for _, m in ipairs(solidos) do
        pcall(function() 
            if m.p.getFuelAmount then total_fuel = total_fuel + m.p.getFuelAmount() 
            elseif m.p.getFluidAmount then total_fuel = total_fuel + m.p.getFluidAmount() 
            else total_fuel = total_fuel + 1000 end -- Se não tiver API de fuel, assume infinito
        end)
    end
    -- Aproximação 0-100 para a UI
    estado.combustivel = math.min(100, math.max(0, (total_fuel / (#solidos * 1000)) * 100))
    if total_fuel == 0 and estado.status == "lancado" then
        log("Motores principais esgotados (burnout)")
        estado.status = "idle"
    end
end

local function aplicarControleVoo()
    if estado.status ~= "lancado" and estado.status ~= "armado" then
        setMotoresSolidos(0)
        if config.THRUSTER_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_SIDE, 0) end
        if vetor then
            pcall(function() vetor.setVector(0, 0); vetor.setThrustNormalized(0) end)
        end
        return
    end
    
    local n, l = lerAngulos()
    estado.gyro_pitch = n
    estado.gyro_yaw = l
    
    local t = os.clock()
    local dt = math.max(t - pid_state.t0, 0.05)
    local rn = (n - pid_state.n0) / dt
    local rl = (l - pid_state.l0) / dt
    pid_state.n0, pid_state.l0, pid_state.t0 = n, l, t
    
    -- Subtrai o comando do usuário (Norte = Pitch, Leste = Yaw)
    -- Assim o PID tenta estabilizar no ângulo que o usuário pediu, não no zero.
    local erro_n = n - estado.pitch
    local erro_l = l - estado.yaw
    
    local ang = { erro_n, erro_l }
    local giro = { rn, rl }
    local inv = config.INVERTER_BOCAL and -1 or 1
    
    local tx = ang[calib.eixoX] * calib.sinalX
    local ty = ang[calib.eixoY] * calib.sinalY
    local gx = giro[calib.eixoX] * calib.sinalX
    local gy = giro[calib.eixoY] * calib.sinalY
    
    local cx = limitar(-inv * (config.PID_KP * tx + config.PID_KD * gx))
    local cy = limitar(-inv * (config.PID_KP * ty + config.PID_KD * gy))
    
    if vetor then
        pcall(function()
            vetor.setVector(cx, cy)
            -- O throttle do vetor pode ser ajustado para não frear o míssil muito forte
            local empuxo_vetor = estado.throttle / config.THROTTLE_MAX
            vetor.setThrustNormalized(empuxo_vetor)
        end)
    end
    
    -- Motores sólidos no máximo
    setMotoresSolidos(1.0)
    if config.THRUSTER_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_SIDE, 15) end
end

local function ativarDetonacao()
    if estado.armado then
        estado.status = "detonado"
        redstone.setOutput(config.DETONACAO_SIDE, true)
        log("*** DETONAÇÃO ATIVADA ***")
        sleep(0.5)
        redstone.setOutput(config.DETONACAO_SIDE, false)
    else
        log("Ogiva não armada - detonação recusada")
    end
end

local function autodestruicao()
    log("!!! AUTODESTRUIÇÃO ATIVADA !!!")
    estado.status = "destruido"
    setMotoresSolidos(0)
    if config.THRUSTER_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_SIDE, 0) end
    if vetor then pcall(function() vetor.setThrustNormalized(0) end) end
    redstone.setOutput(config.DETONACAO_SIDE, true)
    sleep(0.5)
    redstone.setOutput(config.DETONACAO_SIDE, false)
end

local function lancar()
    if estado.status ~= "idle" then return end
    log("=== LANÇAMENTO ===")
    estado.status = "lancado"
    estado.tempo_voo = 0
    estado.throttle = config.THROTTLE_MAX
    pid_state.t0 = os.clock()
    pid_state.n0, pid_state.l0 = lerAngulos()
end

local function armar()
    if estado.status == "lancado" and estado.tempo_voo >= config.ARMAR_DELAY then
        estado.armado = true
        estado.status = "armado"
        log("Ogiva ARMADA")
    end
end

-- ======== GPS & COMANDOS ========

local function atualizarGPS()
    local x, y, z = gps.locate(2)
    if x then
        if estado.pos_x ~= 0 then
            estado.vel_x = x - estado.pos_x
            estado.vel_y = y - estado.pos_y
            estado.vel_z = z - estado.pos_z
        end
        estado.pos_x, estado.pos_y, estado.pos_z = x, y, z
    end
end

local function calcularRumoParaAlvo()
    if not estado.alvo_x then return end
    local dx = estado.alvo_x - estado.pos_x
    local dy = estado.alvo_y - estado.pos_y
    local dz = estado.alvo_z - estado.pos_z
    local dist = math.sqrt(dx^2 + dy^2 + dz^2)
    
    if dist < config.GPS_PRECISAO then
        log("Alvo alcançado!")
        if estado.armado then ativarDetonacao() end
        return
    end
    
    local dist_h = math.sqrt(dx^2 + dz^2)
    local yaw_alvo = math.deg(math.atan2(dx, dz))
    local pitch_alvo = math.deg(math.atan2(dy, dist_h))
    
    estado.yaw = estado.yaw + (yaw_alvo - estado.yaw) * config.GPS_CORRECAO_RATE
    estado.pitch = estado.pitch + (pitch_alvo - estado.pitch) * config.GPS_CORRECAO_RATE
    estado.yaw = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, estado.yaw))
    estado.pitch = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, estado.pitch))
end

local function enviarTelemetria()
    if not modem then return end
    local dados = {
        tipo = "telemetria", protocolo = config.PROTOCOLO,
        estado = estado
    }
    modem.transmit(config.CANAL_ENVIO, config.CANAL_RECEBER, textutils.serialise(dados))
end

local function processarComando(dados)
    if type(dados) ~= "string" then return end
    local ok, cmd = pcall(textutils.unserialise, dados)
    if not ok or not cmd or cmd.protocolo ~= config.PROTOCOLO then return end
    
    estado.conectado = true
    estado.ultimo_ping = os.clock()
    
    if cmd.tipo == "comando" then
        if cmd.acao == "lancar" then lancar()
        elseif cmd.acao == "armar" then armar()
        elseif cmd.acao == "detonar" then ativarDetonacao()
        elseif cmd.acao == "emergencia" then autodestruicao()
        elseif cmd.acao == "throttle" then estado.throttle = cmd.valor or estado.throttle
        elseif cmd.acao == "pitch" then estado.pitch = cmd.valor or estado.pitch
        elseif cmd.acao == "yaw" then estado.yaw = cmd.valor or estado.yaw
        elseif cmd.acao == "modo" then estado.modo = cmd.valor or config.MODO_PADRAO
        elseif cmd.acao == "alvo" then
            estado.alvo_x, estado.alvo_y, estado.alvo_z = cmd.x, cmd.y, cmd.z
        elseif cmd.acao == "ping" then
            modem.transmit(config.CANAL_ENVIO, config.CANAL_RECEBER, textutils.serialise({tipo="pong", protocolo=config.PROTOCOLO}))
        end
    end
end

-- ======== LOOPS ========

local function loopComandos()
    while estado.status ~= "destruido" do
        local _, _, canal, _, msg = os.pullEvent("modem_message")
        if canal == config.CANAL_RECEBER then processarComando(msg) end
    end
end

local function loopVoo()
    while estado.status ~= "destruido" do
        atualizarGPS()
        if estado.status == "lancado" or estado.status == "armado" then
            estado.tempo_voo = estado.tempo_voo + config.INTERVALO_TELEMETRIA
            atualizarCombustivel()
            if estado.modo == config.MODO_GPS and estado.alvo_x then
                calcularRumoParaAlvo()
            end
            aplicarControleVoo()
        end
        enviarTelemetria()
        sleep(config.INTERVALO_TELEMETRIA)
    end
end

-- ======== MAIN ========
local function main()
    term.clear() term.setCursorPos(1, 1)
    print("================================")
    print("  MISSIL TELEGUIADO v4.0")
    print("  Gimbal + Solid Thrusters")
    print("================================")
    
    if not inicializarPeripherals() then
        print("ERRO: Modem nao encontrado!")
        return
    end
    
    log("Sistema pronto. Aguardando comandos da estacao...")
    parallel.waitForAny(loopComandos, loopVoo)
    log("Sistema encerrado.")
end

main()
