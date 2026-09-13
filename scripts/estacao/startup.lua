-- ============================================
-- MISSIL TELEGUIADO - STARTUP DA ESTAÇÃO
-- ============================================
-- Este arquivo deve ser colocado como startup.lua
-- no computador da estação de controle.
-- ============================================

shell.setPath(shell.path() .. ":.")

-- Copiar config.lua se necessário
if not fs.exists("config.lua") and fs.exists("estacao/config.lua") then
    fs.copy("estacao/config.lua", "config.lua")
end

print("Inicializando estacao de controle...")
sleep(1)

if fs.exists("estacao.lua") then
    shell.run("estacao.lua")
elseif fs.exists("estacao/estacao.lua") then
    shell.run("estacao/estacao.lua")
else
    print("ERRO: estacao.lua nao encontrado!")
    print("Verifique a instalacao dos arquivos.")
end
