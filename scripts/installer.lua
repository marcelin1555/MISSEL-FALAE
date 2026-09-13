-- ============================================
-- MISSIL TELEGUIADO - INSTALADOR
-- ============================================
-- Execute este script em qualquer computador
-- CC:Tweaked para instalar os arquivos do
-- míssil ou da estação de controle.
--
-- USO:
--   No terminal do computador, digite:
--     installer missil
--     installer estacao
-- ============================================

local args = { ... }

local function printBanner()
    term.clear()
    term.setCursorPos(1, 1)
    print("================================")
    print("  INSTALADOR MISSIL TELEGUIADO")
    print("  v1.0")
    print("================================")
    print()
end

local function printUso()
    print("Uso: installer <tipo>")
    print()
    print("Tipos disponiveis:")
    print("  missil  - Instala scripts do missil")
    print("  estacao - Instala scripts da estacao")
    print()
    print("Exemplo:")
    print("  installer missil")
end

-- Arquivos embutidos no instalador
-- (cada um como string para não depender de download)

local CONFIG_LUA = [[
local config = {}
config.CANAL_ENVIO    = 42
config.CANAL_RECEBER  = 43
config.PROTOCOLO      = "MISSIL_TG"
config.INTERVALO_TELEMETRIA = 0.25
config.MODEM_SIDE          = nil
config.TILT_PITCH_NAME     = nil
config.TILT_YAW_NAME       = nil
config.THROTTLE_MIN        = 0
config.THROTTLE_MAX        = 15
config.THROTTLE_INICIAL    = 0
config.TILT_MAX_ANGLE      = 45
config.TILT_STEP           = 5
config.THROTTLE_STEP       = 1
config.THRUSTER_SIDE       = "back"
config.DETONACAO_SIDE      = "top"
config.MODO_MANUAL         = "manual"
config.MODO_GPS            = "gps"
config.MODO_PADRAO         = "manual"
config.GPS_PRECISAO        = 3
config.GPS_CORRECAO_RATE   = 0.1
config.ARMAR_DELAY         = 3
config.TIPO_DETONACAO      = "redstone"
config.MONITOR_SCALE       = 0.5
config.COR_FUNDO           = colors.black
config.COR_TEXTO           = colors.white
config.COR_TITULO          = colors.yellow
config.COR_ALERTA          = colors.red
config.COR_OK              = colors.lime
config.COR_INFO            = colors.cyan
config.COR_BARRA           = colors.orange
config.TECLA_CIMA          = keys.w
config.TECLA_BAIXO         = keys.s
config.TECLA_ESQUERDA      = keys.a
config.TECLA_DIREITA       = keys.d
config.TECLA_THROTTLE_UP   = keys.space
config.TECLA_THROTTLE_DOWN = keys.leftShift
config.TECLA_LANCAR        = keys.enter
config.TECLA_ARMAR         = keys.f
config.TECLA_DETONAR       = keys.x
config.TECLA_EMERGENCIA    = keys.backspace
config.TECLA_MODO          = keys.m
config.TECLA_SAIR          = keys.q
return config
]]

local function escreverArquivo(caminho, conteudo)
    local dir = fs.getDir(caminho)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(caminho, "w")
    if f then
        f.write(conteudo)
        f.close()
        print("  [OK] " .. caminho)
        return true
    else
        print("  [ERRO] Nao conseguiu escrever: " .. caminho)
        return false
    end
end

local function instalarMissil()
    print("Instalando scripts do MISSIL...")
    print()
    
    -- config.lua
    escreverArquivo("config.lua", CONFIG_LUA)
    
    -- startup.lua
    local startup = [[
shell.setPath(shell.path() .. ":.")
print("Inicializando sistema do missil...")
sleep(1)
if fs.exists("missile.lua") then
    shell.run("missile.lua")
else
    print("ERRO: missile.lua nao encontrado!")
end
]]
    escreverArquivo("startup.lua", startup)
    
    -- missile.lua - precisa ser baixado ou copiado manualmente
    -- Por enquanto, cria um placeholder com instrução
    if not fs.exists("missile.lua") then
        print()
        print("IMPORTANTE: Copie o arquivo 'missile.lua'")
        print("do repositorio para este computador.")
        print()
        print("Opcao 1: Use 'edit missile.lua' e cole o codigo")
        print("Opcao 2: Copie para a pasta do mundo:")
        print("  saves/<mundo>/computercraft/computer/<id>/")
    else
        print("  [OK] missile.lua ja existe")
    end
    
    print()
    print("Instalacao do missil concluida!")
    print("Reinicie o computador com: reboot")
end

local function instalarEstacao()
    print("Instalando scripts da ESTACAO...")
    print()
    
    -- config.lua
    escreverArquivo("config.lua", CONFIG_LUA)
    
    -- startup.lua
    local startup = [[
shell.setPath(shell.path() .. ":.")
print("Inicializando estacao de controle...")
sleep(1)
if fs.exists("estacao.lua") then
    shell.run("estacao.lua")
else
    print("ERRO: estacao.lua nao encontrado!")
end
]]
    escreverArquivo("startup.lua", startup)
    
    -- estacao.lua
    if not fs.exists("estacao.lua") then
        print()
        print("IMPORTANTE: Copie o arquivo 'estacao.lua'")
        print("do repositorio para este computador.")
        print()
        print("Opcao 1: Use 'edit estacao.lua' e cole o codigo")
        print("Opcao 2: Copie para a pasta do mundo:")
        print("  saves/<mundo>/computercraft/computer/<id>/")
    else
        print("  [OK] estacao.lua ja existe")
    end
    
    print()
    print("Instalacao da estacao concluida!")
    print("Reinicie o computador com: reboot")
end

-- ======== MAIN ========

printBanner()

if #args == 0 then
    printUso()
    return
end

local tipo = string.lower(args[1])

if tipo == "missil" or tipo == "missile" then
    instalarMissil()
elseif tipo == "estacao" or tipo == "station" then
    instalarEstacao()
else
    print("Tipo desconhecido: " .. tipo)
    print()
    printUso()
end
