-- ============================================
-- MISSIL TELEGUIADO - SCRIPT PRINCIPAL DO MÍSSIL
-- CC:Tweaked + Create Propulsion + Aeronautics
-- ============================================
-- Este script roda no computador EMBARCADO no míssil.
-- Ele controla thrusters, tilt adapters e se comunica
-- com a estação de controle via wireless modem.
-- ============================================

local config = require("config")

-- ======== ESTADO DO MÍSSIL ========
local estado = {
    status       = "idle",      -- idle, lancado, armado, detonado, destruido
    throttle     = config.THROTTLE_INICIAL,
    pitch        = 0,           -- ângulo pitch atual (graus)
    yaw          = 0,           -- ângulo yaw atual (graus)
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
local tilt_adapters = {}
local redstone_sides = {}

-- ======== FUNÇÕES AUXILIARES ========

local function log(msg)
    local timestamp = string.format("[%.1f]", os.clock())
    print(timestamp .. " " .. msg)
end

local function encontrarModem()
    -- Tenta encontrar um modem (prioridade: ender > wireless)
    local modems = { peripheral.find("modem") }
    for _, m in ipairs(modems) do
        if m.isWireless and m.isWireless() then
            return m
        end
    end
    -- Fallback: qualquer modem
    if #modems > 0 then return modems[1] end
    return nil
end

local function encontrarTiltAdapters()
    -- Procura todos os tilt adapters conectados
    local adapters = {}
    local nomes = peripheral.getNames()
    for _, nome in ipairs(nomes) do
        local tipo = peripheral.getType(nome)
        if tipo and (string.find(tipo, "tilt") or string.find(tipo, "Tilt")) then
            table.insert(adapters, {
                nome = nome,
                periferico = peripheral.wrap(nome)
            })
            log("Tilt adapter encontrado: " .. nome)
        end
    end
    return adapters
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
    
    -- Tilt adapters
    tilt_adapters = encontrarTiltAdapters()
    if #tilt_adapters == 0 then
        log("AVISO: Nenhum tilt adapter encontrado!")
    else
        log("Tilt adapters encontrados: " .. #tilt_adapters)
    end
    
    -- Teste de redstone
    log("Thruster no lado: " .. config.THRUSTER_SIDE)
    log("Detonação no lado: " .. config.DETONACAO_SIDE)
    
    return modem ~= nil
end

-- ======== CONTROLE DE VOO ========

local function setThrottle(nivel)
    nivel = math.max(config.THROTTLE_MIN, math.min(config.THROTTLE_MAX, nivel))
    estado.throttle = nivel
    redstone.setAnalogOutput(config.THRUSTER_SIDE, nivel)
end

local function setPitch(angulo)
    angulo = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, angulo))
    estado.pitch = angulo
    
    -- Aplica nos tilt adapters de pitch
    for i, adapter in ipairs(tilt_adapters) do
        if adapter.periferico.setTargetAngle then
            -- Se for o primeiro adapter, usa como pitch
            if i == 1 or (i % 2 == 1) then
                pcall(function()
                    adapter.periferico.setTargetAngle(angulo)
                end)
            end
        end
    end
end

local function setYaw(angulo)
    angulo = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, angulo))
    estado.yaw = angulo
    
    -- Aplica nos tilt adapters de yaw
    for i, adapter in ipairs(tilt_adapters) do
        if adapter.periferico.setTargetAngle then
            -- Se for o segundo adapter, usa como yaw
            if i == 2 or (i % 2 == 0) then
                pcall(function()
                    adapter.periferico.setTargetAngle(angulo)
                end)
            end
        end
    end
end

local function ativarDetonacao()
    if estado.armado then
        estado.status = "detonado"
        redstone.setOutput(config.DETONACAO_SIDE, true)
        log("*** DETONAÇÃO ATIVADA ***")
        -- Pulso de redstone
        sleep(0.5)
        redstone.setOutput(config.DETONACAO_SIDE, false)
    else
        log("Ogiva não armada - detonação recusada")
    end
end

local function autodestruicao()
    log("!!! AUTODESTRUIÇÃO ATIVADA !!!")
    estado.status = "destruido"
    setThrottle(0)
    setPitch(0)
    setYaw(0)
    -- Ativa detonação independente do estado de armamento
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
    setThrottle(config.THROTTLE_MAX)
    setPitch(0)
    setYaw(0)
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
    -- Tenta obter posição via GPS do CC:Tweaked
    local x, y, z = gps.locate(2)
    if x then
        -- Calcular velocidade (delta de posição)
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
    
    -- Calcular ângulos necessários
    local yaw_alvo = math.deg(math.atan2(dx, dz))
    local pitch_alvo = math.deg(math.atan2(dy, dist_horizontal))
    
    -- Aplicar correção gradual
    local novo_yaw = estado.yaw + (yaw_alvo - estado.yaw) * config.GPS_CORRECAO_RATE
    local novo_pitch = estado.pitch + (pitch_alvo - estado.pitch) * config.GPS_CORRECAO_RATE
    
    -- Clampar nos limites
    novo_yaw = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, novo_yaw))
    novo_pitch = math.max(-config.TILT_MAX_ANGLE, math.min(config.TILT_MAX_ANGLE, novo_pitch))
    
    setYaw(novo_yaw)
    setPitch(novo_pitch)
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
            -- Responde com pong
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
        -- Atualizar GPS
        atualizarGPS()
        
        -- Atualizar tempo de voo
        if estado.status == "lancado" or estado.status == "armado" then
            estado.tempo_voo = estado.tempo_voo + config.INTERVALO_TELEMETRIA
            
            -- Estimar consumo de combustível
            if estado.throttle > 0 then
                local consumo = (estado.throttle / config.THROTTLE_MAX) * config.INTERVALO_TELEMETRIA * 0.5
                estado.combustivel = math.max(0, estado.combustivel - consumo)
            end
            
            -- Guiamento automático se no modo GPS
            if estado.modo == config.MODO_GPS and estado.alvo_x then
                calcularRumoParaAlvo()
            end
        end
        
        -- Verificar conexão (timeout de 5 segundos)
        if os.clock() - estado.ultimo_ping > 5 then
            estado.conectado = false
        end
        
        -- Enviar telemetria
        enviarTelemetria()
        
        sleep(config.INTERVALO_TELEMETRIA)
    end
end

local function loopSeguranca()
    -- Loop de segurança: se perder combustível ou conexão por muito tempo
    while estado.status ~= "destruido" do
        sleep(1)
        
        -- Se sem combustível e em voo, desligar thrusters
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
    print("  MISSIL TELEGUIADO v1.0")
    print("  Sistema de Controle de Voo")
    print("================================")
    print()
    
    -- Inicializar
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
    log("Sistema pronto. Aguardando comandos...")
    log("Status: " .. estado.status)
    
    -- Rodar loops em paralelo
    parallel.waitForAny(
        loopReceberComandos,
        loopTelemetria,
        loopSeguranca
    )
    
    -- Desligar tudo ao sair
    setThrottle(0)
    setPitch(0)
    setYaw(0)
    redstone.setOutput(config.DETONACAO_SIDE, false)
    log("Sistema encerrado.")
end

main()
