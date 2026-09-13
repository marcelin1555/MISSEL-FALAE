-- ============================================
-- MISSIL TELEGUIADO - SCRIPT PRINCIPAL DO MÍSSIL
-- CC:Tweaked + Create Propulsion + Aeronautics
-- ============================================
-- Suporta 4 Vector Thrusters em arranjo 2x2 sem Tilt Adapter
-- com empuxo diferencial e vetorização direta.
-- ============================================

local config = require("config")

-- ======== ESTADO DO MÍSSIL ========
local estado = {
    status       = "idle",      -- idle, lancado, armado, detonado, destruido
    throttle     = config.THROTTLE_INICIAL,
    pitch        = 0,           -- ângulo/vetor pitch atual (-45 a +45)
    yaw          = 0,           -- ângulo/vetor yaw atual (-45 a +45)
    armado       = false,
    tempo_voo    = 0,           -- segundos desde o lançamento
    combustivel  = 100,         -- percentual estimado
    pos_x        = 0,
    pos_y        = 0,
    pos_z        = 0,
    vel_x        = 0,
    vel_y        = 0,
    vel_z        = 0,
    alvo_x       = nil,
    alvo_y       = nil,
    alvo_z       = nil,
    modo         = config.MODO_PADRAO,
    conectado    = false,
    ultimo_ping  = 0,
}

-- ======== PERIFÉRICOS ========
local modem = nil
local vector_thrusters = {}
local tilt_adapters = {}

-- ======== FUNÇÕES AUXILIARES ========

local function log(msg)
    local timestamp = string.format("[%.1f]", os.clock())
    print(timestamp .. " " .. msg)
end

local function encontrarModem()
    local modems = { peripheral.find("modem") }
    for _, m in ipairs(modems) do
        if m.isWireless and m.isWireless() then
            return m
        end
    end
    if #modems > 0 then return modems[1] end
    return nil
end

local function encontrarThrustersEVetores()
    local thrusters = {}
    local tilts = {}
    local nomes = peripheral.getNames()
    
    for _, nome in ipairs(nomes) do
        local tipo = peripheral.getType(nome) or ""
        local tipoLower = string.lower(tipo)
        
        if string.find(tipoLower, "thruster") then
            table.insert(thrusters, {
                nome = nome,
                periferico = peripheral.wrap(nome)
            })
            log("Vector Thruster periférico encontrado: " .. nome)
        elseif string.find(tipoLower, "tilt") then
            table.insert(tilts, {
                nome = nome,
                isAdvanced = string.find(tipoLower, "advanced") ~= nil or (peripheral.wrap(nome).setPitch ~= nil),
                periferico = peripheral.wrap(nome)
            })
            log("Tilt Adapter encontrado: " .. nome)
        end
    end
    return thrusters, tilts
end

local function inicializarPeripherals()
    log("Inicializando periféricos...")
    
    -- Modem
    modem = encontrarModem()
    if modem then
        modem.open(config.CANAL_RECEBER)
        modem.open(config.CANAL_ENVIO)
        log("Modem wireless inicializado")
    else
        log("AVISO: Nenhum modem encontrado!")
    end
    
    -- Thrusters e Tilt Adapters
    vector_thrusters, tilt_adapters = encontrarThrustersEVetores()
    log("Thrusters encontrados: " .. #vector_thrusters)
    log("Tilt adapters encontrados: " .. #tilt_adapters)
    
    log("Modo de Propulsão: " .. (config.MODO_PROPULSAO or "quad_vector"))
    log("Detonação no lado: " .. config.DETONACAO_SIDE)
    
    return modem ~= nil
end

-- ======== CONTROLE DE VOO (4 THRUSTERS 2x2 EMPUXO DIFERENCIAL & VETORIAL) ========

local function aplicarControleVoo(throttle, pitch, yaw)
    throttle = math.max(config.THROTTLE_MIN, math.min(config.THROTTLE_MAX, throttle))
    pitch = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, pitch))
    yaw = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, yaw))
    
    estado.throttle = throttle
    estado.pitch = pitch
    estado.yaw = yaw

    -- 1. Método: Periféricos "vector_thruster" (se existirem na API do mod)
    if #vector_thrusters > 0 then
        for _, t in ipairs(vector_thrusters) do
            pcall(function()
                local p = t.periferico
                -- Aplica ângulo/vetor diretamente no thruster vetorial
                if p.setVector then
                    p.setVector(pitch, yaw)
                elseif p.setPitchAndYaw then
                    p.setPitchAndYaw(pitch, yaw)
                elseif p.setPitch and p.setYaw then
                    p.setPitch(pitch)
                    p.setYaw(yaw)
                elseif p.setTargetAngle then
                    p.setTargetAngle(pitch, yaw)
                end
                
                -- Aplica throttle
                if p.setThrust then p.setThrust(throttle)
                elseif p.setThrottle then p.setThrottle(throttle)
                end
            end)
        end
    end

    -- 2. Método: Tilt Adapters (se o usuário estiver usando algum)
    if #tilt_adapters > 0 then
        for i, adapter in ipairs(tilt_adapters) do
            local p = adapter.periferico
            pcall(function()
                if adapter.isAdvanced then
                    if p.setPitchAndYaw then p.setPitchAndYaw(pitch, yaw)
                    elseif p.setTargetAngle then p.setTargetAngle(pitch, yaw)
                    end
                else
                    if i == 1 then
                        if p.setTargetAngle then p.setTargetAngle(pitch) end
                    else
                        if p.setTargetAngle then p.setTargetAngle(yaw) end
                    end
                end
            end)
        end
    end

    -- 3. Método Principal: Empuxo Diferencial Quad 2x2 (4 Thrusters sem Tilt Adapter)
    -- Calcula modulação de potência para cada um dos 4 thrusters do arranjo 2x2:
    -- TL (Superior Esquerdo), TR (Superior Direito), BL (Inferior Esquerdo), BR (Inferior Direito)
    local p_factor = (pitch / config.TILT_MAX_ANGLE) * (config.THROTTLE_MAX / 2)
    local y_factor = (yaw / config.TILT_MAX_ANGLE) * (config.THROTTLE_MAX / 2)

    local val_tl = math.max(0, math.min(config.THROTTLE_MAX, math.floor(throttle - p_factor + y_factor + 0.5)))
    local val_tr = math.max(0, math.min(config.THROTTLE_MAX, math.floor(throttle - p_factor - y_factor + 0.5)))
    local val_bl = math.max(0, math.min(config.THROTTLE_MAX, math.floor(throttle + p_factor + y_factor + 0.5)))
    local val_br = math.max(0, math.min(config.THROTTLE_MAX, math.floor(throttle + p_factor - y_factor + 0.5)))

    -- Envia saídas analógicas de Redstone para cada um dos 4 cantos
    if config.THRUSTER_TL_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_TL_SIDE, val_tl) end
    if config.THRUSTER_TR_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_TR_SIDE, val_tr) end
    if config.THRUSTER_BL_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_BL_SIDE, val_bl) end
    if config.THRUSTER_BR_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_BR_SIDE, val_br) end

    -- Saída Mestre de Redstone (fallback)
    if config.THRUSTER_SIDE then
        pcall(redstone.setAnalogOutput, config.THRUSTER_SIDE, throttle)
    end
end

local function setThrottle(nivel)
    aplicarControleVoo(nivel, estado.pitch, estado.yaw)
end

local function setPitch(angulo)
    aplicarControleVoo(estado.throttle, angulo, estado.yaw)
end

local function setYaw(angulo)
    aplicarControleVoo(estado.throttle, estado.pitch, angulo)
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
    aplicarControleVoo(0, 0, 0)
    redstone.setOutput(config.DETONACAO_SIDE, true)
    sleep(0.5)
    redstone.setOutput(config.DETONACAO_SIDE, false)
end

local function lancar()
    if estado.status ~= "idle" then
        log("Não pode lançar: status = " .. estado.status)
        return
    end
    
    log("=== LANÇAMENTO ===")
    estado.status = "lancado"
    estado.tempo_voo = 0
    
    -- Throttle inicial máximo para decolagem
    aplicarControleVoo(config.THROTTLE_MAX, 0, 0)
end

local function armar()
    if estado.status == "lancado" and estado.tempo_voo >= config.ARMAR_DELAY then
        estado.armado = true
        estado.status = "armado"
        log("Ogiva ARMADA")
    else
        log("Não pode armar: status=" .. estado.status .. " tempo=" .. estado.tempo_voo)
    end
end

-- ======== GPS ========

local function atualizarGPS()
    local x, y, z = gps.locate(2)
    if x then
        if estado.pos_x ~= 0 or estado.pos_y ~= 0 or estado.pos_z ~= 0 then
            estado.vel_x = x - estado.pos_x
            estado.vel_y = y - estado.pos_y
            estado.vel_z = z - estado.pos_z
        end
        estado.pos_x = x
        estado.pos_y = y
        estado.pos_z = z
        return true
    end
    return false
end

-- ======== GUIAMENTO AUTOMÁTICO (GPS) ========

local function calcularRumoParaAlvo()
    if not estado.alvo_x then return end
    
    local dx = estado.alvo_x - estado.pos_x
    local dy = estado.alvo_y - estado.pos_y
    local dz = estado.alvo_z - estado.pos_z
    local dist_horizontal = math.sqrt(dx * dx + dz * dz)
    local dist_total = math.sqrt(dx * dx + dy * dy + dz * dz)
    
    if dist_total < config.GPS_PRECISAO then
        log("Alvo alcançado!")
        if estado.armado then
            ativarDetonacao()
        end
        return
    end
    
    local yaw_alvo = math.deg(math.atan2(dx, dz))
    local pitch_alvo = math.deg(math.atan2(dy, dist_horizontal))
    
    local novo_yaw = estado.yaw + (yaw_alvo - estado.yaw) * config.GPS_CORRECAO_RATE
    local novo_pitch = estado.pitch + (pitch_alvo - estado.pitch) * config.GPS_CORRECAO_RATE
    
    novo_yaw = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, novo_yaw))
    novo_pitch = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, novo_pitch))
    
    aplicarControleVoo(estado.throttle, novo_pitch, novo_yaw)
end

-- ======== COMUNICAÇÃO ========

local function enviarTelemetria()
    if not modem then return end
    
    local dados = {
        tipo = "telemetria",
        protocolo = config.PROTOCOLO,
        estado = {
            status      = estado.status,
            throttle    = estado.throttle,
            pitch       = estado.pitch,
            yaw         = estado.yaw,
            armado      = estado.armado,
            tempo_voo   = estado.tempo_voo,
            combustivel = estado.combustivel,
            pos_x       = estado.pos_x,
            pos_y       = estado.pos_y,
            pos_z       = estado.pos_z,
            vel_x       = estado.vel_x,
            vel_y       = estado.vel_y,
            vel_z       = estado.vel_z,
            modo        = estado.modo,
        }
    }
    
    modem.transmit(config.CANAL_ENVIO, config.CANAL_RECEBER, textutils.serialise(dados))
end

local function processarComando(dados)
    if type(dados) ~= "string" then return end
    
    local ok, cmd = pcall(textutils.unserialise, dados)
    if not ok or not cmd then return end
    if cmd.protocolo ~= config.PROTOCOLO then return end
    
    estado.conectado = true
    estado.ultimo_ping = os.clock()
    
    if cmd.tipo == "comando" then
        local acao = cmd.acao
        
        if acao == "lancar" then
            lancar()
        elseif acao == "armar" then
            armar()
        elseif acao == "detonar" then
            ativarDetonacao()
        elseif acao == "emergencia" then
            autodestruicao()
        elseif acao == "throttle" then
            setThrottle(cmd.valor or estado.throttle)
        elseif acao == "pitch" then
            setPitch(cmd.valor or estado.pitch)
        elseif acao == "yaw" then
            setYaw(cmd.valor or estado.yaw)
        elseif acao == "modo" then
            estado.modo = cmd.valor or config.MODO_PADRAO
            log("Modo alterado para: " .. estado.modo)
        elseif acao == "alvo" then
            estado.alvo_x = cmd.x
            estado.alvo_y = cmd.y
            estado.alvo_z = cmd.z
            log("Alvo definido: " .. cmd.x .. ", " .. cmd.y .. ", " .. cmd.z)
        elseif acao == "ping" then
            if modem then
                modem.transmit(config.CANAL_ENVIO, config.CANAL_RECEBER,
                    textutils.serialise({
                        tipo = "pong",
                        protocolo = config.PROTOCOLO
                    })
                )
            end
        end
    end
end

-- ======== LOOPS PRINCIPAIS ========

local function loopReceberComandos()
    while estado.status ~= "destruido" do
        local event, side, canal, reply, msg, dist = os.pullEvent("modem_message")
        if canal == config.CANAL_RECEBER then
            processarComando(msg)
        end
    end
end

local function loopTelemetria()
    while estado.status ~= "destruido" do
        atualizarGPS()
        
        if estado.status == "lancado" or estado.status == "armado" then
            estado.tempo_voo = estado.tempo_voo + config.INTERVALO_TELEMETRIA
            
            if estado.throttle > 0 then
                local consumo = (estado.throttle / config.THROTTLE_MAX) * config.INTERVALO_TELEMETRIA * 0.5
                estado.combustivel = math.max(0, estado.combustivel - consumo)
            end
            
            if estado.modo == config.MODO_GPS and estado.alvo_x then
                calcularRumoParaAlvo()
            end
        end
        
        if os.clock() - estado.ultimo_ping > 5 then
            estado.conectado = false
        end
        
        enviarTelemetria()
        sleep(config.INTERVALO_TELEMETRIA)
    end
end

local function loopSeguranca()
    while estado.status ~= "destruido" do
        sleep(1)
        if estado.combustivel <= 0 and estado.status ~= "idle" then
            log("SEM COMBUSTÍVEL!")
            setThrottle(0)
        end
    end
end

-- ======== MAIN ========

local function main()
    term.clear()
    term.setCursorPos(1, 1)
    print("================================")
    print("  MISSIL TELEGUIADO v2.0")
    print("  Sistema Quad Thruster 2x2")
    print("================================")
    print()
    
    local ok = inicializarPeripherals()
    if not ok then
        print()
        print("ERRO: Modem não encontrado!")
        print("Conecte um wireless modem ao computador.")
        print("Pressione qualquer tecla para sair...")
        os.pullEvent("key")
        return
    end
    
    print()
    log("Sistema 4-Thrusters pronto.")
    log("Status: " .. estado.status)
    
    parallel.waitForAny(
        loopReceberComandos,
        loopTelemetria,
        loopSeguranca
    )
    
    aplicarControleVoo(0, 0, 0)
    redstone.setOutput(config.DETONACAO_SIDE, false)
    log("Sistema encerrado.")
end

main()
