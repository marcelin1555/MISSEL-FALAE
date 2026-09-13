-- calibrar_gimbal.lua : corrige o sentido dos angulos do Gimbal Sensor
-- depois de "inclinar para NORTE" o angulo Norte fica positivo,
-- e "inclinar para LESTE" deixa o angulo Leste positivo.
-- salva em calib.txt (rode 'calibrar' depois deste)

local gimbal = peripheral.find("gimbal_sensor")
if not gimbal then error("Gimbal Sensor nao encontrado") end

local LIMIAR = 3   -- inclinacao minima (graus) para aceitar o teste

local function lerBruto()
  local r = { gimbal.getAngles() }
  if type(r[1]) == "table" then r = r[1] end
  return r[1] or 0, r[2] or 0
end

local function media(n)
  local sx, sz = 0, 0
  for _ = 1, n do
    local x, z = lerBruto()
    sx, sz = sx + x, sz + z
    sleep(0.05)
  end
  return sx / n, sz / n
end

local function titulo(...)
  term.clear() term.setCursorPos(1, 1)
  print("===== CALIBRACAO DO GIMBAL =====")
  for _, linha in ipairs({ ... }) do print(linha) end
  print()
end

-- mostra texto ao vivo ate apertar ENTER
local function aoVivo(texto)
  local _, y = term.getCursorPos()
  while true do
    term.setCursorPos(1, y) term.clearLine()
    term.write(texto() .. "  [ENTER]")
    local timer = os.startTimer(0.1)
    repeat
      local ev, p = os.pullEvent()
      if ev == "key" and p == keys.enter then print() return end
    until ev == "timer" and p == timer
  end
end

-- PASSO 1: zero
titulo("PASSO 1/4",
  "Deixe o missil RETO (em pe)",
  "e parado. Depois aperte ENTER.")
aoVivo(function()
  local x, z = lerBruto()
  return ("bruto X: %6.1f  Z: %6.1f"):format(x, z)
end)
print("Medindo...")
local offX, offZ = media(20)

local function bruto()
  local x, z = lerBruto()
  return ("X: %6.1f  Z: %6.1f"):format(x - offX, z - offZ)
end

-- PASSO 2 e 3: direcoes
local function medir(passo, direcao)
  while true do
    titulo(("PASSO %d/4"):format(passo),
      "Aperte F3 e veja 'Facing'.",
      "Incline o TOPO do missil para",
      "o " .. direcao .. " (5+ graus),",
      "segure e aperte ENTER.")
    aoVivo(bruto)
    local x, z = media(10)
    local dx, dz = x - offX, z - offZ
    if math.max(math.abs(dx), math.abs(dz)) < LIMIAR then
      print("Inclinou pouco. Tente de novo.")
      sleep(2)
    else
      local eixo, d = 1, dx
      if math.abs(dz) > math.abs(dx) then eixo, d = 2, dz end
      local sinal = d > 0 and 1 or -1
      print(("%s = angulo %s %s"):format(direcao,
        eixo == 1 and "X" or "Z", sinal > 0 and "(normal)" or "(INVERTIDO)"))
      print("Endireite o missil e aperte ENTER.")
      aoVivo(bruto)
      return eixo, sinal
    end
  end
end

local eixoN, sinalN = medir(2, "NORTE")
local eixoL, sinalL = medir(3, "LESTE")

if eixoN == eixoL then
  titulo("ERRO: Norte e Leste mexeram",
    "o mesmo angulo. Rode de novo e",
    "incline bem na direcao pedida.")
  return
end

-- PASSO 4: conferir
titulo("PASSO 4/4 - CONFERIR",
  "Incline para testar:",
  "  topo p/ NORTE -> Norte positivo",
  "  topo p/ LESTE -> Leste positivo",
  "Tudo certo? Aperte ENTER p/ salvar.",
  "(CTRL+T cancela)")
aoVivo(function()
  local x, z = lerBruto()
  local a = { x - offX, z - offZ }
  return ("Norte: %6.1f  Leste: %6.1f"):format(a[eixoN] * sinalN, a[eixoL] * sinalL)
end)

-- salva junto com o que ja existir
local calib = {}
if fs.exists("calib.txt") then
  local f = fs.open("calib.txt", "r")
  calib = textutils.unserialize(f.readAll()) or {}
  f.close()
end
calib.offX, calib.offZ = offX, offZ
calib.eixoN, calib.sinalN = eixoN, sinalN
calib.eixoL, calib.sinalL = eixoL, sinalL
-- os angulos mudaram, entao a calibracao do bocal precisa ser refeita
calib.eixoX, calib.sinalX, calib.eixoY, calib.sinalY = nil, nil, nil, nil

local f = fs.open("calib.txt", "w")
f.write(textutils.serialize(calib))
f.close()

titulo("GIMBAL SALVO em calib.txt",
  ("Norte = angulo %s (%d)"):format(eixoN == 1 and "X" or "Z", sinalN),
  ("Leste = angulo %s (%d)"):format(eixoL == 1 and "X" or "Z", sinalL),
  "",
  "Agora calibre o bocal: calibrar")
