-- ============================================
-- MISSIL TELEGUIADO - STARTUP DO MÍSSIL
-- ============================================
-- Este arquivo deve ser colocado como startup.lua
-- no computador embarcado do míssil.
-- ============================================

shell.setPath(shell.path() .. ":.")

if not fs.exists("config.lua") and fs.exists("missile/config.lua") then
    fs.copy("missile/config.lua", "config.lua")
end

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("  🚀 SISTERMA DO MÍSSIL TELESGUIADO v3.0")
print("========================================")
print()
print("  [T] Rodar Bateria de Testes (Motores/Vetores)")
print("  [Qualquer outra tecla] Iniciar Voo Normal")
print()
print("Iniciando em 3 segundos...")

local timer = os.startTimer(3)
local runTest = false

while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timer then
        break
    elseif event == "char" then
        if string.lower(p1) == "t" then
            runTest = true
            break
        end
    elseif event == "key" then
        if p1 == keys.t then
            runTest = true
            break
        else
            break
        end
    end
end

if runTest then
    print()
    print("Iniciando Bateria de Testes de Bancada...")
    sleep(1)
    if fs.exists("teste.lua") then
        shell.run("teste.lua")
    elseif fs.exists("missile/teste.lua") then
        shell.run("missile/teste.lua")
    else
        print("ERRO: teste.lua nao encontrado!")
    end
else
    print()
    print("Inicializando sistema principal...")
    sleep(1)
    if fs.exists("missile.lua") then
        shell.run("missile.lua")
    elseif fs.exists("missile/missile.lua") then
        shell.run("missile/missile.lua")
    else
        print("ERRO: missile.lua nao encontrado!")
    end
end
