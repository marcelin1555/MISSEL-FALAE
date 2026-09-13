-- ============================================
-- MISSIL TELEGUIADO - ESTAÇÃO DE CONTROLE
-- CC:Tweaked + Monitor + Wireless Modem
-- ============================================
-- Este script roda no computador da ESTAÇÃO,
-- mostrando telemetria no monitor e recebendo
-- comandos do jogador via teclado.
-- ============================================

local config = require("config")

-- ======== ESTADO DA ESTAÇÃO ========
local estacao = {
    conectado      = false,
    ultimo_ping    = 0,
    telemetria     = nil,
    modo           = config.MODO_PADRAO,
    alvo_x         = nil,
    alvo_y         = nil,
    alvo_z         = nil,
    input_ativo    = false,
    input_campo    = "",
    input_buffer   = "",
    rodando        = true,
    throttle_cmd   = config.THROTTLE_INICIAL,
    pitch_cmd      = 0,
    yaw_cmd        = 0,
}

-- ======== PERIFÉRICOS ========
local modem = nil
local monitor = nil

-- ======== FUNÇÕES AUXILIARES ========

local function log(msg)
    local timestamp = string.format("[%.1f]", os.clock())
    -- Imprime no terminal do computador, não no monitor
    local old = term.redirect(term.native())
    print(timestamp .. " " .. msg)
    if old then term.redirect(old) end
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

local function encontrarMonitor()
    return peripheral.find("monitor")
end

-- ======== COMUNICAÇÃO ========

local function enviarComando(acao, extras)
    if not modem then return end
    
    local cmd = {
        tipo = "comando",
        protocolo = config.PROTOCOLO,
        acao = acao,
    }
    
    if extras then
        for k, v in pairs(extras) do
            cmd[k] = v
        end
    end
    
    modem.transmit(config.CANAL_ENVIO, config.CANAL_RECEBER, textutils.serialise(cmd))
end

local function ping()
    enviarComando("ping")
end

-- ======== DESENHO DO MONITOR ========

local mon -- referência ao monitor para drawing

local function monClear()
    mon.setBackgroundColor(config.COR_FUNDO)
    mon.clear()
end

local function monEscrever(x, y, texto, cor_texto, cor_fundo)
    mon.setCursorPos(x, y)
    if cor_texto then mon.setTextColor(cor_texto) end
    if cor_fundo then mon.setBackgroundColor(cor_fundo) end
    mon.write(texto)
    -- Reset
    mon.setTextColor(config.COR_TEXTO)
    mon.setBackgroundColor(config.COR_FUNDO)
end

local function monLinha(y, char)
    local w, _ = mon.getSize()
    mon.setCursorPos(1, y)
    mon.setTextColor(colors.gray)
    mon.write(string.rep(char or "-", w))
    mon.setTextColor(config.COR_TEXTO)
end

local function monBarraProgresso(x, y, largura, valor, max, cor)
    local preenchido = math.floor((valor / max) * largura)
    mon.setCursorPos(x, y)
    
    for i = 1, largura do
        if i <= preenchido then
            mon.setBackgroundColor(cor or config.COR_BARRA)
            mon.write(" ")
        else
            mon.setBackgroundColor(colors.gray)
            mon.write(" ")
        end
    end
    
    mon.setBackgroundColor(config.COR_FUNDO)
end

local function desenharHUD()
    if not mon then return end
    
    local w, h = mon.getSize()
    monClear()
    
    -- ======== TÍTULO ========
    local titulo = " MISSIL TELEGUIADO v1.0 "
    local titulo_x = math.floor((w - #titulo) / 2) + 1
    monEscrever(titulo_x, 1, titulo, colors.black, config.COR_TITULO)
    
    -- ======== STATUS DE CONEXÃO ========
    local status_con = estacao.conectado and "CONECTADO" or "DESCONECTADO"
    local cor_con = estacao.conectado and config.COR_OK or config.COR_ALERTA
    monEscrever(2, 2, "Link: ", config.COR_INFO)
    monEscrever(8, 2, status_con, cor_con)
    
    monLinha(3, "=")
    
    local tel = estacao.telemetria
    
    if tel then
        -- ======== STATUS DO MÍSSIL ========
        local status_texto = string.upper(tel.status or "???")
        local cor_status = config.COR_TEXTO
        if tel.status == "idle" then cor_status = colors.lightGray
        elseif tel.status == "lancado" then cor_status = config.COR_OK
        elseif tel.status == "armado" then cor_status = config.COR_BARRA
        elseif tel.status == "detonado" then cor_status = config.COR_ALERTA
        elseif tel.status == "destruido" then cor_status = colors.red
        end
        
        monEscrever(2, 4, "Status:", config.COR_INFO)
        monEscrever(10, 4, status_texto, cor_status)
        
        -- Modo
        local modo_texto = string.upper(tel.modo or "???")
        monEscrever(2, 5, "Modo:  ", config.COR_INFO)
        monEscrever(10, 5, modo_texto, config.COR_TITULO)
        
        -- Armado
        local arm_texto = tel.armado and "SIM" or "NAO"
        local arm_cor = tel.armado and config.COR_ALERTA or colors.lightGray
        monEscrever(2, 6, "Armado:", config.COR_INFO)
        monEscrever(10, 6, arm_texto, arm_cor)
        
        monLinha(7, "-")
        
        -- ======== TELEMETRIA DE VOO ========
        monEscrever(2, 8, "TELEMETRIA DE VOO", config.COR_TITULO)
        
        -- Throttle
        monEscrever(2, 9, "Throttle:", config.COR_INFO)
        local throttle_pct = math.floor((tel.throttle / config.THROTTLE_MAX) * 100)
        monEscrever(12, 9, string.format("%d%%", throttle_pct))
        monBarraProgresso(18, 9, math.min(12, w - 19), tel.throttle, config.THROTTLE_MAX, 
            throttle_pct > 80 and config.COR_ALERTA or config.COR_OK)
        
        -- Pitch / Yaw
        monEscrever(2, 10, "Pitch:", config.COR_INFO)
        monEscrever(10, 10, string.format("%+.1f", tel.pitch or 0) .. "°")
        
        monEscrever(2, 11, "Yaw:  ", config.COR_INFO)
        monEscrever(10, 11, string.format("%+.1f", tel.yaw or 0) .. "°")
        
        -- Combustível
        monEscrever(2, 12, "Fuel: ", config.COR_INFO)
        local fuel = tel.combustivel or 0
        local fuel_cor = fuel > 50 and config.COR_OK or (fuel > 20 and config.COR_BARRA or config.COR_ALERTA)
        monEscrever(10, 12, string.format("%.0f%%", fuel))
        monBarraProgresso(18, 12, math.min(12, w - 19), fuel, 100, fuel_cor)
        
        -- Tempo de voo
        monEscrever(2, 13, "Tempo:", config.COR_INFO)
        monEscrever(10, 13, string.format("%.1fs", tel.tempo_voo or 0))
        
        monLinha(14, "-")
        
        -- ======== POSIÇÃO GPS ========
        monEscrever(2, 15, "POSICAO GPS", config.COR_TITULO)
        
        monEscrever(2, 16, "X:", config.COR_INFO)
        monEscrever(5, 16, string.format("%.1f", tel.pos_x or 0))
        
        monEscrever(2, 17, "Y:", config.COR_INFO)
        monEscrever(5, 17, string.format("%.1f", tel.pos_y or 0))
        
        monEscrever(2, 18, "Z:", config.COR_INFO)
        monEscrever(5, 18, string.format("%.1f", tel.pos_z or 0))
        
        -- Velocidade
        if tel.vel_x then
            local vel = math.sqrt((tel.vel_x or 0)^2 + (tel.vel_y or 0)^2 + (tel.vel_z or 0)^2)
            monEscrever(16, 16, "Vel:", config.COR_INFO)
            monEscrever(21, 16, string.format("%.1f m/s", vel * 20)) -- blocos/tick -> m/s
        end
        
        -- Alvo (se modo GPS)
        if estacao.alvo_x then
            monLinha(19, "-")
            monEscrever(2, 20, "ALVO", config.COR_TITULO)
            monEscrever(2, 21, string.format("X:%.0f Y:%.0f Z:%.0f",
                estacao.alvo_x, estacao.alvo_y, estacao.alvo_z), config.COR_BARRA)
            
            -- Distância até o alvo
            if tel.pos_x and estacao.alvo_x then
                local dx = estacao.alvo_x - tel.pos_x
                local dy = estacao.alvo_y - tel.pos_y
                local dz = estacao.alvo_z - tel.pos_z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                monEscrever(2, 22, "Dist: ", config.COR_INFO)
                monEscrever(8, 22, string.format("%.1f blocos", dist),
                    dist < 10 and config.COR_ALERTA or config.COR_TEXTO)
            end
        end
        
    else
        -- Sem telemetria
        monEscrever(2, 5, "Aguardando telemetria...", colors.lightGray)
        monEscrever(2, 7, "Verifique se o missil esta", colors.lightGray)
        monEscrever(2, 8, "ligado e com modem ativo.", colors.lightGray)
    end
    
    -- ======== CONTROLES (rodapé) ========
    local footer_y = math.max(h - 4, 23)
    monLinha(footer_y, "=")
    monEscrever(2, footer_y + 1, "CONTROLES", config.COR_TITULO)
    monEscrever(2, footer_y + 2, "WASD:Direcao SPACE/SHIFT:Pot", colors.lightGray)
    monEscrever(2, footer_y + 3, "ENTER:Lancar F:Armar X:Detonar", colors.lightGray)
    monEscrever(2, footer_y + 4, "M:Modo  BKSP:Emergencia  Q:Sair", colors.lightGray)
end

-- ======== PROCESSAMENTO DE TECLAS ========

local function processarTecla(tecla)
    -- Input de coordenadas GPS ativo?
    if estacao.input_ativo then
        -- Processar digitação de coordenadas
        if tecla == keys.enter then
            -- Finalizar input
            local val = tonumber(estacao.input_buffer)
            if val then
                if estacao.input_campo == "x" then
                    estacao.alvo_x = val
                    estacao.input_campo = "y"
                    estacao.input_buffer = ""
                    log("Alvo X = " .. val .. ". Digite Y:")
                elseif estacao.input_campo == "y" then
                    estacao.alvo_y = val
                    estacao.input_campo = "z"
                    estacao.input_buffer = ""
                    log("Alvo Y = " .. val .. ". Digite Z:")
                elseif estacao.input_campo == "z" then
                    estacao.alvo_z = val
                    estacao.input_ativo = false
                    estacao.input_buffer = ""
                    log("Alvo Z = " .. val)
                    log("Alvo definido: " .. estacao.alvo_x .. ", " .. estacao.alvo_y .. ", " .. estacao.alvo_z)
                    -- Enviar alvo para o míssil
                    enviarComando("alvo", {
                        x = estacao.alvo_x,
                        y = estacao.alvo_y,
                        z = estacao.alvo_z
                    })
                end
            else
                log("Valor invalido! Tente novamente.")
                estacao.input_buffer = ""
            end
        elseif tecla == keys.backspace then
            estacao.input_buffer = string.sub(estacao.input_buffer, 1, -2)
        end
        return
    end
    
    -- Controles normais
    if tecla == config.TECLA_CIMA then
        estacao.pitch_cmd = estacao.pitch_cmd + config.TILT_STEP
        enviarComando("pitch", { valor = estacao.pitch_cmd })
        
    elseif tecla == config.TECLA_BAIXO then
        estacao.pitch_cmd = estacao.pitch_cmd - config.TILT_STEP
        enviarComando("pitch", { valor = estacao.pitch_cmd })
        
    elseif tecla == config.TECLA_ESQUERDA then
        estacao.yaw_cmd = estacao.yaw_cmd - config.TILT_STEP
        enviarComando("yaw", { valor = estacao.yaw_cmd })
        
    elseif tecla == config.TECLA_DIREITA then
        estacao.yaw_cmd = estacao.yaw_cmd + config.TILT_STEP
        enviarComando("yaw", { valor = estacao.yaw_cmd })
        
    elseif tecla == config.TECLA_THROTTLE_UP then
        estacao.throttle_cmd = math.min(config.THROTTLE_MAX, estacao.throttle_cmd + config.THROTTLE_STEP)
        enviarComando("throttle", { valor = estacao.throttle_cmd })
        
    elseif tecla == config.TECLA_THROTTLE_DOWN then
        estacao.throttle_cmd = math.max(config.THROTTLE_MIN, estacao.throttle_cmd - config.THROTTLE_STEP)
        enviarComando("throttle", { valor = estacao.throttle_cmd })
        
    elseif tecla == config.TECLA_LANCAR then
        log("Comando: LANCAR!")
        estacao.throttle_cmd = config.THROTTLE_MAX
        enviarComando("lancar")
        
    elseif tecla == config.TECLA_ARMAR then
        log("Comando: ARMAR ogiva")
        enviarComando("armar")
        
    elseif tecla == config.TECLA_DETONAR then
        log("Comando: DETONAR!")
        enviarComando("detonar")
        
    elseif tecla == config.TECLA_EMERGENCIA then
        log("!!! EMERGENCIA - AUTODESTRUICAO !!!")
        enviarComando("emergencia")
        
    elseif tecla == config.TECLA_MODO then
        -- Alternar modo
        if estacao.modo == config.MODO_MANUAL then
            estacao.modo = config.MODO_GPS
            log("Modo alterado para GPS")
            -- Pedir coordenadas do alvo
            log("Digite coordenada X do alvo:")
            estacao.input_ativo = true
            estacao.input_campo = "x"
            estacao.input_buffer = ""
        else
            estacao.modo = config.MODO_MANUAL
            log("Modo alterado para MANUAL")
        end
        enviarComando("modo", { valor = estacao.modo })
        
    elseif tecla == config.TECLA_SAIR then
        log("Encerrando estacao de controle...")
        estacao.rodando = false
    end
end

local function processarChar(char)
    if estacao.input_ativo then
        -- Aceitar dígitos, ponto e sinal negativo
        if char:match("[%d%.%-]") then
            estacao.input_buffer = estacao.input_buffer .. char
        end
    end
end

-- ======== LOOPS PRINCIPAIS ========

local function loopReceberTelemetria()
    while estacao.rodando do
        local event, side, canal, reply, msg, dist = os.pullEvent("modem_message")
        if canal == config.CANAL_RECEBER then
            local ok, dados = pcall(textutils.unserialise, msg)
            if ok and dados and dados.protocolo == config.PROTOCOLO then
                if dados.tipo == "telemetria" then
                    estacao.telemetria = dados.estado
                    estacao.conectado = true
                    estacao.ultimo_ping = os.clock()
                elseif dados.tipo == "pong" then
                    estacao.conectado = true
                    estacao.ultimo_ping = os.clock()
                end
            end
        end
    end
end

local function loopInput()
    while estacao.rodando do
        local event, param = os.pullEvent()
        if event == "key" then
            processarTecla(param)
        elseif event == "char" then
            processarChar(param)
        end
    end
end

local function loopDesenhar()
    while estacao.rodando do
        -- Verificar timeout de conexão
        if os.clock() - estacao.ultimo_ping > 3 then
            estacao.conectado = false
        end
        
        -- Redesenhar HUD
        desenharHUD()
        
        -- Ping periódico
        ping()
        
        sleep(0.5)
    end
end

-- ======== INICIALIZAÇÃO ========

local function inicializar()
    term.clear()
    term.setCursorPos(1, 1)
    print("================================")
    print("  ESTACAO DE CONTROLE v1.0")
    print("  Missil Teleguiado")
    print("================================")
    print()
    
    -- Modem
    modem = encontrarModem()
    if not modem then
        print("ERRO: Nenhum modem wireless encontrado!")
        print("Conecte um modem wireless ao computador.")
        return false
    end
    modem.open(config.CANAL_RECEBER)
    modem.open(config.CANAL_ENVIO)
    print("Modem wireless inicializado")
    
    -- Monitor
    monitor = encontrarMonitor()
    if monitor then
        mon = monitor
        mon.setTextScale(config.MONITOR_SCALE)
        print("Monitor encontrado e configurado")
    else
        -- Sem monitor, usa o terminal do computador
        mon = term.current()
        print("AVISO: Sem monitor externo, usando terminal")
    end
    
    print()
    print("Estacao pronta! Use as teclas para controlar.")
    print("Pressione Q para sair.")
    print()
    
    return true
end

-- ======== MAIN ========

local function main()
    if not inicializar() then
        print("Pressione qualquer tecla para sair...")
        os.pullEvent("key")
        return
    end
    
    -- Rodar loops em paralelo
    parallel.waitForAny(
        loopReceberTelemetria,
        loopInput,
        loopDesenhar
    )
    
    -- Limpar
    if monitor then
        monitor.setBackgroundColor(colors.black)
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Estacao desligada")
    end
    
    term.clear()
    term.setCursorPos(1, 1)
    print("Estacao de controle encerrada.")
end

main()
