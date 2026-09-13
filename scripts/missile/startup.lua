-- ============================================
-- MISSIL TELEGUIADO - STARTUP DO MÍSSIL
-- ============================================
-- Este arquivo deve ser colocado como startup.lua
-- no computador embarcado do míssil.
-- ============================================

-- Configurar path para encontrar os módulos
shell.setPath(shell.path() .. ":.")

-- Copiar config.lua se necessário (caso esteja numa subpasta)
if not fs.exists("config.lua") and fs.exists("missile/config.lua") then
    fs.copy("missile/config.lua", "config.lua")
end

-- Rodar o script principal do míssil
print("Inicializando sistema do missil...")
sleep(1)

if fs.exists("missile.lua") then
    shell.run("missile.lua")
elseif fs.exists("missile/missile.lua") then
    shell.run("missile/missile.lua")
else
    print("ERRO: missile.lua nao encontrado!")
    print("Verifique a instalacao dos arquivos.")
end
