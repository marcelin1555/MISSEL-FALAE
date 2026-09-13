-- Inicializador do controlador BlockForge Militar standalone
term.clear()
term.setCursorPos(1, 1)
print("BLOCKFORGE MILITAR - CONTROLADOR v2.0")
print("R = modo remoto   ENTER = modo local")
local remoto = false
local timer = os.startTimer(5)
while true do
  local event, value = os.pullEvent()
  if event == "char" and value:lower() == "r" then remoto = true; break end
  if event == "key" and value == keys.enter then break end
  if event == "timer" and value == timer then break end
end

if fs.exists("missil.lua") then
  if remoto then shell.run("missil.lua", "remoto") else shell.run("missil.lua") end
elseif fs.exists("missile.lua") then
  shell.run("missile.lua")
else
  print("ERRO: missil.lua nao encontrado.")
  print("Execute novamente o instalador.")
end
