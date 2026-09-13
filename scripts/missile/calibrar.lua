-- calibrar.lua : ensina ao computador como o bocal corrige o missil
-- rode 'calibrar_gimbal' ANTES deste. Salva em calib.txt

local gimbal = peripheral.find("gimbal_sensor")
local vetor  = peripheral.find("vector_thruster")
  or peripheral.find("liquid_vector_thruster")
  or peripheral.find("creative_vector_thruster")
if not gimbal then error("Gimbal Sensor nao encontrado") end
if not vetor  then error("Vector thruster nao encontrado") end

local LIMIAR = 3   -- inclinacao minima (graus) para aceitar o teste

-- carrega calibracao do gimbal
local calib = {}
if fs.exists("calib.txt") then
  local f = fs.open("calib.txt", "r")
  calib = textutils.unserialize(f.readAll()) or {}
  f.close()
end
if not calib.eixoN then
  print("AVISO: gimbal nao calibrado.")
  print("Rode 'calibrar_gimbal' antes. ENTER p/ seguir assim mesmo.")
  repeat local _, k = os.pullEvent("key") until k == keys.enter
end
calib.offX, calib.offZ = calib.offX or 0, calib.offZ or 0
calib.eixoN, calib.sinalN = calib.eixoN or 1, calib.sinalN or 1
calib.eixoL, calib.sinalL = calib.eixoL or 2, calib.sinalL or 1

local function lerBruto()
  local r = { gimbal.getAngles() }
  if type(r[1]) == "table" then r = r[1] end
  return r[1] or 0, r[2] or 0
end

-- angulos corrigidos: Norte, Leste
local function ler()
  local x, z = lerBruto()
  local a = { x - calib.offX, z - calib.offZ }
  return a[calib.eixoN] * calib.sinalN, a[calib.eixoL] * calib.sinalL
end

local function media(fn, n)
  local sa, sb = 0, 0
  for _ = 1, n do
    local a, b = fn()
    sa, sb = sa + a, sb + b
    sleep(0.05)
  end
  return sa / n, sb / n
end

local function titulo(...)
  term.clear() term.setCursorPos(1, 1)
  print("===== CALIBRACAO DO BOCAL =====")
  for _, linha in ipairs({ ... }) do print(linha) end
  print()
end

local function aoVivo()
  local _, y = term.getCursorPos()
  while true do
    local n, l = ler()
    term.setCursorPos(1, y) term.clearLine()
    term.write(("Norte: %6.1f  Leste: %6.1f  [ENTER]"):format(n, l))
    local timer = os.startTimer(0.1)
    repeat
      local ev, p = os.pullEvent()
      if ev == "key" and p == keys.enter then print() return end
    until ev == "timer" and p == timer
  end
end

vetor.setThrustNormalized(0)
vetor.setVector(0, 0)

-- PASSO 1: zero
titulo("PASSO 1/3",
  "Deixe o missil RETO (em pe)",
  "e parado. Depois aperte ENTER.")
aoVivo()
print("Medindo...")
calib.offX, calib.offZ = media(lerBruto, 20)

-- PASSO 2 e 3: qual angulo cada eixo do bocal corrige
local function testarEixo(passo, nome, vx, vy)
  while true do
    vetor.setVector(vx, vy)
    titulo(("PASSO %d/3 - eixo %s do bocal"):format(passo, nome),
      "O bocal foi inclinado.",
      "Veja para que lado a BOCA",
      "(saida do fogo) aponta.",
      "",
      "Incline o TOPO do missil para",
      "ESSE MESMO lado (5+ graus),",
      "segure e aperte ENTER.")
    aoVivo()
    local n, l = media(ler, 10)
    vetor.setVector(0, 0)

    if math.max(math.abs(n), math.abs(l)) < LIMIAR then
      print("Inclinou pouco. Tente de novo.")
      sleep(2)
    else
      local eixo, d = 1, n
      if math.abs(l) > math.abs(n) then eixo, d = 2, l end
      local sinal = d > 0 and 1 or -1
      print(("OK: bocal %s -> %s%s"):format(nome,
        sinal > 0 and "" or "-", eixo == 1 and "Norte" or "Leste"))
      print("Endireite o missil. ENTER p/ seguir.")
      aoVivo()
      return eixo, sinal
    end
  end
end

local eixoX, sinalX = testarEixo(2, "X", 1, 0)
local eixoY, sinalY = testarEixo(3, "Y", 0, 1)

if eixoX == eixoY then
  titulo("ERRO: os dois eixos do bocal",
    "mexeram o mesmo angulo.",
    "Rode 'calibrar' de novo e incline",
    "bem na direcao da boca do bocal.")
  return
end

calib.eixoX, calib.sinalX = eixoX, sinalX
calib.eixoY, calib.sinalY = eixoY, sinalY
local f = fs.open("calib.txt", "w")
f.write(textutils.serialize(calib))
f.close()

local nomes = { "Norte", "Leste" }
titulo("CALIBRACAO SALVA em calib.txt",
  ("Bocal X -> %s%s"):format(sinalX > 0 and "" or "-", nomes[eixoX]),
  ("Bocal Y -> %s%s"):format(sinalY > 0 and "" or "-", nomes[eixoY]),
  "",
  "Agora o missil esta pronto para voar!")
