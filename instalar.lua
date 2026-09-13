-- instalar.lua : BlockForge Militar - Instalador
-- uso: instalar            (menu)
--      instalar missil | base | gps_torre

local PROGRAMAS = {}

PROGRAMAS[#PROGRAMAS + 1] = { chave = "missil", arquivo = "missil.lua", titulo = "Missil (computador do missil)", codigo = [=[
-- missil.lua : BlockForge Militar - Missil Guiado
-- Create Aeronautics + Create Propulsion: Simulated + CC: Tweaked
-- uso: missil          (menu)
--      missil remoto   (aguarda ordens da base)
--      missil teste    (teste de estabilizacao)

local VERSAO = "3.1"
local ARQ_CONFIG = "/bfm_config.txt"
local PASTA_PRESETS = "bfm_presets"
local PROTOCOLO = "bfm"
local SERVICO = "bfm_missil"
local LIMIAR = 3 -- inclinacao minima (graus) aceita nas calibracoes
local atan2 = math.atan2 or math.atan

---------------------------------------------------------------- TELA

local W, H = term.getSize()
local COR = term.isColor()

local function cor(c) if COR then term.setTextColor(c) end end
local function fundo(c) if COR then term.setBackgroundColor(c) end end

local function escrever(x, y, txt, c, bg)
  term.setCursorPos(x, y)
  if bg then fundo(bg) end
  cor(c or colors.white)
  term.write(txt)
  fundo(colors.black)
  cor(colors.white)
end

local function limparLinha(y)
  fundo(colors.black)
  term.setCursorPos(1, y)
  term.clearLine()
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

local function quebrar(texto, largura)
  local linhas = {}
  texto = tostring(texto)
  while #texto > largura do
    table.insert(linhas, texto:sub(1, largura))
    texto = texto:sub(largura + 1)
  end
  table.insert(linhas, texto)
  return linhas
end

local function desenharAviso(titulo, linhas, c)
  cabecalho(titulo)
  local y = 3
  for _, l in ipairs(linhas) do
    for _, parte in ipairs(quebrar(l, W - 2)) do
      if y < H then escrever(2, y, parte, c) end
      y = y + 1
    end
  end
end

local function aviso(titulo, linhas, c)
  desenharAviso(titulo, linhas, c)
  rodape("Aperte qualquer tecla")
  os.pullEvent("key")
end

local function avisoTempo(titulo, linhas, c, segundos)
  desenharAviso(titulo, linhas, c)
  rodape(("Continua em %ds (ou aperte uma tecla)"):format(segundos))
  local timer = os.startTimer(segundos)
  while true do
    local ev, p = os.pullEvent()
    if ev == "key" or (ev == "timer" and p == timer) then return end
  end
end

local function confirmar(titulo, pergunta)
  cabecalho(titulo)
  for i, parte in ipairs(quebrar(pergunta, W - 2)) do
    escrever(2, 2 + i, parte, colors.yellow)
  end
  rodape("S = sim   N = nao")
  while true do
    local _, ch = os.pullEvent("char")
    ch = ch:lower()
    if ch == "s" then return true end
    if ch == "n" then return false end
  end
end

local function perguntar(y, rotulo, padrao, oculto)
  escrever(2, y, rotulo, colors.lightGray)
  term.setCursorPos(2 + #rotulo, y)
  cor(colors.white)
  return read(oculto and "*" or nil, nil, nil, padrao ~= nil and tostring(padrao) or nil)
end

-- menu com setas; retorna o indice escolhido ou nil (BACKSPACE)
local function menu(titulo, opcoes, info)
  local sel = 1
  while true do
    cabecalho(titulo)
    local y = 3
    if info then
      for _, l in ipairs(info) do
        escrever(2, y, l[1], l[2])
        y = y + 1
      end
      y = y + 1
    end
    local visiveis = math.max(1, H - y)
    local topo = 1
    if sel > visiveis then topo = sel - visiveis + 1 end
    for i = topo, math.min(#opcoes, topo + visiveis - 1) do
      local txt = ("%s%s %s"):format(i == sel and ">" or " ",
        i <= 9 and tostring(i) or " ", opcoes[i])
      if #txt > W - 2 then txt = txt:sub(1, W - 2) end
      if i == sel then
        escrever(2, y, txt .. string.rep(" ", W - 2 - #txt), colors.black, colors.yellow)
      else
        escrever(2, y, txt)
      end
      y = y + 1
    end
    rodape("SETAS/NUMERO escolhe  ENTER ok  BACKSPACE volta")
    local ev, p = os.pullEvent()
    if ev == "key" then
      if p == keys.up then
        sel = sel > 1 and sel - 1 or #opcoes
      elseif p == keys.down then
        sel = sel < #opcoes and sel + 1 or 1
      elseif p == keys.enter then
        return sel
      elseif p == keys.backspace then
        return nil
      end
    elseif ev == "char" then
      local n = tonumber(p)
      if n and n >= 1 and n <= #opcoes then return n end
    end
  end
end

-- atualiza a linha y com fn() ate ENTER (true) ou BACKSPACE (false)
local function aoVivo(y, fn)
  local timer = os.startTimer(0)
  while true do
    local ev, p = os.pullEvent()
    if ev == "timer" and p == timer then
      local txt, c = fn()
      limparLinha(y)
      escrever(2, y, txt, c)
      timer = os.startTimer(0.1)
    elseif ev == "key" and p == keys.enter then
      return true
    elseif ev == "key" and p == keys.backspace then
      return false
    end
  end
end

---------------------------------------------------------------- MATEMATICA

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function lim1(v) return clamp(v, -1, 1) end
local function mag(a, b) return math.sqrt(a * a + b * b) end

local function limitarMag(a, b, max)
  local m = mag(a, b)
  if m > max and m > 0 then return a * max / m, b * max / m end
  return a, b
end

-- gira um vetor (norte, leste) pelo angulo em radianos
local function rotacionar(n, l, ang)
  local c, s = math.cos(ang), math.sin(ang)
  return n * c - l * s, n * s + l * c
end

-- vetor horizontal (norte, leste) de 'de' ate 'para'. Norte = -Z, Leste = +X
local function horiz(de, para)
  return -(para.z - de.z), para.x - de.x
end

---------------------------------------------------------------- CONFIG

local LADOS = { "top", "bottom", "front", "back", "left", "right", "todos" }

-- lado de cada vector thruster no missil -> vetor unitario {norte, leste}
local LADO_VETOR = { N = { 1, 0 }, S = { -1, 0 }, L = { 0, 1 }, O = { 0, -1 }, C = { 0, 0 } }
local GIRO_MAX = 0.5 -- parte maxima do bocal usada para frear o giro
local TESTE_PULSO = 0.3 -- toque de giro usado no teste do sentido do freio

local PADRAO = {
  nome = "sem_nome",
  -- gimbal
  offX = 0, offZ = 0,
  eixoN = 1, sinalN = 1, eixoL = 2, sinalL = 1,
  gimbalOk = false,
  -- bocal
  eixoX = 2, sinalX = 1, eixoY = 1, sinalY = 1,
  bocalOk = false,
  posMotores = {}, -- lado de cada vector thruster (N/S/L/O/C)
  -- voo
  kp = 0.04, kd = 0.015, inverter = false,
  controleGiro = true, kGiro = 0.15, inverterGiro = false,
  empuxoVetor = 1.0, acelerador = 1.0, usarSolidos = true,
  abortar = 60, contagem = 3,
  -- navegacao
  altCruzeiro = 40, altSaida = 15,
  velMax = 20, velSubida = 15, velDescida = 12,
  inclMax = 20, distAtaque = 12,
  kPos = 0.25, kVel = 1.5, kAlt = 0.5, kVz = 0.08, kiVz = 0.05, acelBase = 0.6,
  corrigirGiro = true, alcanceMax = 2000,
  -- ogiva e seguranca
  ladoOgiva = "top", raioDetonacao = 4, tempoArme = 5, distArme = 30,
  tempoMax = 180, impacto = true,
  -- sistema
  codigo = "", iniciarRemoto = false,
  alvoX = 0, alvoY = 64, alvoZ = 0,
}

-- ajustes que aparecem com %d: precisam ser inteiros
local INTEIROS = {
  abortar = true, contagem = true, altCruzeiro = true, altSaida = true,
  distAtaque = true, alcanceMax = true, raioDetonacao = true,
  tempoArme = true, distArme = true, tempoMax = true,
}

local cfg = {}

local function copiar(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function lerTabela(caminho)
  if not fs.exists(caminho) then return nil end
  local f = fs.open(caminho, "r")
  local dados = textutils.unserialize(f.readAll())
  f.close()
  if type(dados) ~= "table" then return nil end
  return dados
end

local function gravarTabela(caminho, t)
  local pasta = fs.getDir(caminho)
  if pasta ~= "" and not fs.exists(pasta) then fs.makeDir(pasta) end
  local f = fs.open(caminho, "w")
  f.write(textutils.serialize(t))
  f.close()
end

local function aplicar(dados)
  for k, v in pairs(dados) do
    if PADRAO[k] ~= nil and type(v) == type(PADRAO[k]) then
      if INTEIROS[k] then v = math.floor(v + 0.5) end
      cfg[k] = v
    end
  end
end

local function carregarConfig()
  cfg = copiar(PADRAO)
  local dados = lerTabela(ARQ_CONFIG)
  if dados then
    aplicar(dados)
  else
    -- importa a calibracao dos scripts antigos (calib.txt)
    local antigo = lerTabela("/calib.txt")
    if antigo then
      aplicar(antigo)
      cfg.gimbalOk = antigo.eixoN ~= nil
      cfg.bocalOk = antigo.eixoX ~= nil
    end
  end
end

local function salvarConfig()
  gravarTabela(ARQ_CONFIG, cfg)
end

---------------------------------------------------------------- PERIFERICOS

local TIPOS_VETOR = { "vector_thruster", "liquid_vector_thruster", "creative_vector_thruster" }
local TIPOS_MOTOR = {
  { tipo = "solid_fuel_thruster", classe = "solido",   rotulo = "SOL" },
  { tipo = "thruster",            classe = "liquido",  rotulo = "LIQ" },
  { tipo = "ion_thruster",        classe = "ion",      rotulo = "ION" },
  { tipo = "creative_thruster",   classe = "criativo", rotulo = "CRI" },
}

local P = { vetores = {}, motores = {} }

local function temTipo(nome, lista)
  for _, t in ipairs(lista) do
    if peripheral.hasType(nome, t) then return true end
  end
  return false
end

local function detectar()
  P = { gimbal = nil, drive = nil, modem = nil, vetores = {}, motores = {} }
  -- o GPS so usa modem sem fio encostado direto no computador
  for _, lado in ipairs(rs.getSides()) do
    if peripheral.hasType(lado, "modem") and peripheral.call(lado, "isWireless") then
      P.modem = lado
      break
    end
  end
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.hasType(nome, "gimbal_sensor") then
      P.gimbal = P.gimbal or peripheral.wrap(nome)
    elseif temTipo(nome, TIPOS_VETOR) then
      table.insert(P.vetores, { nome = nome, p = peripheral.wrap(nome) })
    elseif peripheral.hasType(nome, "drive") then
      P.drive = P.drive or peripheral.wrap(nome)
    else
      for _, t in ipairs(TIPOS_MOTOR) do
        if peripheral.hasType(nome, t.tipo) then
          table.insert(P.motores, { nome = nome, p = peripheral.wrap(nome),
            classe = t.classe, rotulo = t.rotulo })
          break
        end
      end
    end
  end
end

local function contar(classe)
  local n = 0
  for _, m in ipairs(P.motores) do
    if m.classe == classe then n = n + 1 end
  end
  return n
end

-- chama um metodo sem quebrar se ele nao existir
local function chamar(p, metodo, ...)
  if type(p[metodo]) ~= "function" then return nil end
  local ok, r = pcall(p[metodo], ...)
  if ok then return r end
  return nil
end

local function acelerar(m, pot)
  pcall(m.p.setPowerNormalized, pot)
end

-- x, y: inclinacao igual para todos os bocais
-- giro: forca tangencial para frear a rotacao (cada motor inclina de lado)
local function vetorComando(x, y, giro)
  local inv = cfg.inverter and -1 or 1
  for _, v in ipairs(P.vetores) do
    local vx, vy = x, y
    local r = giro and giro ~= 0 and LADO_VETOR[cfg.posMotores[v.nome] or "C"]
    if r then
      -- forca lateral {norte, leste} neste motor que gira o missil contra a rotacao
      local f = { giro * r[2], -giro * r[1] }
      vx = lim1(vx - inv * cfg.sinalX * f[cfg.eixoX])
      vy = lim1(vy - inv * cfg.sinalY * f[cfg.eixoY])
    end
    pcall(v.p.setVector, vx, vy)
  end
end

-- quantos vector thrusters tem lado definido (fora do centro)
local function motoresMapeados()
  local n = 0
  for _, v in ipairs(P.vetores) do
    local lado = cfg.posMotores[v.nome]
    if lado and lado ~= "C" then n = n + 1 end
  end
  return n
end

local function vetorEmpuxo(pot)
  for _, v in ipairs(P.vetores) do
    if not pcall(v.p.setThrustNormalized, pot) then
      pcall(v.p.setPowerNormalized, pot)
    end
  end
end

local function desligarTudo()
  for _, m in ipairs(P.motores) do acelerar(m, 0) end
  vetorComando(0, 0)
  vetorEmpuxo(0)
end

-- texto do combustivel e se ainda tem
local function combustivel(m)
  local p = m.p
  if m.classe == "solido" then
    local q = chamar(p, "getFuelAmount") or 0
    local queimando = chamar(p, "isBurning") == true
    if queimando then
      local s = math.floor((chamar(p, "getBurnTimeRemaining") or 0) / 20)
      return ("queimando %ds"):format(s), true
    end
    return q > 0 and "carregado" or "VAZIO", q > 0
  elseif m.classe == "liquido" then
    local a = math.floor(chamar(p, "getFuelAmountMb") or 0)
    local c = math.floor(chamar(p, "getFuelCapacityMb") or 0)
    return ("%d/%d mB"):format(a, c), a > 0
  elseif m.classe == "ion" then
    local a = math.floor(chamar(p, "getEnergyAmountFe") or 0)
    return ("%d FE"):format(a), a > 0
  end
  return "infinito", true
end

local function empuxoKN(m)
  return chamar(m.p, "getCurrentThrustKN") or 0
end

local function ogiva(ligar)
  if cfg.ladoOgiva == "todos" then
    for _, lado in ipairs(rs.getSides()) do redstone.setOutput(lado, ligar) end
  else
    redstone.setOutput(cfg.ladoOgiva, ligar)
  end
end

---------------------------------------------------------------- REDE E GPS

local ultimaPos = nil

local function nomeRede()
  return (os.getComputerLabel() or "missil") .. "#" .. os.getComputerID()
end

local function abrirRede()
  if not P.modem then return false end
  if not rednet.isOpen(P.modem) then rednet.open(P.modem) end
  return true
end

-- CC: Sable (Create Aeronautics): a fisica do jogo informa posicao e giro
-- direto, sem GPS. So funciona com o computador montado na contraption.
local function sublevelPose()
  if type(sublevel) ~= "table" or type(sublevel.getLogicalPose) ~= "function" then return nil end
  local ok, pose = pcall(sublevel.getLogicalPose)
  if not ok or type(pose) ~= "table" or type(pose.position) ~= "table" then return nil end
  local p = pose.position
  if type(p.x) ~= "number" or type(p.y) ~= "number" or type(p.z) ~= "number" then return nil end
  return { x = p.x, y = p.y, z = p.z }
end

-- rotacao em torno do eixo vertical (rad/s; positivo = anti-horario visto de cima)
local function giroVertical()
  if type(sublevel) ~= "table" or type(sublevel.getAngularVelocity) ~= "function" then return nil end
  local ok, w = pcall(sublevel.getAngularVelocity)
  if ok and type(w) == "table" and type(w.y) == "number" then return w.y end
  return nil
end

local fontePos = "nenhuma"

-- posicao do missil: sublevel se estiver montado, senao GPS
local function posicao(timeout)
  local p = sublevelPose()
  if p then
    fontePos = "sublevel"
  elseif P.modem then
    local x, y, z = gps.locate(timeout or 0.5)
    if not x then return nil end
    p = { x = x, y = y, z = z }
    fontePos = "GPS"
  else
    return nil
  end
  ultimaPos = p
  return p
end

local function statusMissil()
  detectar()
  local problemas = {}
  if not P.gimbal then table.insert(problemas, "sem Gimbal Sensor") end
  if #P.vetores == 0 then table.insert(problemas, "sem Vector Thruster") end
  if not P.modem then table.insert(problemas, "sem modem sem fio direto") end
  if not cfg.gimbalOk then table.insert(problemas, "gimbal nao calibrado") end
  if not cfg.bocalOk then table.insert(problemas, "bocal nao calibrado") end
  return {
    tipo = "status", nome = nomeRede(), versao = VERSAO,
    pronto = #problemas == 0, problemas = problemas,
    pos = ultimaPos, precisaCodigo = cfg.codigo ~= "", preset = cfg.nome,
    vet = #P.vetores, liq = contar("liquido"), sol = contar("solido"),
  }
end

---------------------------------------------------------------- SENSOR

local function lerBruto()
  local r = { P.gimbal.getAngles() }
  if type(r[1]) == "table" then r = r[1] end
  return r[1] or 0, r[2] or 0
end

-- angulos corrigidos pela calibracao: Norte, Leste
local function lerAngulos()
  local x, z = lerBruto()
  local a = { x - cfg.offX, z - cfg.offZ }
  return a[cfg.eixoN] * cfg.sinalN, a[cfg.eixoL] * cfg.sinalL
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

local function exigir(precisaVetor)
  detectar()
  if not P.gimbal then
    aviso("ERRO", { "Gimbal Sensor nao encontrado.",
      "Conecte ao computador (ou via Wired Modem)." }, colors.red)
    return false
  end
  if precisaVetor and #P.vetores == 0 then
    aviso("ERRO", { "Vector thruster nao encontrado." }, colors.red)
    return false
  end
  return true
end

local function dirEixo(eixo, sinal)
  return (sinal > 0 and "" or "-") .. (eixo == 1 and "X" or "Z")
end

---------------------------------------------------------------- CALIBRAR GIMBAL

local function calibrarGimbal()
  if not exigir(false) then return end

  cabecalho("GIMBAL 1/4")
  escrever(2, 3, "Deixe o missil RETO e parado.", colors.yellow)
  escrever(2, 4, "A contraption precisa estar montada.", colors.lightGray)
  rodape("ENTER confirma   BACKSPACE cancela")
  local ok = aoVivo(6, function()
    local x, z = lerBruto()
    return ("Sensor   X %6.1f   Z %6.1f"):format(x, z)
  end)
  if not ok then return end
  escrever(2, 8, "Medindo...", colors.yellow)
  local offX, offZ = media(lerBruto, 20)

  local function relativo()
    local x, z = lerBruto()
    return x - offX, z - offZ
  end

  local function medir(passo, direcao)
    while true do
      cabecalho("GIMBAL " .. passo .. "/4")
      escrever(2, 3, "Incline o TOPO do missil para o " .. direcao, colors.yellow)
      escrever(2, 4, "(F3 > Facing mostra a direcao)", colors.lightGray)
      escrever(2, 5, "Segure inclinado e aperte ENTER.")
      rodape("ENTER confirma   BACKSPACE cancela")
      if not aoVivo(7, function()
        local dx, dz = relativo()
        local inc = math.max(math.abs(dx), math.abs(dz))
        return ("X %6.1f   Z %6.1f   inclinacao %4.1f"):format(dx, dz, inc),
          inc >= LIMIAR and colors.lime or colors.red
      end) then return nil end

      local dx, dz = media(relativo, 10)
      if math.max(math.abs(dx), math.abs(dz)) < LIMIAR then
        escrever(2, 9, ("Inclinou pouco! Precisa de %d+ graus."):format(LIMIAR), colors.red)
        sleep(2)
      else
        local eixo, d = 1, dx
        if math.abs(dz) > math.abs(dx) then eixo, d = 2, dz end
        local sinal = d > 0 and 1 or -1
        escrever(2, 9, ("%s = angulo %s %s"):format(direcao, eixo == 1 and "X" or "Z",
          sinal > 0 and "(normal)" or "(invertido)"), colors.lime)
        escrever(2, 10, "Endireite o missil e aperte ENTER.")
        if not aoVivo(12, function()
          local x2, z2 = relativo()
          return ("X %6.1f   Z %6.1f"):format(x2, z2)
        end) then return nil end
        return eixo, sinal
      end
    end
  end

  local eixoN, sinalN = medir(2, "NORTE")
  if not eixoN then return end
  local eixoL, sinalL = medir(3, "LESTE")
  if not eixoL then return end

  if eixoN == eixoL then
    aviso("GIMBAL", { "Norte e Leste mexeram o mesmo angulo.",
      "Refaca e incline bem na direcao pedida." }, colors.red)
    return
  end

  cabecalho("GIMBAL 4/4")
  escrever(2, 3, "Confira inclinando o missil:", colors.yellow)
  escrever(2, 4, "  topo p/ NORTE -> Norte positivo")
  escrever(2, 5, "  topo p/ LESTE -> Leste positivo")
  rodape("ENTER salva   BACKSPACE cancela")
  if not aoVivo(7, function()
    local dx, dz = relativo()
    local a = { dx, dz }
    return ("Norte %6.1f   Leste %6.1f"):format(a[eixoN] * sinalN, a[eixoL] * sinalL)
  end) then return end

  cfg.offX, cfg.offZ = offX, offZ
  cfg.eixoN, cfg.sinalN, cfg.eixoL, cfg.sinalL = eixoN, sinalN, eixoL, sinalL
  cfg.gimbalOk = true
  cfg.bocalOk = false -- os angulos mudaram: bocal precisa ser refeito
  salvarConfig()

  aviso("GIMBAL SALVO", {
    ("Norte = angulo %s"):format(dirEixo(eixoN, sinalN)),
    ("Leste = angulo %s"):format(dirEixo(eixoL, sinalL)),
    "",
    "Proximo passo: Calibrar bocal.",
  }, colors.lime)
end

---------------------------------------------------------------- CALIBRAR BOCAL

local function calibrarBocal()
  if not exigir(true) then return end
  if not cfg.gimbalOk and not confirmar("BOCAL", "Gimbal nao calibrado. Continuar?") then
    return
  end

  local antigo = copiar(cfg)
  vetorEmpuxo(0)
  vetorComando(0, 0)

  local function mostrar()
    local n, l = lerAngulos()
    local inc = math.max(math.abs(n), math.abs(l))
    return ("Norte %6.1f   Leste %6.1f   incl. %4.1f"):format(n, l, inc),
      inc >= LIMIAR and colors.lime or colors.white
  end

  cabecalho("BOCAL 1/3")
  escrever(2, 3, "Deixe o missil RETO e parado.", colors.yellow)
  escrever(2, 4, "Sem combustivel nos motores!", colors.orange)
  rodape("ENTER confirma   BACKSPACE cancela")
  if not aoVivo(6, mostrar) then return end
  escrever(2, 8, "Medindo...", colors.yellow)
  cfg.offX, cfg.offZ = media(lerBruto, 20)

  local function testar(passo, nome, vx, vy)
    while true do
      vetorComando(vx, vy)
      cabecalho(("BOCAL %d/3 - eixo %s"):format(passo, nome))
      escrever(2, 3, "O bocal foi inclinado. Veja para que lado", colors.yellow)
      escrever(2, 4, "a BOCA (saida do fogo) aponta.", colors.yellow)
      escrever(2, 6, "Incline o TOPO do missil para ESSE lado,")
      escrever(2, 7, "segure e aperte ENTER.")
      rodape("ENTER confirma   BACKSPACE cancela")
      if not aoVivo(9, mostrar) then return nil end

      local n, l = media(lerAngulos, 10)
      vetorComando(0, 0)
      if math.max(math.abs(n), math.abs(l)) < LIMIAR then
        escrever(2, 11, ("Inclinou pouco! Precisa de %d+ graus."):format(LIMIAR), colors.red)
        sleep(2)
      else
        local eixo, d = 1, n
        if math.abs(l) > math.abs(n) then eixo, d = 2, l end
        local sinal = d > 0 and 1 or -1
        escrever(2, 11, ("Bocal %s -> %s%s"):format(nome, sinal > 0 and "" or "-",
          eixo == 1 and "Norte" or "Leste"), colors.lime)
        escrever(2, 12, "Endireite o missil e aperte ENTER.")
        if not aoVivo(14, mostrar) then return nil end
        return eixo, sinal
      end
    end
  end

  local eixoX, sinalX = testar(2, "X", 1, 0)
  if not eixoX then cfg = antigo return end
  local eixoY, sinalY = testar(3, "Y", 0, 1)
  if not eixoY then cfg = antigo return end

  if eixoX == eixoY then
    cfg = antigo
    aviso("BOCAL", { "Os dois eixos do bocal mexeram o mesmo angulo.",
      "Refaca inclinando bem para o lado da boca." }, colors.red)
    return
  end

  cfg.eixoX, cfg.sinalX, cfg.eixoY, cfg.sinalY = eixoX, sinalX, eixoY, sinalY
  cfg.bocalOk = true
  salvarConfig()

  local nomes = { "Norte", "Leste" }
  aviso("BOCAL SALVO", {
    ("Bocal X -> %s%s"):format(sinalX > 0 and "" or "-", nomes[eixoX]),
    ("Bocal Y -> %s%s"):format(sinalY > 0 and "" or "-", nomes[eixoY]),
    "",
    "Pronto para voar. Dica: salve um preset!",
  }, colors.lime)
end

---------------------------------------------------------------- CALIBRAR GIRO

local function calibrarMotores()
  if not exigir(true) then return end
  if not cfg.bocalOk then
    aviso("GIRO", { "Calibre o bocal antes." }, colors.orange)
    return
  end
  vetorEmpuxo(0)
  vetorComando(0, 0)

  local novo = {}
  for i, v in ipairs(P.vetores) do
    cabecalho(("GIRO %d/%d"):format(i, #P.vetores))
    escrever(2, 3, "Um bocal esta balancando sozinho.", colors.yellow)
    escrever(2, 4, "Em que lado do missil fica ESSE motor?", colors.yellow)
    escrever(2, 6, "N Norte   S Sul   L Leste   O Oeste")
    escrever(2, 7, "C = no centro (eixo do missil)")
    escrever(2, 9, "Missil na mesma posicao da calibracao!", colors.lightGray)
    escrever(2, 10, "Motor: " .. v.nome, colors.lightGray)
    rodape("N/S/L/O/C escolhe   BACKSPACE cancela")

    local escolha
    parallel.waitForAny(function()
      local lado = 1
      while true do
        pcall(v.p.setVector, lado, 0)
        lado = -lado
        sleep(0.5)
      end
    end, function()
      while true do
        local ev, p = os.pullEvent()
        if ev == "char" and LADO_VETOR[p:upper()] then
          escolha = p:upper()
          return
        elseif ev == "key" and p == keys.backspace then
          return
        end
      end
    end)
    pcall(v.p.setVector, 0, 0)
    if not escolha then return end
    novo[v.nome] = escolha
  end

  cfg.posMotores = novo
  salvarConfig()
  local linhas = {}
  for _, v in ipairs(P.vetores) do
    table.insert(linhas, ("%-26s %s"):format(v.nome, novo[v.nome]))
  end
  table.insert(linhas, "")
  table.insert(linhas, "O freio de giro usa a API sublevel (CC: Sable).")
  aviso("GIRO SALVO", linhas, colors.lime)
end

---------------------------------------------------------------- VOO

local function desenharHorizonte(n, l, an, al)
  -- caixa de 13x7 com o centro em (8, 6); 30 graus = borda
  escrever(8, 2, "N", colors.lightGray)
  escrever(2, 3, "+-----------+", colors.gray)
  for yy = 4, 8 do
    escrever(2, yy, "|           |", colors.gray)
  end
  escrever(2, 9, "+-----------+", colors.gray)
  escrever(8, 10, "S", colors.lightGray)
  escrever(1, 6, "O", colors.lightGray)
  escrever(15, 6, "L", colors.lightGray)
  escrever(8, 6, "+", colors.gray)

  local function ponto(nn, ll)
    local px = 8 + math.floor(ll / 30 * 5 + 0.5)
    local py = 6 - math.floor(nn / 30 * 2 + 0.5)
    return clamp(px, 3, 13), clamp(py, 4, 8)
  end
  if an and (math.abs(an) > 0.5 or math.abs(al) > 0.5) then
    local x, y = ponto(an, al)
    escrever(x, y, "x", colors.cyan)
  end
  local inc = math.max(math.abs(n), math.abs(l))
  local c = colors.lime
  if inc > 25 then c = colors.red elseif inc > 10 then c = colors.yellow end
  local x, y = ponto(n, l)
  escrever(x, y, "@", c)
end

-- opts.alvo = {x,y,z} para voo guiado (nil = so estabilizar)
-- opts.base = id da base que mandou lancar (nil = lancamento local)
local function voar(opts)
  opts = opts or {}
  local alvo, base = opts.alvo, opts.base
  local guiado = alvo ~= nil

  local S = {
    fase = guiado and "DECOLAGEM" or "ESTABILIZAR",
    motivo = "Fim", detonou = false, armado = false,
    n = 0, l = 0, giro = 0, cx = 0, cy = 0, hz = 0,
    alvoN = 0, alvoL = 0, psi = 0, incMax = 0, wy = 0, mapeados = 0,
    acel = cfg.acelerador, integral = cfg.acelBase,
    vel = { n = 0, l = 0, y = 0 }, eventos = {},
  }

  local function evento(txt)
    table.insert(S.eventos, 1, txt)
    if #S.eventos > 3 then table.remove(S.eventos) end
    if base then rednet.send(base, { tipo = "evento", texto = txt }, PROTOCOLO) end
  end

  local function falha(txt)
    if base then
      rednet.send(base, { tipo = "evento", texto = txt, fim = true }, PROTOCOLO)
      avisoTempo("LANCAMENTO NEGADO", { txt }, colors.red, 5)
    else
      aviso("LANCAMENTO", { txt }, colors.red)
    end
  end

  detectar()
  if not P.gimbal then falha("Gimbal Sensor nao encontrado") return end
  if #P.vetores == 0 then falha("Vector thruster nao encontrado") return end
  S.mapeados = motoresMapeados()
  -- teste automatico do sentido do freio de giro (so no teste de estabilizacao)
  if not guiado and cfg.controleGiro and S.mapeados >= 2 and giroVertical() then
    S.tg = {}
  end

  if guiado then
    local o = posicao(2)
    if not o then
      falha(P.modem and "Sem posicao: sem sublevel e GPS sem sinal (torres na mesma altura?)"
        or "Sem posicao: sem sublevel e sem modem sem fio para o GPS")
      return
    end
    local dH = mag(horiz(o, alvo))
    if dH > cfg.alcanceMax then
      falha(("Alvo a %d blocos (alcance max %d). Se o missil esta perto, o GPS esta dando posicao errada dentro da contraption.")
        :format(math.floor(dH), cfg.alcanceMax))
      return
    end
    S.origem, S.pos = o, o
    S.cruzeiroY = math.max(o.y, alvo.y) + cfg.altCruzeiro
    S.distH = dH
    S.dist = math.sqrt(dH * dH + (alvo.y - o.y) ^ 2)
  end

  local ativos = {}
  for _, m in ipairs(P.motores) do
    if m.classe ~= "solido" or cfg.usarSolidos then table.insert(ativos, m) end
  end

  -- checklist (so no lancamento local; a base ja confirmou)
  if not base then
    cabecalho(guiado and "LANCAMENTO GUIADO" or "TESTE DE VOO")
    local function item(y, rotulo, valor, bom)
      escrever(2, y, rotulo, colors.lightGray)
      escrever(24, y, valor, bom and colors.lime or colors.orange)
    end
    item(3, "Preset", cfg.nome, true)
    item(4, "Calibracao", (cfg.gimbalOk and cfg.bocalOk) and "OK" or "PENDENTE",
      cfg.gimbalOk and cfg.bocalOk)
    item(5, "Vetor / Liq / Sol", ("%d / %d / %d%s"):format(#P.vetores, contar("liquido"),
      contar("solido"), cfg.usarSolidos and "" or " (off)"), true)
    item(6, "Empuxo vetor / acel.", ("%d%% / %d%%"):format(
      math.floor(cfg.empuxoVetor * 100 + 0.5), math.floor(cfg.acelerador * 100 + 0.5)), true)
    if guiado then
      item(8, "Alvo", ("%d %d %d"):format(math.floor(alvo.x), math.floor(alvo.y),
        math.floor(alvo.z)), true)
      item(9, "Distancia", ("%d blocos"):format(math.floor(S.dist)), true)
      item(10, "Altura de cruzeiro", ("Y %d"):format(math.floor(S.cruzeiroY)), true)
      item(11, "Ogiva", ("lado %s, raio %d"):format(cfg.ladoOgiva, cfg.raioDetonacao), true)
      item(12, "Arma apos", ("%ds e %d blocos"):format(cfg.tempoArme, cfg.distArme), true)
    end
    local giroTxt, giroBom
    if not cfg.controleGiro then
      giroTxt, giroBom = "desligado", false
    elseif not giroVertical() then
      giroTxt, giroBom = "sem sublevel", false
    else
      giroTxt = ("%d/%d motores"):format(S.mapeados, #P.vetores)
      giroBom = S.mapeados >= 2
    end
    item(13, "Freio de giro", giroTxt, giroBom)
    if #ativos == 0 then
      escrever(2, 14, "Nenhum motor principal: so o vetor empurra.", colors.orange)
    end
    if contar("solido") > 0 and cfg.usarSolidos then
      escrever(2, 15, "Solidos NAO apagam depois de acesos!", colors.orange)
    end
    rodape("ENTER lancar   BACKSPACE cancelar")
    while true do
      local _, k = os.pullEvent("key")
      if k == keys.enter then break end
      if k == keys.backspace then return end
    end
  end

  -- contagem regressiva (cancela por tecla ou pela base)
  ogiva(false)
  for i = cfg.contagem, 1, -1 do
    cabecalho("CONTAGEM")
    local txt = ("T-%d"):format(i)
    escrever(math.floor((W - #txt) / 2) + 1, math.floor(H / 2), txt, colors.yellow)
    rodape("BACKSPACE cancela")
    evento(txt)
    local timer = os.startTimer(1)
    while true do
      local ev, a, b, c = os.pullEvent()
      if ev == "timer" and a == timer then break end
      if (ev == "key" and a == keys.backspace)
        or (ev == "rednet_message" and c == PROTOCOLO and type(b) == "table" and b.tipo == "abortar") then
        if base then
          rednet.send(base, { tipo = "evento", texto = "Lancamento cancelado", fim = true }, PROTOCOLO)
          avisoTempo("LANCAMENTO", { "Lancamento cancelado." }, colors.orange, 3)
        else
          aviso("LANCAMENTO", { "Lancamento cancelado." }, colors.orange)
        end
        return
      end
    end
  end

  -- ignicao
  for _, m in ipairs(P.motores) do
    if m.classe == "solido" then
      acelerar(m, cfg.usarSolidos and 1 or 0)
    else
      acelerar(m, cfg.acelerador)
    end
  end
  vetorEmpuxo(cfg.empuxoVetor)
  S.inicio = os.clock()
  evento("IGNICAO")

  local function detonar(txt)
    S.detonou = true
    S.motivo = "DETONACAO: " .. txt
    ogiva(true)
    evento(S.motivo)
  end

  -- As chamadas a perifericos descartam eventos enquanto esperam o jogo,
  -- entao o voo roda em tarefas paralelas, cada uma com seu proprio sleep.

  -- TAREFA: estabilizacao PD (gimbal + vetor, o mais rapido possivel)
  local function controle()
    local n0, l0 = lerAngulos()
    local t0 = os.clock()
    local ultX, ultY, ultG
    local ciclos, tHz = 0, t0
    while true do
      sleep(0.05)
      local n, l = lerAngulos()
      local wy = giroVertical()
      local t = os.clock()
      local dt = math.max(t - t0, 0.05)
      local rn, rl = (n - n0) / dt, (l - l0) / dt
      n0, l0, t0 = n, l, t

      local inc = math.max(math.abs(n), math.abs(l))
      S.incMax = math.max(S.incMax, inc)
      if inc > cfg.abortar then
        S.motivo = ("ABORTADO: inclinacao de %.0f graus"):format(inc)
        return
      end

      -- erro = inclinacao atual - inclinacao pedida pela navegacao
      local ang, giro = { n - S.alvoN, l - S.alvoL }, { rn, rl }
      local inv = cfg.inverter and -1 or 1
      local tx = ang[cfg.eixoX] * cfg.sinalX
      local ty = ang[cfg.eixoY] * cfg.sinalY
      local gx = giro[cfg.eixoX] * cfg.sinalX
      local gy = giro[cfg.eixoY] * cfg.sinalY
      local cx = lim1(-inv * (cfg.kp * tx + cfg.kd * gx))
      local cy = lim1(-inv * (cfg.kp * ty + cfg.kd * gy))

      -- rumo e freio de giro pela velocidade angular do sublevel.
      -- psi = quanto o missil girou (sentido horario) desde o lancamento
      local g = 0
      if wy then
        S.temGiro, S.wy = true, wy
        S.psi = S.psi - wy * dt
        if S.psi > math.pi then S.psi = S.psi - 2 * math.pi end
        if S.psi < -math.pi then S.psi = S.psi + 2 * math.pi end
        if cfg.controleGiro and S.mapeados >= 2 then
          g = clamp(-cfg.kGiro * wy, -GIRO_MAX, GIRO_MAX) * (cfg.inverterGiro and -1 or 1)
        end
      end

      -- teste do sentido do freio: toque + e depois -, medindo a rotacao.
      -- O freio esta certo se a rotacao muda no mesmo sentido do toque.
      local tg = S.tg
      if tg and wy and not tg.res then
        local tv = t - S.inicio
        if tv >= 3 and tv < 3.8 then
          g = TESTE_PULSO
          tg.a1 = tg.a1 or wy
          tg.b1 = wy
        elseif tv >= 3.8 and tv < 4.6 then
          g = -TESTE_PULSO
          tg.a2 = tg.a2 or wy
          tg.b2 = wy
        elseif tv >= 4.6 then
          if tg.a1 and tg.a2 then
            -- a diferenca entre os dois toques cancela um giro que ja existia
            tg.s = (tg.b1 - tg.a1) - (tg.b2 - tg.a2)
            tg.inverter = tg.s < 0
            if math.abs(tg.s) < 0.02 then
              tg.res = "inconclusivo"
            else
              tg.res = (tg.inverter == cfg.inverterGiro) and "CERTO" or "TROCAR"
            end
          else
            tg.res = "inconclusivo"
          end
        end
      end

      if not ultX or math.abs(cx - ultX) > 0.01 or math.abs(cy - ultY) > 0.01
        or math.abs(g - ultG) > 0.01 then
        vetorComando(cx, cy, g)
        ultX, ultY, ultG = cx, cy, g
      end

      S.n, S.l, S.cx, S.cy = n, l, cx, cy
      S.giro = math.max(math.abs(rn), math.abs(rl))
      ciclos = ciclos + 1
      if t - tHz >= 1 then
        S.hz = ciclos / (t - tHz)
        ciclos, tHz = 0, t
      end
    end
  end

  -- TAREFA: navegacao por GPS, fases do voo e espoleta
  local function navegacao()
    local o = S.origem
    local ultPos, ultT, ultGps = o, os.clock(), os.clock()
    local vn, vl, vy = 0, 0, 0
    local velAnt = 0
    local jT, jVn, jVl, sCN, sCL, nC = os.clock(), 0, 0, 0, 0, 0
    local ultAcel = -1

    local function acelLiquidos(u)
      S.acel = u
      if math.abs(u - ultAcel) >= 0.02 then
        for _, m in ipairs(P.motores) do
          if m.classe ~= "solido" then acelerar(m, u) end
        end
        ultAcel = u
      end
    end

    while true do
      sleep(0.1)
      local p = posicao(0.3)
      local t = os.clock()
      local tv = t - S.inicio

      if not p then
        if t - ultGps > 2 then S.alvoN, S.alvoL = 0, 0 end
        if t - ultGps > 8 then
          S.motivo = "Posicao perdida (sublevel/GPS): voo cancelado"
          return
        end
      else
        local dt = math.max(t - ultT, 0.05)
        local dn, dl = horiz(ultPos, p)
        local rVn, rVl, rVy = dn / dt, dl / dt, (p.y - ultPos.y) / dt
        local velBruta = math.sqrt(rVn * rVn + rVl * rVl + rVy * rVy)
        vn = vn + 0.5 * (rVn - vn)
        vl = vl + 0.5 * (rVl - vl)
        vy = vy + 0.5 * (rVy - vy)
        ultPos, ultT, ultGps = p, t, t
        S.pos, S.vel = p, { n = vn, l = vl, y = vy }

        local en, el = horiz(p, alvo)
        local distH = mag(en, el)
        local dist = math.sqrt(distH * distH + (alvo.y - p.y) ^ 2)
        S.distH, S.dist = distH, dist

        -- armar a ogiva longe da base
        if not S.armado and tv >= cfg.tempoArme then
          local on, ol = horiz(o, p)
          if math.sqrt(on * on + ol * ol + (p.y - o.y) ^ 2) >= cfg.distArme then
            S.armado = true
            evento("OGIVA ARMADA")
          end
        end

        -- espoleta
        if S.armado then
          if dist <= cfg.raioDetonacao then detonar("alvo atingido") return end
          if cfg.impacto and velAnt > 8 and velBruta < 1.5 then detonar("impacto") return end
          if cfg.tempoMax > 0 and tv >= cfg.tempoMax then detonar("tempo maximo") return end
        elseif cfg.tempoMax > 0 and tv >= cfg.tempoMax then
          S.motivo = "Tempo maximo (ogiva desarmada)"
          return
        end
        velAnt = velBruta

        -- fases
        local fase = S.fase
        if fase == "DECOLAGEM" and p.y - o.y >= cfg.altSaida then fase = "SUBIDA" end
        if fase == "SUBIDA" and p.y >= S.cruzeiroY - 3 then fase = "CRUZEIRO" end
        if (fase == "SUBIDA" or fase == "CRUZEIRO") and distH <= cfg.distAtaque then fase = "ATAQUE" end
        if fase == "ATAQUE" and distH > cfg.distAtaque * 2.5 then fase = "CRUZEIRO" end
        if fase ~= S.fase then
          S.fase = fase
          evento("FASE: " .. fase)
        end

        local tn, tl = 0, 0
        if fase == "DECOLAGEM" then
          acelLiquidos(cfg.acelerador)
        else
          -- horizontal: posicao -> velocidade desejada -> inclinacao desejada
          local vMax, iMax = cfg.velMax, cfg.inclMax
          if fase == "SUBIDA" then iMax = iMax * 0.5 end
          if fase == "ATAQUE" then vMax = math.min(vMax, math.max(2, distH)) end
          local dvn, dvl = limitarMag(cfg.kPos * en, cfg.kPos * el, vMax)
          tn, tl = limitarMag(cfg.kVel * (dvn - vn), cfg.kVel * (dvl - vl), iMax)

          -- vertical: acelerador dos motores liquidos
          local vzDes
          if fase == "ATAQUE" then
            vzDes = -cfg.velDescida * clamp(1 - distH / cfg.distAtaque, 0.2, 1)
          else
            vzDes = clamp(cfg.kAlt * (S.cruzeiroY - p.y), -cfg.velDescida, cfg.velSubida)
          end
          local erro = vzDes - vy
          S.integral = clamp(S.integral + cfg.kiVz * erro * dt, 0, 1)
          local u = S.integral + cfg.kVz * erro
          local incAtual = math.min(math.max(math.abs(S.n), math.abs(S.l)), 60)
          u = u / math.max(math.cos(math.rad(incAtual)), 0.5)
          acelLiquidos(clamp(u, 0, 1))
        end

        -- estima o giro do missil no proprio eixo comparando o que foi
        -- pedido com a aceleracao medida pelo GPS (janela de 1 s)
        sCN, sCL, nC = sCN + tn, sCL + tl, nC + 1
        if t - jT >= 1 then
          local dtj = t - jT
          local an, al = (vn - jVn) / dtj, (vl - jVl) / dtj
          local cn, cl = sCN / nC, sCL / nC
          if cfg.corrigirGiro and not S.temGiro and fase ~= "DECOLAGEM" and mag(cn, cl) > 4 and mag(an, al) > 0.8 then
            local e = atan2(cn * al - cl * an, cn * an + cl * al)
            S.psi = clamp(S.psi + 0.3 * e, -math.rad(60), math.rad(60))
          end
          jT, jVn, jVl, sCN, sCL, nC = t, vn, vl, 0, 0, 0
        end

        S.alvoN, S.alvoL = rotacionar(tn, tl, -S.psi)
      end
    end
  end

  -- TAREFA: tela e telemetria para a base
  local function telemetria()
    while true do
      local algum, total, linhas = false, 0, {}
      for _, m in ipairs(P.motores) do
        local kn = empuxoKN(m)
        total = total + kn
        local txt, tem = combustivel(m)
        -- so conta motores que estao em uso (solidos desligados nao contam)
        if tem and (m.classe ~= "solido" or cfg.usarSolidos) then algum = true end
        table.insert(linhas, { r = m.rotulo, nome = m.nome, kn = kn, t = txt, ok = tem })
      end
      if not guiado and #ativos > 0 and not algum then
        S.motivo = "Combustivel esgotado"
        return
      end

      local tv = os.clock() - S.inicio
      cabecalho(("%s  T+%.1fs"):format(S.fase, tv))
      desenharHorizonte(S.n, S.l, S.alvoN, S.alvoL)
      local x = 18
      escrever(x, 3, ("Incl.  N %5.1f  L %5.1f"):format(S.n, S.l))
      escrever(x, 4, ("Pedido N %5.1f  L %5.1f"):format(S.alvoN, S.alvoL), colors.cyan)
      escrever(x, 5, ("Bocal  X %5.2f  Y %5.2f"):format(S.cx, S.cy), colors.lightBlue)
      escrever(x, 6, ("Ctrl %4.1f Hz   Giro %4.0f/s"):format(S.hz, S.giro),
        S.hz >= 5 and colors.lime or colors.red)
      if guiado then
        local py = S.pos and S.pos.y or 0
        local meta = S.fase == "ATAQUE" and alvo.y or S.cruzeiroY
        escrever(x, 7, ("Dist %6.0f  horiz %6.0f"):format(S.dist or 0, S.distH or 0), colors.yellow)
        escrever(x, 8, ("Alt  %6.1f  meta  %6.0f"):format(py, meta))
        escrever(x, 9, ("Vel  %6.1f  Vy    %6.1f"):format(mag(S.vel.n, S.vel.l), S.vel.y))
        escrever(x, 10, S.armado and "ARMADO" or "desarmado", S.armado and colors.red or colors.lime)
        escrever(x + 11, 10, ("acel %3d%%  rumo %3.0f"):format(math.floor(S.acel * 100 + 0.5),
          math.deg(S.psi)), colors.orange)
      else
        escrever(x, 8, ("Empuxo %7.2f kN"):format(total), colors.orange)
        local tg = S.tg
        if tg then
          local txt, c = "Teste giro: aguardando", colors.lightGray
          if tg.res == "CERTO" then
            txt, c = "Teste giro: CERTO", colors.lime
          elseif tg.res == "TROCAR" then
            txt, c = "Teste giro: INVERTIDO", colors.red
          elseif tg.res then
            txt = "Teste giro: inconclusivo"
          elseif tg.a1 then
            txt, c = "Teste giro: medindo...", colors.yellow
          end
          escrever(x, 10, txt, c)
        end
      end
      escrever(x, 11, ("Rot %4.0f g/s  pos %s"):format(math.deg(S.wy), fontePos),
        math.abs(math.deg(S.wy)) > 90 and colors.red or colors.lightGray)
      local y = 12
      for _, li in ipairs(linhas) do
        if y > H - 2 then break end
        escrever(2, y, ("%s %-12s %7.2f kN  %s"):format(li.r, li.nome:sub(1, 12), li.kn, li.t),
          li.ok and colors.white or colors.red)
        y = y + 1
      end
      if S.eventos[1] then escrever(2, H - 1, S.eventos[1], colors.lightGray) end
      rodape("X ou BACKSPACE = ABORTAR")

      if base then
        local motores = {}
        for _, li in ipairs(linhas) do
          table.insert(motores, { r = li.r, t = li.t, ok = li.ok })
        end
        rednet.send(base, {
          tipo = "telemetria", nome = nomeRede(), fase = S.fase, t = tv,
          pos = S.pos, alvo = alvo, dist = S.dist, distH = S.distH,
          vel = S.vel, cruzeiroY = S.cruzeiroY, armado = S.armado,
          n = S.n, l = S.l, psi = math.deg(S.psi), hz = S.hz,
          acel = S.acel, empuxo = total, motores = motores,
        }, PROTOCOLO)
      end
      sleep(0.5)
    end
  end

  -- TAREFA: teclado
  local function teclado()
    while true do
      local _, k = os.pullEvent("key")
      if k == keys.x or k == keys.backspace then
        S.motivo = "Abortado pelo operador"
        return
      end
    end
  end

  -- TAREFA: ordens pela rede durante o voo
  local function rede()
    while true do
      local id, msg = rednet.receive(PROTOCOLO)
      if type(msg) == "table" then
        if msg.tipo == "abortar" then
          S.motivo = "Abortado pela base #" .. id
          return
        elseif msg.tipo == "ping" then
          rednet.send(id, { tipo = "status", nome = nomeRede(), versao = VERSAO,
            pronto = false, emVoo = true, problemas = { "em voo" },
            pos = S.pos, preset = cfg.nome, precisaCodigo = cfg.codigo ~= "",
            vet = #P.vetores, liq = contar("liquido"), sol = contar("solido") }, PROTOCOLO)
        end
      end
    end
  end

  local tarefas = { controle, telemetria, teclado }
  if guiado then table.insert(tarefas, navegacao) end
  if rednet.isOpen() then table.insert(tarefas, rede) end

  local ok, err = pcall(parallel.waitForAny, table.unpack(tarefas))

  desligarTudo()
  if S.detonou then pcall(sleep, 1) end
  ogiva(false)
  if not ok then
    S.motivo = err == "Terminated" and "Interrompido (CTRL+T)" or ("Erro: " .. tostring(err))
  end
  if base then
    rednet.send(base, { tipo = "evento", texto = S.motivo, fim = true }, PROTOCOLO)
  end

  local linhas = {
    S.motivo,
    "",
    ("Tempo de voo:       %.1f s"):format(os.clock() - S.inicio),
    ("Inclinacao maxima:  %.1f graus"):format(S.incMax),
  }
  if guiado and S.dist then
    table.insert(linhas, ("Distancia do alvo:  %.1f blocos"):format(S.dist))
  end
  if contar("solido") > 0 and cfg.usarSolidos then
    table.insert(linhas, "")
    table.insert(linhas, "Solidos podem continuar queimando!")
  end
  local tg = S.tg
  if tg and tg.res then
    table.insert(linhas, "")
    if tg.res == "CERTO" then
      table.insert(linhas, "Freio de giro: sentido CERTO")
    elseif tg.res == "TROCAR" then
      table.insert(linhas, "Freio de giro: sentido INVERTIDO")
    else
      table.insert(linhas, "Freio de giro: teste inconclusivo (reagiu pouco)")
    end
  end
  local corFinal = (ok and not S.motivo:upper():find("ABORT")) and colors.white or colors.red
  if base then
    avisoTempo("VOO ENCERRADO", linhas, corFinal, 8)
  else
    aviso("VOO ENCERRADO", linhas, corFinal)
    if tg and tg.res == "TROCAR" and confirmar("FREIO DE GIRO",
      "O teste indicou sentido invertido. Trocar 'Inverter freio de giro' e salvar?") then
      cfg.inverterGiro = tg.inverter
      salvarConfig()
    end
  end
end

local function lancarLocal()
  detectar()
  abrirRede()
  cabecalho("LANCAR EM COORDENADA")
  escrever(2, 3, "Coordenada do alvo (F3 no alvo):", colors.yellow)
  local function numero(y, rotulo, padrao)
    local r = perguntar(y, rotulo, padrao)
    return r and tonumber((r:gsub(",", ".")))
  end
  local x = numero(5, "X: ", cfg.alvoX)
  local y = x and numero(6, "Y: ", cfg.alvoY)
  local z = y and numero(7, "Z: ", cfg.alvoZ)
  if not (x and y and z) then
    aviso("LANCAR", { "Coordenada invalida." }, colors.red)
    return
  end
  cfg.alvoX, cfg.alvoY, cfg.alvoZ = x, y, z
  salvarConfig()
  if not (cfg.gimbalOk and cfg.bocalOk)
    and not confirmar("LANCAR", "Calibracao pendente! Lancar mesmo assim?") then
    return
  end
  voar({ alvo = { x = x, y = y, z = z } })
end

---------------------------------------------------------------- MODO REMOTO

local function modoRemoto()
  while true do
    detectar()
    if not P.modem then
      aviso("MODO REMOTO", { "Precisa de um modem SEM FIO encostado",
        "direto no computador (de preferencia Ender Modem)." }, colors.red)
      return
    end
    abrirRede()
    pcall(rednet.host, SERVICO, nomeRede())

    local pedido, sair = nil, false
    local contato = nil
    local posTxt = "procurando..."

    local function tela()
      local st = statusMissil()
      cabecalho("MODO REMOTO")
      escrever(2, 3, "AGUARDANDO ORDEM DA BASE", colors.yellow)
      escrever(2, 5, "Nome na rede", colors.lightGray)
      escrever(17, 5, nomeRede())
      escrever(2, 6, "Status", colors.lightGray)
      escrever(17, 6, st.pronto and "PRONTO" or "NAO PRONTO", st.pronto and colors.lime or colors.red)
      local y = 7
      for _, pr in ipairs(st.problemas) do
        escrever(4, y, "- " .. pr, colors.orange)
        y = y + 1
      end
      escrever(2, y + 1, "Posicao", colors.lightGray)
      escrever(17, y + 1, posTxt, ultimaPos and colors.white or colors.red)
      escrever(2, y + 2, "Preset", colors.lightGray)
      escrever(17, y + 2, cfg.nome)
      escrever(2, y + 3, "Codigo", colors.lightGray)
      escrever(17, y + 3, cfg.codigo ~= "" and "exigido" or "nenhum")
      if contato then
        escrever(2, y + 4, "Ultimo contato", colors.lightGray)
        escrever(17, y + 4, contato)
      end
      rodape("BACKSPACE sai do modo remoto")
    end

    local function atualizar()
      while true do
        local p = posicao(1)
        posTxt = p and ("%.0f %.0f %.0f (%s)"):format(p.x, p.y, p.z, fontePos) or "sem sinal"
        tela()
        sleep(2)
      end
    end

    local function ouvir()
      while true do
        local id, msg = rednet.receive(PROTOCOLO)
        if type(msg) == "table" then
          contato = ("base #%d"):format(id)
          if msg.tipo == "ping" then
            rednet.send(id, statusMissil(), PROTOCOLO)
          elseif msg.tipo == "lancar" then
            local st = statusMissil()
            local a = type(msg.alvo) == "table" and msg.alvo or {}
            local alvo = { x = tonumber(a.x), y = tonumber(a.y), z = tonumber(a.z) }
            local negar
            if not st.pronto then
              negar = "Nao pronto: " .. table.concat(st.problemas, ", ")
            elseif cfg.codigo ~= "" and msg.codigo ~= cfg.codigo then
              negar = "Codigo de lancamento incorreto"
            elseif not (alvo.x and alvo.y and alvo.z) then
              negar = "Alvo invalido"
            end
            if negar then
              rednet.send(id, { tipo = "lancar_negado", motivo = negar }, PROTOCOLO)
            else
              rednet.send(id, { tipo = "lancar_ok", nome = nomeRede() }, PROTOCOLO)
              pedido = { alvo = alvo, base = id }
              return
            end
          end
          tela()
        end
      end
    end

    local function teclas()
      while true do
        local _, k = os.pullEvent("key")
        if k == keys.backspace then
          sair = true
          return
        end
      end
    end

    parallel.waitForAny(atualizar, ouvir, teclas)
    if sair then
      pcall(rednet.unhost, SERVICO)
      return
    end
    if pedido then voar(pedido) end
  end
end

---------------------------------------------------------------- AJUSTES

local MARCA_STARTUP = "-- bfm_autostart"

local function atualizarStartup()
  local existe = fs.exists("/startup.lua")
  local nosso = false
  if existe then
    local f = fs.open("/startup.lua", "r")
    nosso = (f.readAll() or ""):find(MARCA_STARTUP, 1, true) ~= nil
    f.close()
  end
  if cfg.iniciarRemoto then
    if existe and not nosso
      and not confirmar("STARTUP", "Ja existe um startup.lua de outro programa. Substituir?") then
      cfg.iniciarRemoto = false
      return
    end
    local f = fs.open("/startup.lua", "w")
    f.write(MARCA_STARTUP .. "\nshell.run(\"/" .. shell.getRunningProgram() .. "\", \"remoto\")\n")
    f.close()
  elseif nosso then
    fs.delete("/startup.lua")
  end
end

local GRUPOS = {
  { "Voo e estabilizacao", {
    { "empuxoVetor", "Empuxo do vetor (0-1)", 0, 1 },
    { "acelerador", "Acelerador decolagem (0-1)", 0, 1 },
    { "usarSolidos", "Usar motores solidos" },
    { "kp", "KP forca da correcao", 0, 1 },
    { "kd", "KD amortecimento", 0, 1 },
    { "inverter", "Inverter correcao" },
    { "controleGiro", "Frear giro (sublevel)" },
    { "kGiro", "Forca do freio de giro", 0, 2 },
    { "inverterGiro", "Inverter freio de giro" },
    { "abortar", "Abortar acima de (graus)", 5, 90 },
    { "contagem", "Contagem regressiva (s)", 0, 30 },
  } },
  { "Navegacao GPS", {
    { "altCruzeiro", "Altura cruzeiro (+blocos)", 5, 300 },
    { "altSaida", "Subida vertical inicial", 3, 100 },
    { "velMax", "Velocidade horizontal max", 2, 60 },
    { "velSubida", "Velocidade de subida max", 1, 40 },
    { "velDescida", "Velocidade de mergulho", 1, 40 },
    { "inclMax", "Inclinacao max (graus)", 2, 45 },
    { "distAtaque", "Distancia p/ mergulho", 3, 100 },
    { "kPos", "Ganho de posicao", 0, 2 },
    { "kVel", "Ganho de velocidade", 0, 10 },
    { "kAlt", "Ganho de altura", 0, 5 },
    { "kVz", "Ganho vertical P", 0, 1 },
    { "kiVz", "Ganho vertical I", 0, 1 },
    { "acelBase", "Acelerador p/ pairar (0-1)", 0, 1 },
    { "corrigirGiro", "Corrigir rumo automatico" },
    { "alcanceMax", "Alcance maximo (blocos)", 50, 20000 },
  } },
  { "Ogiva e seguranca", {
    { "ladoOgiva", "Lado da ogiva (redstone)" },
    { "raioDetonacao", "Raio de detonacao", 1, 20 },
    { "tempoArme", "Armar apos (segundos)", 0, 60 },
    { "distArme", "Armar a (blocos da base)", 0, 500 },
    { "tempoMax", "Autodestruir apos (s, 0=nao)", 0, 900 },
    { "impacto", "Detonar no impacto" },
  } },
  { "Sistema", {
    { "_label", "Nome do missil" },
    { "codigo", "Codigo de lancamento" },
    { "iniciarRemoto", "Ligar ja em modo remoto" },
  } },
}

local function valorTxt(chave)
  if chave == "_label" then return os.getComputerLabel() or "(sem nome)" end
  local v = cfg[chave]
  if type(v) == "boolean" then return v and "SIM" or "NAO" end
  if chave == "codigo" then return v == "" and "(nenhum)" or string.rep("*", #v) end
  return tostring(v)
end

local function editarGrupo(grupo)
  while true do
    local ops = {}
    for _, it in ipairs(grupo[2]) do
      table.insert(ops, ("%-28s %s"):format(it[2], valorTxt(it[1])))
    end
    table.insert(ops, "Voltar")
    local i = menu(grupo[1]:upper(), ops)
    if not i or i == #ops then return end

    local chave, nome, min, max = table.unpack(grupo[2][i])
    if chave == "_label" then
      cabecalho("NOME DO MISSIL")
      escrever(2, 3, "Letras, numeros, _ ou - (sem espacos)", colors.lightGray)
      local r = perguntar(5, "Nome: ", os.getComputerLabel())
      if r and r:match("^[%w_%-]+$") then
        os.setComputerLabel(r)
      elseif r and r ~= "" then
        aviso("NOME", { "Nome invalido." }, colors.red)
      end
    elseif chave == "ladoOgiva" then
      local idx = 1
      for k, lado in ipairs(LADOS) do
        if lado == cfg.ladoOgiva then idx = k end
      end
      cfg.ladoOgiva = LADOS[idx % #LADOS + 1]
    elseif chave == "codigo" then
      cabecalho("CODIGO DE LANCAMENTO")
      escrever(2, 3, "A base vai pedir este codigo para lancar.", colors.lightGray)
      escrever(2, 4, "Deixe vazio para nao exigir.", colors.lightGray)
      local r = perguntar(6, "Codigo: ", nil, true)
      cfg.codigo = r or ""
    elseif type(cfg[chave]) == "boolean" then
      cfg[chave] = not cfg[chave]
      if chave == "iniciarRemoto" then atualizarStartup() end
    else
      cabecalho(grupo[1]:upper())
      escrever(2, 3, nome, colors.yellow)
      escrever(2, 4, ("Valor entre %s e %s"):format(min, max), colors.lightGray)
      local r = perguntar(6, "Novo valor: ", cfg[chave])
      local v = r and tonumber((r:gsub(",", ".")))
      if v and INTEIROS[chave] then v = math.floor(v + 0.5) end
      if v and v >= min and v <= max then
        cfg[chave] = v
      else
        aviso("AJUSTES", { "Valor invalido." }, colors.red)
      end
    end
    salvarConfig()
  end
end

local function ajustes()
  while true do
    local ops = {}
    for _, g in ipairs(GRUPOS) do table.insert(ops, g[1]) end
    table.insert(ops, "Restaurar padroes (mantem calibracao)")
    table.insert(ops, "Voltar")
    local i = menu("AJUSTES", ops)
    if not i or i == #ops then return end
    if i <= #GRUPOS then
      editarGrupo(GRUPOS[i])
    elseif confirmar("AJUSTES", "Restaurar todos os ajustes para o padrao?") then
      local manter = { "offX", "offZ", "eixoN", "sinalN", "eixoL", "sinalL", "gimbalOk",
        "eixoX", "sinalX", "eixoY", "sinalY", "bocalOk", "posMotores", "nome", "iniciarRemoto" }
      local novo = copiar(PADRAO)
      for _, k in ipairs(manter) do novo[k] = cfg[k] end
      cfg = novo
      salvarConfig()
    end
  end
end

---------------------------------------------------------------- PRESETS

local function localPresets()
  detectar()
  if P.drive and P.drive.isDiskPresent() and P.drive.hasData() then
    return fs.combine(P.drive.getMountPath(), PASTA_PRESETS), true
  end
  return "/" .. PASTA_PRESETS, false
end

local function listarPresets(pasta)
  local lista = {}
  if fs.exists(pasta) then
    for _, arq in ipairs(fs.list(pasta)) do
      local nome = arq:match("^(.+)%.preset$")
      if nome then table.insert(lista, nome) end
    end
  end
  table.sort(lista)
  return lista
end

local function escolherPreset(titulo, pasta)
  local lista = listarPresets(pasta)
  if #lista == 0 then
    aviso(titulo, { "Nenhum preset salvo aqui." }, colors.orange)
    return nil
  end
  local ops = copiar(lista)
  table.insert(ops, "Voltar")
  local i = menu(titulo, ops)
  if not i or i == #ops then return nil end
  return lista[i]
end

local function presets()
  while true do
    local pasta, noDisco = localPresets()
    local rotulo = noDisco and (P.drive.getDiskLabel() or "sem rotulo") or nil
    local info = {
      { noDisco and ("Disquete: " .. rotulo) or "SEM DISQUETE - usando o computador",
        noDisco and colors.lime or colors.orange },
      { "Preset ativo: " .. cfg.nome, colors.lightGray },
    }
    local i = menu("PRESETS", {
      "Salvar configuracao atual",
      "Carregar preset",
      "Apagar preset",
      "Rotular disquete",
      "Voltar",
    }, info)
    if not i or i == 5 then return end

    if i == 1 then
      cabecalho("SALVAR PRESET")
      escrever(2, 3, "Nome do preset (letras, numeros, _ ou -)", colors.yellow)
      escrever(2, 4, noDisco and "Destino: disquete" or "Destino: computador", colors.lightGray)
      local nome = perguntar(6, "> ", cfg.nome ~= "sem_nome" and cfg.nome or nil)
      if nome and nome:match("^[%w_%-]+$") and #nome <= 20 then
        local caminho = fs.combine(pasta, nome .. ".preset")
        if not fs.exists(caminho)
          or confirmar("SALVAR PRESET", "'" .. nome .. "' ja existe. Substituir?") then
          cfg.nome = nome
          gravarTabela(caminho, cfg)
          salvarConfig()
          aviso("SALVAR PRESET", { "Preset '" .. nome .. "' salvo!" }, colors.lime)
        end
      else
        aviso("SALVAR PRESET", { "Nome invalido (max 20, sem espacos)." }, colors.red)
      end

    elseif i == 2 then
      local nome = escolherPreset("CARREGAR PRESET", pasta)
      if nome then
        local dados = lerTabela(fs.combine(pasta, nome .. ".preset"))
        if dados then
          local remoto = cfg.iniciarRemoto
          cfg = copiar(PADRAO)
          aplicar(dados)
          cfg.nome = nome
          cfg.iniciarRemoto = remoto
          salvarConfig()
          aviso("CARREGAR PRESET", {
            "Preset '" .. nome .. "' carregado!",
            ("Gimbal %s   Bocal %s"):format(cfg.gimbalOk and "OK" or "PENDENTE",
              cfg.bocalOk and "OK" or "PENDENTE"),
            "Lembre: a calibracao so vale para a mesma montagem.",
          }, colors.lime)
        else
          aviso("CARREGAR PRESET", { "Arquivo corrompido." }, colors.red)
        end
      end

    elseif i == 3 then
      local nome = escolherPreset("APAGAR PRESET", pasta)
      if nome and confirmar("APAGAR PRESET", "Apagar '" .. nome .. "'?") then
        fs.delete(fs.combine(pasta, nome .. ".preset"))
        aviso("APAGAR PRESET", { "Preset apagado." }, colors.lime)
      end

    elseif i == 4 then
      if not noDisco then
        aviso("ROTULAR", { "Coloque um disquete no Disk Drive." }, colors.orange)
      else
        cabecalho("ROTULAR DISQUETE")
        local r = perguntar(4, "Rotulo: ", rotulo)
        if r and #r > 0 then
          P.drive.setDiskLabel(r)
          aviso("ROTULAR", { "Disquete rotulado: " .. r }, colors.lime)
        end
      end
    end
  end
end

---------------------------------------------------------------- TESTES

local function painel()
  while true do
    detectar()
    cabecalho("STATUS")
    local y = 3
    if P.gimbal then
      local n, l = lerAngulos()
      escrever(2, y, ("GIM Norte %6.1f  Leste %6.1f"):format(n, l), colors.lime)
    else
      escrever(2, y, "GIM nao encontrado", colors.red)
    end
    y = y + 1
    escrever(2, y, "MOD " .. (P.modem and ("sem fio no lado " .. P.modem) or "sem modem sem fio direto"),
      P.modem and colors.lime or colors.red)
    y = y + 1
    if #P.vetores == 0 then
      escrever(2, y, "VET nao encontrado", colors.red)
      y = y + 1
    end
    for _, v in ipairs(P.vetores) do
      escrever(2, y, ("VET %-18s X %5.2f  Y %5.2f"):format(v.nome:sub(1, 18),
        chamar(v.p, "getVectorX") or 0, chamar(v.p, "getVectorY") or 0))
      y = y + 1
    end
    for _, m in ipairs(P.motores) do
      if y >= H - 1 then break end
      local txt, tem = combustivel(m)
      escrever(2, y, ("%s %-18s %s"):format(m.rotulo, m.nome:sub(1, 18), txt),
        tem and colors.white or colors.red)
      y = y + 1
    end
    if #P.motores == 0 and y < H - 1 then
      escrever(2, y, "Nenhum motor encontrado", colors.orange)
    end
    local _, noDisco = localPresets()
    escrever(2, H - 1, noDisco and "Disquete: OK" or "Disquete: nao", colors.lightGray)
    rodape("BACKSPACE volta")

    local timer = os.startTimer(0.5)
    repeat
      local ev, p = os.pullEvent()
      if ev == "key" and p == keys.backspace then return end
    until ev == "timer" and p == timer
  end
end

local function bocalManual()
  detectar()
  if #P.vetores == 0 then
    aviso("ERRO", { "Vector thruster nao encontrado." }, colors.red)
    return
  end
  local x, y, pot, giro = 0, 0, 0, 0
  local PASSO = 0.1
  local v = P.vetores[1].p

  while true do
    vetorComando(x, y, giro)
    vetorEmpuxo(pot)
    cabecalho("BOCAL MANUAL")
    escrever(2, 3, "SETAS   inclinar o bocal", colors.lightGray)
    escrever(2, 4, "W / S   empuxo do vetor", colors.lightGray)
    escrever(2, 5, "ESPACO  centralizar", colors.lightGray)
    escrever(2, 6, "Q / E   freio de giro (bocais em catavento)", colors.lightGray)
    escrever(2, 10, ("Giro    %5.2f   motores com lado: %d/%d"):format(giro,
      motoresMapeados(), #P.vetores), giro ~= 0 and colors.cyan or colors.white)
    escrever(2, 7, ("Alvo    X %5.2f   Y %5.2f"):format(x, y))
    escrever(2, 8, ("Atual   X %5.2f   Y %5.2f"):format(
      chamar(v, "getVectorX") or 0, chamar(v, "getVectorY") or 0))
    escrever(2, 9, ("Empuxo  %d%%"):format(math.floor(pot * 100 + 0.5)),
      pot > 0 and colors.orange or colors.white)
    rodape("BACKSPACE sai (zera o bocal)")

    local timer = os.startTimer(0.2)
    local ev, k = os.pullEvent()
    if ev == "key" then
      if k == keys.left then x = clamp(x - PASSO, -1, 1)
      elseif k == keys.right then x = clamp(x + PASSO, -1, 1)
      elseif k == keys.up then y = clamp(y + PASSO, -1, 1)
      elseif k == keys.down then y = clamp(y - PASSO, -1, 1)
      elseif k == keys.w then pot = clamp(pot + PASSO, 0, 1)
      elseif k == keys.s then pot = clamp(pot - PASSO, 0, 1)
      elseif k == keys.q then giro = clamp(giro - 0.25, -0.5, 0.5)
      elseif k == keys.e then giro = clamp(giro + 0.25, -0.5, 0.5)
      elseif k == keys.space then x, y, giro = 0, 0, 0
      elseif k == keys.backspace then return end
    end
    os.cancelTimer(timer)
  end
end

local function testeGps()
  detectar()
  if not P.modem and not sublevelPose() then
    aviso("TESTE GPS", { "Sem posicao: o computador nao esta num sublevel",
      "e nao tem modem sem fio encostado (GPS)." }, colors.red)
    return
  end
  local amostras, falhas = 0, 0
  local function loop()
    while true do
      local t0 = os.clock()
      local p = posicao(1)
      local ms = (os.clock() - t0) * 1000
      if p then amostras = amostras + 1 else falhas = falhas + 1 end
      cabecalho("TESTE GPS")
      if p then
        escrever(2, 3, "Posicao do missil (" .. fontePos .. "):", colors.lightGray)
        escrever(2, 4, ("X %.2f   Y %.2f   Z %.2f"):format(p.x, p.y, p.z), colors.lime)
        local dH = mag(horiz(p, { x = cfg.alvoX, y = cfg.alvoY, z = cfg.alvoZ }))
        escrever(2, 6, ("Ultimo alvo (%d %d %d): %d blocos"):format(math.floor(cfg.alvoX),
          math.floor(cfg.alvoY), math.floor(cfg.alvoZ), math.floor(dH)), colors.lightGray)
        escrever(2, 7, ("Resposta em %d ms"):format(math.floor(ms)), colors.lightGray)
        escrever(2, 9, "Confira com o F3! Se a posicao for muito diferente", colors.yellow)
        escrever(2, 10, "da real, o GPS nao funciona dentro da contraption.", colors.yellow)
      else
        escrever(2, 3, "SEM SINAL DE GPS", colors.red)
        escrever(2, 5, "- Existem 4 torres (gps_torre) ligadas?")
        escrever(2, 6, "- As torres estao em chunks carregados?")
        escrever(2, 7, "- As torres nao estao todas na mesma altura?")
        escrever(2, 8, "- Modem sem fio comum tem alcance curto.")
      end
      escrever(2, 12, ("Leituras ok: %d   falhas: %d"):format(amostras, falhas), colors.lightGray)
      rodape("BACKSPACE volta")
      sleep(0.5)
    end
  end
  local function tecla()
    repeat
      local _, k = os.pullEvent("key")
    until k == keys.backspace
  end
  parallel.waitForAny(loop, tecla)
end

local function testeOgiva()
  if not confirmar("TESTE DA OGIVA",
    ("Vai ligar redstone no lado '%s' por 2 segundos. Use uma LAMPADA no lugar da TNT! Continuar?")
      :format(cfg.ladoOgiva)) then
    return
  end
  ogiva(true)
  cabecalho("TESTE DA OGIVA")
  escrever(2, 4, "REDSTONE LIGADO", colors.red)
  sleep(2)
  ogiva(false)
  aviso("TESTE DA OGIVA", { "Redstone desligado.", "A lampada acendeu? Entao a ogiva esta ok." }, colors.lime)
end

local function testes()
  while true do
    local i = menu("TESTES", {
      "Painel de status (ao vivo)",
      "Teste de GPS",
      "Controle manual do bocal",
      "Teste da ogiva (use lampada!)",
      "Voltar",
    })
    if not i or i == 5 then return end
    if i == 1 then painel()
    elseif i == 2 then testeGps()
    elseif i == 3 then bocalManual()
    elseif i == 4 then testeOgiva() end
    desligarTudo()
    ogiva(false)
  end
end

---------------------------------------------------------------- MENU

local function principal()
  while true do
    detectar()
    abrirRede()
    local extra = contar("criativo") > 0 and ("  Cri " .. contar("criativo")) or ""
    local _, noDisco = localPresets()
    local info = {
      { ("Gimbal %s  Vetor %d  Liq %d  Sol %d  Ion %d%s"):format(
          P.gimbal and "OK" or "--", #P.vetores, contar("liquido"),
          contar("solido"), contar("ion"), extra), colors.lightGray },
      { ("Calib: gimbal %s  bocal %s  giro %d/%d"):format(
          cfg.gimbalOk and "OK" or "PENDENTE", cfg.bocalOk and "OK" or "PENDENTE",
          motoresMapeados(), #P.vetores),
        (cfg.gimbalOk and cfg.bocalOk) and colors.lime or colors.orange },
      { ("Rede: %s  %s"):format(nomeRede(), P.modem and "(modem OK)" or "(SEM MODEM)"),
        P.modem and colors.lightGray or colors.orange },
      { ("Preset: %s   Disquete: %s"):format(cfg.nome, noDisco and "SIM" or "NAO"),
        colors.lightGray },
    }
    local acoes = {
      modoRemoto, lancarLocal, voar, calibrarGimbal, calibrarBocal,
      calibrarMotores, ajustes, presets, testes,
    }
    local i = menu("MISSIL v" .. VERSAO, {
      "Modo remoto (aguardar base)",
      "Lancar em coordenada",
      "Teste de estabilizacao",
      "Calibrar gimbal",
      "Calibrar bocal",
      "Calibrar giro (lado dos motores)",
      "Ajustes",
      "Presets (disquete)",
      "Testes",
      "Sair",
    }, info)
    if not i or i == 10 then return end

    local ok, err = pcall(acoes[i])
    detectar()
    desligarTudo()
    ogiva(false)
    if not ok then
      carregarConfig()
      if err ~= "Terminated" then
        aviso("ERRO", { tostring(err) }, colors.red)
      end
    end
  end
end

carregarConfig()
local ok, err = pcall(function()
  detectar()
  abrirRede()
  if arg[1] == "remoto" then
    modoRemoto()
  elseif arg[1] == "teste" then
    voar()
    return
  end
  principal()
end)
pcall(detectar)
pcall(desligarTudo)
pcall(ogiva, false)
fundo(colors.black)
cor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok and err ~= "Terminated" then
  printError(err)
else
  print("BlockForge Militar - ate a proxima!")
end
]=] }

PROGRAMAS[#PROGRAMAS + 1] = { chave = "base", arquivo = "base.lua", titulo = "Base de lancamento", codigo = [=[
-- base.lua : BlockForge Militar - Base de Lancamento
-- Controla os misseis que estao em "modo remoto" pela rede (rednet)
-- Precisa de: computador (de preferencia avancado) + Ender Modem

local VERSAO = "1.0"
local PROTOCOLO = "bfm"
local SERVICO = "bfm_missil"
local ARQ_ALVOS = "bfm_alvos.txt"
local ARQ_ESTADO = "/bfm_base.txt"

---------------------------------------------------------------- TELA

local W, H = term.getSize()
local COR = term.isColor()

local function cor(c) if COR then term.setTextColor(c) end end
local function fundo(c) if COR then term.setBackgroundColor(c) end end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function escrever(x, y, txt, c, bg)
  term.setCursorPos(x, y)
  if bg then fundo(bg) end
  cor(c or colors.white)
  term.write(txt)
  fundo(colors.black)
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

local function quebrar(texto, largura)
  local linhas = {}
  texto = tostring(texto)
  while #texto > largura do
    table.insert(linhas, texto:sub(1, largura))
    texto = texto:sub(largura + 1)
  end
  table.insert(linhas, texto)
  return linhas
end

local function aviso(titulo, linhas, c)
  cabecalho(titulo)
  local y = 3
  for _, l in ipairs(linhas) do
    for _, parte in ipairs(quebrar(l, W - 2)) do
      if y < H then escrever(2, y, parte, c) end
      y = y + 1
    end
  end
  rodape("Aperte qualquer tecla")
  os.pullEvent("key")
end

local function confirmar(titulo, pergunta)
  cabecalho(titulo)
  for i, parte in ipairs(quebrar(pergunta, W - 2)) do
    escrever(2, 2 + i, parte, colors.yellow)
  end
  rodape("S = sim   N = nao")
  while true do
    local _, ch = os.pullEvent("char")
    ch = ch:lower()
    if ch == "s" then return true end
    if ch == "n" then return false end
  end
end

local function perguntar(y, rotulo, padrao, oculto)
  escrever(2, y, rotulo, colors.lightGray)
  term.setCursorPos(2 + #rotulo, y)
  cor(colors.white)
  return read(oculto and "*" or nil, nil, nil, padrao ~= nil and tostring(padrao) or nil)
end

local function menu(titulo, opcoes, info)
  local sel = 1
  while true do
    cabecalho(titulo)
    local y = 3
    if info then
      for _, l in ipairs(info) do
        escrever(2, y, l[1], l[2])
        y = y + 1
      end
      y = y + 1
    end
    local visiveis = math.max(1, H - y)
    local topo = 1
    if sel > visiveis then topo = sel - visiveis + 1 end
    for i = topo, math.min(#opcoes, topo + visiveis - 1) do
      local txt = ("%s%s %s"):format(i == sel and ">" or " ",
        i <= 9 and tostring(i) or " ", opcoes[i])
      if #txt > W - 2 then txt = txt:sub(1, W - 2) end
      if i == sel then
        escrever(2, y, txt .. string.rep(" ", W - 2 - #txt), colors.black, colors.yellow)
      else
        escrever(2, y, txt)
      end
      y = y + 1
    end
    rodape("SETAS/NUMERO escolhe  ENTER ok  BACKSPACE volta")
    local ev, p = os.pullEvent()
    if ev == "key" then
      if p == keys.up then
        sel = sel > 1 and sel - 1 or #opcoes
      elseif p == keys.down then
        sel = sel < #opcoes and sel + 1 or 1
      elseif p == keys.enter then
        return sel
      elseif p == keys.backspace then
        return nil
      end
    elseif ev == "char" then
      local n = tonumber(p)
      if n and n >= 1 and n <= #opcoes then return n end
    end
  end
end

---------------------------------------------------------------- DADOS

local sel = { id = nil, nome = nil }
local alvo = nil -- { nome, x, y, z }

local function lerTabela(caminho)
  if not fs.exists(caminho) then return nil end
  local f = fs.open(caminho, "r")
  local dados = textutils.unserialize(f.readAll())
  f.close()
  if type(dados) ~= "table" then return nil end
  return dados
end

local function gravarTabela(caminho, t)
  local f = fs.open(caminho, "w")
  f.write(textutils.serialize(t))
  f.close()
end

local function carregarEstado()
  local e = lerTabela(ARQ_ESTADO)
  if e then
    sel = e.sel or sel
    alvo = e.alvo
  end
end

local function salvarEstado()
  gravarTabela(ARQ_ESTADO, { sel = sel, alvo = alvo })
end

-- lista de alvos: no disquete se tiver, senao no computador
local function arquivoAlvos()
  local drive = peripheral.find("drive")
  if drive and drive.isDiskPresent() and drive.hasData() then
    return fs.combine(drive.getMountPath(), ARQ_ALVOS), true
  end
  return "/" .. ARQ_ALVOS, false
end

local function lerAlvos()
  local caminho = arquivoAlvos()
  return lerTabela(caminho) or {}
end

local function gravarAlvos(lista)
  local caminho = arquivoAlvos()
  gravarTabela(caminho, lista)
end

local function coords(a)
  return ("%d %d %d"):format(math.floor(a.x), math.floor(a.y), math.floor(a.z))
end

---------------------------------------------------------------- REDE

local function abrirModem()
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.hasType(nome, "modem") and peripheral.call(nome, "isWireless") then
      if not rednet.isOpen(nome) then rednet.open(nome) end
      return nome
    end
  end
  return nil
end

-- espera uma mensagem de 'id' com um dos tipos pedidos
local function esperar(id, tipos, timeout)
  local timer = os.startTimer(timeout)
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "timer" and a == timer then return nil end
    if ev == "rednet_message" and a == id and c == PROTOCOLO
      and type(b) == "table" and tipos[b.tipo] then
      os.cancelTimer(timer)
      return b
    end
  end
end

local function consultar(id)
  rednet.send(id, { tipo = "ping" }, PROTOCOLO)
  return esperar(id, { status = true }, 2)
end

---------------------------------------------------------------- ACOES

local function procurar()
  cabecalho("PROCURAR MISSEIS")
  escrever(2, 3, "Procurando misseis em modo remoto...", colors.yellow)
  local ids = { rednet.lookup(SERVICO) }
  local achados = {}
  for _, id in ipairs(ids) do
    escrever(2, 5, ("Consultando #%d..."):format(id), colors.lightGray)
    local st = consultar(id)
    if st then table.insert(achados, { id = id, st = st }) end
  end

  if #achados == 0 then
    aviso("PROCURAR MISSEIS", {
      "Nenhum missil respondeu.",
      "",
      "- No missil: menu > Modo remoto",
      "- O missil tem modem sem fio?",
      "- Longe demais? Use Ender Modem nos dois.",
    }, colors.orange)
    return
  end

  local ops = {}
  for _, a in ipairs(achados) do
    table.insert(ops, ("%-22s %s"):format(a.st.nome or ("#" .. a.id),
      a.st.emVoo and "EM VOO" or (a.st.pronto and "PRONTO" or "NAO PRONTO")))
  end
  table.insert(ops, "Voltar")
  local i = menu("SELECIONAR MISSIL", ops)
  if not i or i == #ops then return end

  local a = achados[i]
  sel = { id = a.id, nome = a.st.nome }
  salvarEstado()
  local linhas = {
    "Selecionado: " .. (a.st.nome or ("#" .. a.id)),
    "Preset: " .. tostring(a.st.preset),
    ("Motores: vetor %d, liquidos %d, solidos %d"):format(a.st.vet or 0, a.st.liq or 0, a.st.sol or 0),
    "Codigo de lancamento: " .. (a.st.precisaCodigo and "exigido" or "nenhum"),
  }
  if a.st.pos then
    table.insert(linhas, "Posicao GPS: " .. coords(a.st.pos))
  end
  if not a.st.pronto then
    table.insert(linhas, "")
    table.insert(linhas, "NAO PRONTO: " .. table.concat(a.st.problemas or {}, ", "))
  end
  aviso("MISSIL SELECIONADO", linhas, a.st.pronto and colors.lime or colors.orange)
end

local function salvarNaLista(novo)
  cabecalho("SALVAR ALVO")
  local _, noDisco = arquivoAlvos()
  escrever(2, 3, "Nome do alvo (ex: bunker_norte)", colors.yellow)
  escrever(2, 4, noDisco and "Destino: disquete" or "Destino: computador", colors.lightGray)
  local nome = perguntar(6, "> ", novo.nome)
  if not nome or nome == "" then return end
  novo.nome = nome
  local lista = lerAlvos()
  for i = #lista, 1, -1 do
    if lista[i].nome == nome then table.remove(lista, i) end
  end
  table.insert(lista, { nome = nome, x = novo.x, y = novo.y, z = novo.z })
  table.sort(lista, function(a, b) return a.nome < b.nome end)
  gravarAlvos(lista)
end

local function definirAlvo()
  cabecalho("DEFINIR ALVO")
  escrever(2, 3, "Coordenada do alvo (use F3 no local):", colors.yellow)
  local function numero(y, rotulo, padrao)
    local r = perguntar(y, rotulo, padrao)
    return r and tonumber((r:gsub(",", ".")))
  end
  local x = numero(5, "X: ", alvo and alvo.x)
  local y = x and numero(6, "Y: ", alvo and alvo.y)
  local z = y and numero(7, "Z: ", alvo and alvo.z)
  if not (x and y and z) then
    aviso("DEFINIR ALVO", { "Coordenada invalida." }, colors.red)
    return
  end
  alvo = { nome = "manual", x = x, y = y, z = z }
  if confirmar("DEFINIR ALVO", ("Alvo %s definido. Salvar na lista de alvos?"):format(coords(alvo))) then
    salvarNaLista(alvo)
  end
  salvarEstado()
end

local function alvosSalvos()
  while true do
    local lista = lerAlvos()
    local _, noDisco = arquivoAlvos()
    if #lista == 0 then
      aviso("ALVOS SALVOS", { "Nenhum alvo salvo.",
        "Use 'Definir alvo' e salve na lista." }, colors.orange)
      return
    end
    local ops = {}
    for _, a in ipairs(lista) do
      table.insert(ops, ("%-20s %s"):format(a.nome, coords(a)))
    end
    table.insert(ops, "Voltar")
    local i = menu("ALVOS SALVOS", ops, {
      { noDisco and "Lista no disquete" or "Lista no computador", colors.lightGray },
    })
    if not i or i == #ops then return end

    local a = lista[i]
    local j = menu("ALVO: " .. a.nome, { "Usar como alvo", "Apagar", "Voltar" })
    if j == 1 then
      alvo = { nome = a.nome, x = a.x, y = a.y, z = a.z }
      salvarEstado()
      return
    elseif j == 2 and confirmar("APAGAR ALVO", "Apagar '" .. a.nome .. "'?") then
      table.remove(lista, i)
      gravarAlvos(lista)
    end
  end
end

local function acompanhar()
  if not sel.id then
    aviso("TELEMETRIA", { "Selecione um missil primeiro." }, colors.orange)
    return
  end

  local T, eventos, fim = nil, {}, nil
  local ultimo = os.clock()
  local dist0

  local function receber()
    while true do
      local id, msg = rednet.receive(PROTOCOLO)
      if id == sel.id and type(msg) == "table" then
        ultimo = os.clock()
        if msg.tipo == "telemetria" then
          T = msg
          if msg.dist and not dist0 then dist0 = msg.dist end
        elseif msg.tipo == "evento" then
          table.insert(eventos, 1, msg.texto)
          if #eventos > 5 then table.remove(eventos) end
          if msg.fim then fim = msg.texto end
        end
      end
    end
  end

  local function desenhar()
    local cinza = colors.lightGray
    while true do
      cabecalho("TELEMETRIA")
      escrever(2, 2, sel.nome or ("#" .. sel.id), colors.yellow)
      if fim then
        escrever(2, 3, "VOO ENCERRADO: " .. fim, colors.red)
      elseif not T then
        escrever(2, 3, "Aguardando dados do missil...", cinza)
      end
      if T then
        if not fim then
          escrever(2, 3, "FASE: " .. tostring(T.fase), colors.yellow)
          escrever(24, 3, ("T+%.1fs"):format(T.t or 0))
          escrever(38, 3, T.armado and "ARMADO" or "desarmado", T.armado and colors.red or colors.lime)
        end
        if T.pos then
          escrever(2, 5, "Posicao", cinza)
          escrever(14, 5, ("%.0f %.0f %.0f"):format(T.pos.x, T.pos.y, T.pos.z))
        end
        if T.alvo then
          escrever(2, 6, "Alvo", cinza)
          escrever(14, 6, coords(T.alvo))
        end
        if T.dist then
          escrever(2, 7, "Distancia", cinza)
          escrever(14, 7, ("%.0f blocos  (horizontal %.0f)"):format(T.dist, T.distH or 0), colors.yellow)
        end
        local vel = T.vel or { n = 0, l = 0, y = 0 }
        local vh = math.sqrt(vel.n * vel.n + vel.l * vel.l)
        escrever(2, 8, "Velocidade", cinza)
        escrever(14, 8, ("%.1f b/s   vertical %.1f"):format(vh, vel.y))
        if T.distH and vh > 1 then
          escrever(2, 9, "Chegada", cinza)
          escrever(14, 9, ("~%.0f s"):format(T.distH / vh))
        end
        escrever(2, 10, "Inclinacao", cinza)
        escrever(14, 10, ("N %.1f  L %.1f   rumo %.0f"):format(T.n or 0, T.l or 0, T.psi or 0))
        escrever(2, 11, "Controle", cinza)
        escrever(14, 11, ("%.1f Hz   acelerador %d%%"):format(T.hz or 0,
          math.floor((T.acel or 0) * 100 + 0.5)), (T.hz or 0) >= 5 and colors.lime or colors.red)
        if dist0 and T.dist and dist0 > 0 then
          local larg = W - 4
          local cheio = math.floor(larg * clamp(1 - T.dist / dist0, 0, 1) + 0.5)
          escrever(2, 12, "[" .. string.rep("=", cheio) .. string.rep(" ", larg - cheio) .. "]", colors.orange)
        end
      end
      local semSinal = os.clock() - ultimo
      if not fim and T and semSinal > 3 then
        escrever(2, 13, ("SEM SINAL ha %ds (explodiu? fora de alcance?)"):format(math.floor(semSinal)), colors.red)
      end
      local y = 14
      for _, e in ipairs(eventos) do
        if y > H - 1 then break end
        escrever(2, y, tostring(e):sub(1, W - 2), cinza)
        y = y + 1
      end
      rodape(fim and "BACKSPACE volta" or "A = ABORTAR   BACKSPACE volta (voo continua)")
      sleep(0.25)
    end
  end

  local function teclas()
    while true do
      local _, k = os.pullEvent("key")
      if k == keys.backspace then return end
      if k == keys.a and not fim then
        for _ = 1, 3 do rednet.send(sel.id, { tipo = "abortar" }, PROTOCOLO) end
        table.insert(eventos, 1, "ABORTAR enviado")
        if #eventos > 5 then table.remove(eventos) end
      end
    end
  end

  parallel.waitForAny(receber, desenhar, teclas)
end

local function lancar()
  if not sel.id then
    aviso("LANCAR", { "Selecione um missil primeiro." }, colors.orange)
    return
  end
  if not alvo then
    aviso("LANCAR", { "Defina o alvo primeiro." }, colors.orange)
    return
  end

  cabecalho("LANCAR")
  escrever(2, 3, "Consultando o missil...", colors.yellow)
  local st = consultar(sel.id)
  if not st then
    aviso("LANCAR", { "O missil nao respondeu.",
      "Ele esta ligado em Modo remoto?" }, colors.red)
    return
  end
  if not st.pronto then
    aviso("LANCAR", { "Missil NAO PRONTO:", table.concat(st.problemas or {}, ", ") }, colors.red)
    return
  end

  cabecalho("CONFIRMAR LANCAMENTO")
  local cinza = colors.lightGray
  escrever(2, 3, "Missil", cinza)
  escrever(14, 3, st.nome or ("#" .. sel.id))
  escrever(2, 4, "Preset", cinza)
  escrever(14, 4, tostring(st.preset))
  escrever(2, 5, "Alvo", cinza)
  escrever(14, 5, ("%s  (%s)"):format(alvo.nome, coords(alvo)), colors.yellow)
  if st.pos then
    local dx, dz = alvo.x - st.pos.x, alvo.z - st.pos.z
    escrever(2, 6, "Distancia", cinza)
    escrever(14, 6, ("%d blocos"):format(math.floor(math.sqrt(dx * dx + dz * dz))))
  end

  local codigo
  local y = 8
  if st.precisaCodigo then
    codigo = perguntar(y, "Codigo de lancamento: ", nil, true)
    y = y + 2
  end
  escrever(2, y, "Digite LANCAR para confirmar:", colors.red)
  local r = perguntar(y + 1, "> ", nil)
  if not r or r:upper() ~= "LANCAR" then
    aviso("LANCAR", { "Lancamento cancelado." }, colors.orange)
    return
  end

  rednet.send(sel.id, { tipo = "lancar", alvo = { x = alvo.x, y = alvo.y, z = alvo.z },
    codigo = codigo }, PROTOCOLO)
  local resp = esperar(sel.id, { lancar_ok = true, lancar_negado = true }, 3)
  if not resp then
    aviso("LANCAR", { "Sem resposta do missil." }, colors.red)
    return
  end
  if resp.tipo == "lancar_negado" then
    aviso("LANCAMENTO NEGADO", { tostring(resp.motivo) }, colors.red)
    return
  end
  acompanhar()
end

---------------------------------------------------------------- MENU

local function principal()
  while true do
    local modem = abrirModem()
    local info = {
      { "Modem:  " .. (modem and "OK" or "NAO ENCONTRADO"), modem and colors.lime or colors.red },
      { "Missil: " .. (sel.id and (sel.nome or ("#" .. sel.id)) or "nenhum"),
        sel.id and colors.white or colors.orange },
      { "Alvo:   " .. (alvo and ("%s (%s)"):format(alvo.nome, coords(alvo)) or "nenhum"),
        alvo and colors.white or colors.orange },
    }
    local i = menu("BASE v" .. VERSAO, {
      "Procurar e selecionar missil",
      "Definir alvo (coordenada)",
      "Alvos salvos",
      "LANCAR",
      "Acompanhar voo / abortar",
      "Sair",
    }, info)
    if not i or i == 6 then return end

    if not modem then
      aviso("ERRO", { "Coloque um modem sem fio (Ender Modem) na base." }, colors.red)
    else
      local acoes = { procurar, definirAlvo, alvosSalvos, lancar, acompanhar }
      local ok, err = pcall(acoes[i])
      if not ok and err ~= "Terminated" then
        aviso("ERRO", { tostring(err) }, colors.red)
      end
    end
    salvarEstado()
  end
end

carregarEstado()
local ok, err = pcall(principal)
fundo(colors.black)
cor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok and err ~= "Terminated" then
  printError(err)
else
  print("BlockForge Militar - Base encerrada.")
end
]=] }

PROGRAMAS[#PROGRAMAS + 1] = { chave = "gps_torre", arquivo = "gps_torre.lua", titulo = "Torre de GPS", codigo = [=[
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
]=] }

local W, H = term.getSize()
local COR = term.isColor()
local function cor(c) if COR then term.setTextColor(c) end end
local function fundo(c) if COR then term.setBackgroundColor(c) end end

local function escrever(x, y, txt, c, bg)
  term.setCursorPos(x, y)
  if bg then fundo(bg) end
  cor(c or colors.white)
  term.write(txt)
  fundo(colors.black)
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
end

local function rodape(txt)
  fundo(colors.gray)
  term.setCursorPos(1, H)
  term.clearLine()
  cor(colors.white)
  term.write(" " .. txt)
  fundo(colors.black)
end

local function instalar(p)
  -- remove versoes antigas com e sem .lua
  local nome = p.arquivo:gsub("%.lua$", "")
  for _, velho in ipairs({ nome, p.arquivo }) do
    if fs.exists("/" .. velho) then fs.delete("/" .. velho) end
  end
  local f = fs.open("/" .. p.arquivo, "w")
  f.write(p.codigo)
  f.close()
  return nome
end

local function limparAntigos()
  for _, velho in ipairs({ "reto", "reto.lua", "calibrar", "calibrar.lua",
    "calibrar_gimbal", "calibrar_gimbal.lua", "vetor", "vetor.lua" }) do
    if fs.exists("/" .. velho) then fs.delete("/" .. velho) end
  end
end

local function concluir(p, nome)
  cabecalho("INSTALADO")
  escrever(2, 3, p.titulo .. " instalado!", colors.lime)
  escrever(2, 5, "Para abrir, digite:", colors.lightGray)
  escrever(4, 6, nome, colors.yellow)
  if p.chave == "gps_torre" then
    escrever(2, 8, "Na primeira vez ele pede a coordenada", colors.lightGray)
    escrever(2, 9, "deste computador e depois liga sozinho.", colors.lightGray)
  elseif p.chave == "missil" then
    escrever(2, 8, "Calibracao e presets antigos foram mantidos.", colors.lightGray)
  end
  rodape("ENTER abre agora   outra tecla sai")
  local _, k = os.pullEvent("key")
  fundo(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  if k == keys.enter then shell.run("/" .. p.arquivo) end
end

-- instalacao direta pelo argumento
if arg[1] then
  for _, p in ipairs(PROGRAMAS) do
    if p.chave == arg[1] then
      limparAntigos()
      local nome = instalar(p)
      print(p.titulo .. " instalado. Digite: " .. nome)
      return
    end
  end
  printError("Opcoes: missil, base, gps_torre")
  return
end

local sel = 1
while true do
  cabecalho("INSTALADOR")
  escrever(2, 3, "O que este computador vai ser?", colors.yellow)
  local ops = {}
  for _, p in ipairs(PROGRAMAS) do ops[#ops + 1] = p.titulo end
  ops[#ops + 1] = "Sair"
  for i, txt in ipairs(ops) do
    local linha = (i == sel and ">" or " ") .. i .. " " .. txt
    if i == sel then
      escrever(2, 4 + i, linha .. string.rep(" ", W - 2 - #linha), colors.black, colors.yellow)
    else
      escrever(2, 4 + i, linha)
    end
  end
  escrever(2, 11, "Instale um programa por computador:", colors.lightGray)
  escrever(2, 12, "  4+ torres, 1 base e 1 por missil.", colors.lightGray)
  rodape("SETAS/NUMERO escolhe   ENTER instala")

  local ev, p = os.pullEvent()
  local escolha
  if ev == "key" then
    if p == keys.up then sel = sel > 1 and sel - 1 or #ops
    elseif p == keys.down then sel = sel < #ops and sel + 1 or 1
    elseif p == keys.enter then escolha = sel end
  elseif ev == "char" and tonumber(p) then
    local n = tonumber(p)
    if n >= 1 and n <= #ops then escolha = n end
  end

  if escolha then
    if escolha == #ops then
      fundo(colors.black)
      term.clear()
      term.setCursorPos(1, 1)
      return
    end
    local prog = PROGRAMAS[escolha]
    limparAntigos()
    local nome = instalar(prog)
    concluir(prog, nome)
    return
  end
end
