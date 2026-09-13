-- Inicializador do controlador BlockForge Militar standalone
term.clear()
term.setCursorPos(1, 1)
print("BLOCKFORGE MILITAR - CONTROLADOR v2.0")
print("Iniciando...")
sleep(1)

if fs.exists("missil.lua") then
  shell.run("missil.lua")
elseif fs.exists("missile.lua") then
  shell.run("missile.lua")
else
  print("ERRO: missil.lua nao encontrado.")
  print("Execute novamente o instalador.")
end
