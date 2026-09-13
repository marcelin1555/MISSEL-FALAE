-- Instalador do controlador BlockForge Militar
local BASE_URL = "https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/"
local args = { ... }

local function download(remotePath, localPath)
  print("Baixando " .. localPath .. "...")
  if not http then
    print("ERRO: API HTTP desativada no CC:Tweaked.")
    return false
  end
  local response = http.get(BASE_URL .. remotePath)
  if not response then
    print("ERRO: falha ao baixar " .. remotePath)
    return false
  end
  local content = response.readAll()
  response.close()
  local file = fs.open(localPath, "w")
  if not file then
    print("ERRO: nao foi possivel criar " .. localPath)
    return false
  end
  file.write(content)
  file.close()
  print("OK: " .. localPath)
  return true
end

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("  BLOCKFORGE MILITAR - INSTALADOR")
print("  Controlador standalone v2.0")
print("========================================")
print()

local tipo = string.lower(args[1] or "")
if tipo == "missil" or tipo == "missile" then
  local ok1 = download("missile/missil.lua", "missil.lua")
  local ok2 = download("missile/startup.lua", "startup.lua")
  print()
  if ok1 and ok2 then
    print("Instalacao concluida.")
    print("Execute: missil")
    print("Ou reinicie com: reboot")
  else
    print("Instalacao incompleta.")
  end
elseif tipo == "estacao" or tipo == "station" then
  download("estacao/startup.lua", "startup.lua")
  download("estacao/estacao.lua", "estacao.lua")
  print("Estacao nova instalada.")
  print("No veiculo, inicie: missil remoto")
else
  print("Uso: installer missil   ou   installer estacao")
  print("missil: controlador local BlockForge")
  print("estacao: painel remoto wireless novo")
end
