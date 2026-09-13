-- ============================================
-- MISSIL TELEGUIADO - INSTALADOR AUTOMÁTICO
-- ============================================
-- Instala automaticamente os arquivos do projeto
-- via GitHub no CC:Tweaked.

local BASE_URL = "https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/"

local args = { ... }

local function download(urlPath, savePath)
    print("Baixando: " .. savePath .. "...")
    if not http then
        print("  [ERRO] API HTTP nao esta ativada no CC:Tweaked!")
        return false
    end
    local response = http.get(BASE_URL .. urlPath)
    if response then
        local content = response.readAll()
        response.close()
        local dir = fs.getDir(savePath)
        if dir and dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end
        local file = fs.open(savePath, "w")
        if file then
            file.write(content)
            file.close()
            print("  [OK] Salvo com sucesso!")
            return true
        else
            print("  [ERRO] Falha ao criar arquivo: " .. savePath)
        end
    else
        print("  [ERRO] Falha na conexao: " .. BASE_URL .. urlPath)
    end
    return false
end

local function printBanner()
    term.clear()
    term.setCursorPos(1, 1)
    print("================================")
    print("  INSTALADOR MISSIL TELEGUIADO")
    print("  v1.0 - GitHub Auto-Installer")
    print("================================")
    print()
end

local function printUso()
    print("Uso: installer <tipo>")
    print()
    print("Tipos disponiveis:")
    print("  missil  - Baixa e instala scripts do missil")
    print("  estacao - Baixa e instala scripts da estacao")
    print()
    print("Exemplo:")
    print("  installer missil")
end

local function instalarMissil()
    print("Instalando scripts do MISSIL...")
    print()
    download("config.lua", "config.lua")
    download("missile/startup.lua", "startup.lua")
    download("missile/missile.lua", "missile.lua")
    download("missile/teste.lua", "teste.lua")
    download("missile/calibrar_gimbal.lua", "calibrar_gimbal.lua")
    download("missile/calibrar.lua", "calibrar.lua")
    print()
    print("Instalacao do Missil Concluida!")
    print("Para calibrar o gimbal, digite: calibrar_gimbal")
    print("Para calibrar o bocal, digite: calibrar")
    print("Para testar os motores, digite: teste")
    print("Para iniciar o sistema de voo, digite: reboot")
end

local function instalarEstacao()
    print("Instalando scripts da ESTACAO DE CONTROLE...")
    print()
    download("config.lua", "config.lua")
    download("estacao/startup.lua", "startup.lua")
    download("estacao/estacao.lua", "estacao.lua")
    print()
    print("Instalacao da Estacao Concluida!")
    print("Digite 'reboot' para iniciar a interface.")
end

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
    print("Tipo invalido: " .. tipo)
    printUso()
end
