-- Startup da estacao BlockForge Remote v1
term.clear()
term.setCursorPos(1, 1)
print("BLOCKFORGE REMOTE - ESTACAO v1")
print("Iniciando link wireless...")
sleep(1)

if fs.exists("estacao.lua") then
  shell.run("estacao.lua")
else
  print("ERRO: estacao.lua nao encontrado.")
  print("Execute novamente o instalador.")
end
