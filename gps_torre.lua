-- gps_torre.lua : BlockForge Militar - Torre de GPS
-- Na primeira vez pergunta a coordenada deste computador,
-- cria o startup e fica respondendo os pedidos de GPS.
-- Monte 4 torres (ou mais), em alturas diferentes, com Ender Modem.

local ARQ = "/gps_torre.cfg"
local MARCA_STARTUP = "-- bfm_gps_torre"

local W, H = term.getSize()
local COR = term.isColor()

local function cor(c) if COR then term.setTextColor(c) end end
local function fundo(c) if COR then term.setBackgroundColor(c) end end

local function escrever(x, y, txt, c)
  term.setCursorPos(x, y)
  cor(c or colors.white)
  term.write(txt)
  cor(colors.white)
end

local function cabecalho(titulo)
  fundo(colors.black)
  term.clear()
  fundo(colors.gray)
  term.setCursorPos(1, 1)
  term.clearLine()
  cor(colors.yellow)
  term.write(" BLOCKFORGE MILITAR")
  cor(colors.white)
  term.setCursorPos(math.max(21, W - #titulo), 1)
  term.write(titulo)
  fundo(colors.black)
  cor(colors.white)
end

local function rodape(txt)
  fundo(colors.gray)
  term.setCursorPos(1, H)
  term.clearLine()
  cor(colors.white)
  term.write(" " .. txt)
  fundo(colors.black)
end

local function modemsSemFio()
  local lista = {}
  for _, lado in ipairs(rs.getSides()) do
    if peripheral.hasType(lado, "modem") and peripheral.call(lado, "isWireless") then
      table.insert(lista, lado)
    end
  end
  return lista
end

local function lerCfg()
  if not fs.exists(ARQ) then return nil end
  local f = fs.open(ARQ, "r")
  local c = textutils.unserialize(f.readAll())
  f.close()
  if type(c) == "table" and c.x and c.y and c.z then return c end
  return nil
end

local function criarStartup()
  if fs.exists("/startup.lua") then
    local f = fs.open("/startup.lua", "r")
    local conteudo = f.readAll() or ""
    f.close()
    if conteudo:find(MARCA_STARTUP, 1, true) then return end
    cabecalho("TORRE GPS")
    escrever(2, 3, "Ja existe um startup.lua neste computador.", colors.orange)
    escrever(2, 4, "Substituir para a torre ligar sozinha? (S/N)", colors.yellow)
    while true do
      local _, ch = os.pullEvent("char")
      ch = ch:lower()
      if ch == "n" then return end
      if ch == "s" then break end
    end
  end
  local f = fs.open("/startup.lua", "w")
  f.write(MARCA_STARTUP .. "\nshell.run(\"/" .. shell.getRunningProgram() .. "\")\n")
  f.close()
end

local function configurar()
  while true do
    cabecalho("TORRE GPS - SETUP")
    escrever(2, 3, "Coordenada DESTE computador:", colors.yellow)
    escrever(2, 4, "Olhe para ele com F3 e leia 'Targeted Block'.", colors.lightGray)

    local function numero(y, rotulo)
      while true do
        term.setCursorPos(1, y)
        term.clearLine()
        escrever(2, y, rotulo, colors.lightGray)
        term.setCursorPos(2 + #rotulo, y)
        local v = tonumber(read())
        if v and v == math.floor(v) then return v end
      end
    end

    local x = numero(6, "X: ")
    local y = numero(7, "Y: ")
    local z = numero(8, "Z: ")
    escrever(2, 10, ("Confirma %d %d %d ? (S/N)"):format(x, y, z), colors.yellow)
    while true do
      local _, ch = os.pullEvent("char")
      ch = ch:lower()
      if ch == "s" then
        local f = fs.open(ARQ, "w")
        f.write(textutils.serialize({ x = x, y = y, z = z }))
        f.close()
        criarStartup()
        return
      end
      if ch == "n" then break end
    end
  end
end

local function hospedar(c)
  local lados = modemsSemFio()
  if #lados == 0 then
    cabecalho("TORRE GPS")
    escrever(2, 3, "Nenhum modem sem fio encostado no computador!", colors.red)
    escrever(2, 5, "Coloque um Ender Modem em qualquer lado.", colors.lightGray)
    rodape("Esperando um modem...")
    os.pullEvent("peripheral")
    return "recarregar"
  end
  for _, lado in ipairs(lados) do
    peripheral.call(lado, "open", gps.CHANNEL_GPS)
  end

  local atendidos = 0
  local ultimo = "nenhum ainda"

  local function tela()
    cabecalho("TORRE GPS #" .. os.getComputerID())
    escrever(2, 3, "Status", colors.lightGray)
    escrever(16, 3, "ONLINE", colors.lime)
    escrever(2, 4, "Posicao", colors.lightGray)
    escrever(16, 4, ("%d %d %d"):format(c.x, c.y, c.z), colors.yellow)
    escrever(2, 5, "Modems", colors.lightGray)
    escrever(16, 5, table.concat(lados, ", "))
    escrever(2, 7, "Atendidos", colors.lightGray)
    escrever(16, 7, tostring(atendidos))
    escrever(2, 8, "Ultimo", colors.lightGray)
    escrever(16, 8, ultimo)
    escrever(2, 10, "Mantenha este chunk carregado.", colors.lightGray)
    rodape("R = reconfigurar   CTRL+T = parar")
  end

  tela()
  while true do
    local ev, lado, canal, resposta, msg, dist = os.pullEvent()
    if ev == "modem_message" and canal == gps.CHANNEL_GPS and msg == "PING" and dist then
      peripheral.call(lado, "transmit", resposta, gps.CHANNEL_GPS, { c.x, c.y, c.z })
      atendidos = atendidos + 1
      ultimo = ("a %d blocos"):format(math.floor(dist))
      tela()
    elseif ev == "char" and lado:lower() == "r" then
      fs.delete(ARQ)
      return "reconfigurar"
    elseif ev == "peripheral" or ev == "peripheral_detach" then
      return "recarregar"
    end
  end
end

local ok, err = pcall(function()
  while true do
    local c = lerCfg()
    if not c then
      configurar()
    else
      hospedar(c)
    end
  end
end)
fundo(colors.black)
cor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok and err ~= "Terminated" then
  printError(err)
else
  print("Torre de GPS parada. (as outras continuam)")
end
