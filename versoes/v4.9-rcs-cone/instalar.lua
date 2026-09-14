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

local VERSAO = "4.9"
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

---------------------------------------------------------------- ORIENTACAO 3D
-- Quaternions {x, y, z, w} que levam um vetor do corpo para o mundo.
-- Mundo: X = leste, Y = cima, Z = sul.

local function normalizar(x, y, z)
  local m = math.sqrt(x * x + y * y + z * z)
  if m < 1e-9 then return 0, 0, 0, 0 end
  return x / m, y / m, z / m, m
end

local function conjugar(q)
  return { x = -q.x, y = -q.y, z = -q.z, w = q.w }
end

-- produto a*b (aplica b, depois a)
local function multQuat(a, b)
  return {
    w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
  }
end

-- gira o vetor (x, y, z) pelo quaternion q
local function girar(q, x, y, z)
  local tx = 2 * (q.y * z - q.z * y)
  local ty = 2 * (q.z * x - q.x * z)
  local tz = 2 * (q.x * y - q.y * x)
  return x + q.w * tx + (q.y * tz - q.z * ty),
    y + q.w * ty + (q.z * tx - q.x * tz),
    z + q.w * tz + (q.x * ty - q.y * tx)
end

-- leva um vetor do mundo para o referencial do lancamento: o missil
-- "congelado" como estava em q0 (reto, virado como na calibracao)
local function paraLancamento(q, q0, x, y, z)
  local bx, by, bz = girar(conjugar(q), x, y, z)
  return girar(q0, bx, by, bz)
end

-- direcao do nariz no mundo (o nariz e o "cima" do missil em q0)
local function narizMundo(q, q0)
  local bx, by, bz = girar(conjugar(q0), 0, 1, 0)
  return girar(q, bx, by, bz)
end

-- inclinacao (graus) de um vetor em relacao a vertical: norte, leste
local function inclinacaoVetor(x, y, z)
  return math.deg(atan2(-z, y)), math.deg(atan2(x, y))
end

-- velocidade angular (rad/s, mundo) entre duas orientacoes
local function velAngular(q, qAnt, dt)
  local d = multQuat(q, conjugar(qAnt))
  if d.w < 0 then d = { x = -d.x, y = -d.y, z = -d.z, w = -d.w } end
  return 2 * d.x / dt, 2 * d.y / dt, 2 * d.z / dt
end

-- gira a direcao unitaria 'a' em direcao a 'b', no maximo maxAng radianos
local function aproximarDirecao(a, b, maxAng)
  local dot = clamp(a[1] * b[1] + a[2] * b[2] + a[3] * b[3], -1, 1)
  if math.acos(dot) <= maxAng then return { b[1], b[2], b[3] } end
  -- parte de b perpendicular a a (se forem opostos, usa um eixo qualquer)
  local px, py, pz = normalizar(b[1] - dot * a[1], b[2] - dot * a[2], b[3] - dot * a[3])
  if px == 0 and py == 0 and pz == 0 then
    px, py, pz = normalizar(a[2], -a[1], 0)
    if px == 0 and py == 0 and pz == 0 then px, py, pz = 1, 0, 0 end
  end
  local c, s = math.cos(maxAng), math.sin(maxAng)
  local x, y, z = normalizar(a[1] * c + px * s, a[2] * c + py * s, a[3] * c + pz * s)
  return { x, y, z }
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
  kp = 0.04, ki = 0, kd = 0.03, inverter = false,
  taxaIncl = 15, -- graus/s: rapidez maxima da inclinacao pedida pela navegacao
  controleGiro = true, kGiro = 0.15, inverterGiro = false,
  empuxoVetor = 1.0, empuxoMin = 0.3, acelerador = 1.0, usarSolidos = true,
  abortar = 60, contagem = 3,
  -- navegacao
  altCruzeiro = 40, altSaida = 15,
  velMax = 20, velSubida = 15, velDescida = 12,
  inclMax = 20, distAtaque = 12,
  kPos = 0.25, kVel = 1.5, kAlt = 0.5, kVz = 0.08, kiVz = 0.05, acelBase = 0.6,
  corrigirGiro = true, alcanceMax = 2000,
  -- guiagem de missil por apontamento (orientacao do sublevel)
  guiagemPose = true, conjugarQuat = false,
  qCal = {}, subId = "", -- orientacao e sublevel na calibracao do bocal
  taxaVirar = 25, inclAtaque = 45, navN = 3, kGuia = 0.5,
  -- ogiva e seguranca
  ladoOgiva = "top", raioDetonacao = 4, tempoArme = 5, distArme = 30,
  altDeton = 3, tempoMax = 180, impacto = true,
  -- RCS: motores solidos (Create Propulsion) no cone, para apontar o missil na
  -- QUEDA, quando os motores principais e os vector thrusters estao desligados.
  usarRcs = true, kRcs = 0.8,
  rcsMotores = {}, -- nome do motor solido -> lado (N/S/L/O) que ele inclina o nariz
  -- sistema
  codigo = "", soCifrado = true, iniciarRemoto = false,
  alvoX = 0, alvoY = 64, alvoZ = 0,
}

-- ajustes que aparecem com %d: precisam ser inteiros
local INTEIROS = {
  abortar = true, contagem = true, altCruzeiro = true, altSaida = true,
  distAtaque = true, alcanceMax = true, raioDetonacao = true,
  tempoArme = true, distArme = true, tempoMax = true, altDeton = true,
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

---------------------------------------------------------------- CRIPTOGRAFIA

-- [cripto-inicio]
-- SHA-256, HMAC e PBKDF2 em Lua puro (bit32 do CC: Tweaked).
local cripto = {}
do
  local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
  local rshift, rrotate = bit32.rshift, bit32.rrotate
  local M = 4294967296
  local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }

  function cripto.sha256(msg)
    local ml = #msg
    local bits = ml * 8
    local cauda = {}
    for i = 7, 0, -1 do cauda[#cauda + 1] = string.char(math.floor(bits / 2 ^ (8 * i)) % 256) end
    msg = msg .. "\128" .. string.rep("\0", (55 - ml) % 64) .. table.concat(cauda)
    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local w = {}
    for bloco = 1, #msg, 64 do
      for i = 0, 15 do
        local a, b, c, d = msg:byte(bloco + i * 4, bloco + i * 4 + 3)
        w[i] = ((a * 256 + b) * 256 + c) * 256 + d
      end
      for i = 16, 63 do
        local v, u = w[i - 15], w[i - 2]
        w[i] = (w[i - 16] + bxor(rrotate(v, 7), rrotate(v, 18), rshift(v, 3)) + w[i - 7]
          + bxor(rrotate(u, 17), rrotate(u, 19), rshift(u, 10))) % M
      end
      local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
      for i = 0, 63 do
        local t1 = (h + bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
          + bxor(band(e, f), band(bnot(e), g)) + K[i + 1] + w[i]) % M
        local t2 = (bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
          + bxor(band(a, b), band(a, c), band(b, c))) % M
        h, g, f, e, d, c, b, a = g, f, e, (d + t1) % M, c, b, a, (t1 + t2) % M
      end
      h0, h1, h2, h3 = (h0 + a) % M, (h1 + b) % M, (h2 + c) % M, (h3 + d) % M
      h4, h5, h6, h7 = (h4 + e) % M, (h5 + f) % M, (h6 + g) % M, (h7 + h) % M
    end
    local out = {}
    for _, v in ipairs({ h0, h1, h2, h3, h4, h5, h6, h7 }) do
      out[#out + 1] = string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256,
        math.floor(v / 256) % 256, v % 256)
    end
    return table.concat(out)
  end

  -- a e b com o mesmo tamanho
  function cripto.xor(a, b)
    local r = {}
    for i = 1, #a do r[i] = string.char(bxor(a:byte(i), b:byte(i))) end
    return table.concat(r)
  end

  function cripto.hmac(chave, msg)
    if #chave > 64 then chave = cripto.sha256(chave) end
    chave = chave .. string.rep("\0", 64 - #chave)
    local dentro = cripto.xor(chave, string.rep("\54", 64))
    local fora = cripto.xor(chave, string.rep("\92", 64))
    return cripto.sha256(fora .. cripto.sha256(dentro .. msg))
  end

  -- PBKDF2-HMAC-SHA256 com 32 bytes; cede a vez de tempos em tempos
  function cripto.derivar(senha, sal, voltas)
    local u = cripto.hmac(senha, sal .. "\0\0\0\1")
    local r = u
    for i = 2, voltas do
      u = cripto.hmac(senha, u)
      r = cripto.xor(r, u)
      if i % 32 == 0 then
        os.queueEvent("bfm_cripto")
        os.pullEvent("bfm_cripto")
      end
    end
    return r
  end

  function cripto.hex(s)
    return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
  end

  function cripto.deHex(h)
    if type(h) ~= "string" or #h % 2 == 1 or h:find("[^%x]") then return nil end
    return (h:gsub("%x%x", function(p) return string.char(tonumber(p, 16)) end))
  end

  -- compara sem parar no primeiro byte diferente
  function cripto.igual(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
    local d = 0
    for i = 1, #a do d = bor(d, bxor(a:byte(i), b:byte(i))) end
    return d == 0
  end

  -- bytes imprevisiveis: relogios, sorteio e enderecos de memoria misturados no SHA-256
  local reserva, contador = "", 0
  function cripto.aleatorio(n)
    local out, tam = {}, 0
    while tam < n do
      contador = contador + 1
      reserva = cripto.sha256(table.concat({ reserva, tostring(os.epoch and os.epoch("utc") or 0),
        tostring(os.clock()), tostring(math.random()), tostring(os.getComputerID()),
        tostring(contador), tostring({}) }, "|"))
      out[#out + 1] = reserva
      tam = tam + 32
    end
    return table.concat(out):sub(1, n)
  end
end

-- mensagem assinada na ordem de lancamento (base e missil montam igual)
local function mensagemLancar(nonce, alvo, idBase)
  return ("BFM-LANCAR|%s|%.2f|%.2f|%.2f|%d"):format(nonce, alvo.x, alvo.y, alvo.z, idBase)
end
-- [cripto-fim]

---------------------------------------------------------------- PERIFERICOS

local TIPOS_VETOR = { "vector_thruster", "liquid_vector_thruster", "creative_vector_thruster" }
local TIPOS_MOTOR = {
  { tipo = "solid_fuel_thruster", classe = "solido",   rotulo = "SOL" },
  { tipo = "thruster",            classe = "liquido",  rotulo = "LIQ" },
  { tipo = "ion_thruster",        classe = "ion",      rotulo = "ION" },
  { tipo = "creative_thruster",   classe = "criativo", rotulo = "CRI" },
}

local P = { vetores = {}, motores = {}, rcs = {}, relays = {} }

local function temTipo(nome, lista)
  for _, t in ipairs(lista) do
    if peripheral.hasType(nome, t) then return true end
  end
  return false
end

local function detectar()
  P = { gimbal = nil, drive = nil, modem = nil, altimetro = nil, vetores = {}, motores = {},
    rcs = {}, relays = {} }
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
    elseif peripheral.hasType(nome, "altitude_sensor") then
      P.altimetro = P.altimetro or peripheral.wrap(nome)
    elseif temTipo(nome, TIPOS_VETOR) then
      table.insert(P.vetores, { nome = nome, p = peripheral.wrap(nome) })
    elseif peripheral.hasType(nome, "redstone_relay") then
      table.insert(P.relays, nome)
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
  -- separa os motores solidos marcados como RCS (no cone): saem da lista de
  -- propulsao e ganham a direcao {tn, tl} para onde inclinam o nariz.
  local principais = {}
  for _, m in ipairs(P.motores) do
    local lado = m.classe == "solido" and cfg.rcsMotores[m.nome]
    local d = lado and LADO_VETOR[lado]
    if d and (d[1] ~= 0 or d[2] ~= 0) then
      table.insert(P.rcs, { nome = m.nome, m = m, tn = d[1], tl = d[2] })
    else
      table.insert(principais, m)
    end
  end
  P.motores = principais
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
  if not pcall(m.p.setPowerNormalized, pot) then pcall(m.p.setPower, math.floor(pot * 15 + 0.5)) end
end

-- Cada chamada a periferico espera o proximo tick do jogo (0,05 s).
-- Disparando todas juntas com parallel.waitForAll elas cabem num tick so.

-- x, y: inclinacao igual para todos os bocais
-- giro: forca tangencial para frear a rotacao (cada motor inclina de lado)
-- adiciona em 'tarefas' uma chamada setVector por motor
local function tarefasVetor(tarefas, x, y, giro)
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
    table.insert(tarefas, function() pcall(v.p.setVector, vx, vy) end)
  end
  return tarefas
end

local function vetorComando(x, y, giro)
  local tarefas = tarefasVetor({}, x, y, giro)
  if #tarefas > 0 then parallel.waitForAll(table.unpack(tarefas)) end
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
  local tarefas = {}
  for _, v in ipairs(P.vetores) do
    table.insert(tarefas, function()
      if not pcall(v.p.setThrustNormalized, pot) then
        pcall(v.p.setPowerNormalized, pot)
      end
    end)
  end
  if #tarefas > 0 then parallel.waitForAll(table.unpack(tarefas)) end
end

-- RCS: motores solidos (Create Propulsion) montados no cone, apontando para fora.
-- Disparar um empurra o missil pelo lado oposto e INCLINA o nariz para o lado {tn, tl}
-- (mapeado na calibracao). Como sao motores comuns, o computador os liga direto com
-- setPowerNormalized -- sem warhead nem redstone. Servem para apontar o missil na
-- QUEDA, quando os motores principais e os vector thrusters estao desligados (sem
-- empuxo saindo, o vector thruster nao consegue mais virar o missil).

local function rcsDesligar()
  for _, e in ipairs(P.rcs) do acelerar(e.m, 0) end
end

-- comando de atitude (cN, cL em -1..1 = inclinar o nariz para +Norte / +Leste):
-- cada RCS recebe potencia proporcional a quanto ele empurra nessa direcao.
-- Devolve a soma das potencias (0 = parado).
local function rcsAtitude(cN, cL)
  local tarefas, soma = {}, 0
  for _, e in ipairs(P.rcs) do
    local pot = clamp(cfg.kRcs * (cN * e.tn + cL * e.tl), 0, 1)
    soma = soma + pot
    table.insert(tarefas, function() acelerar(e.m, pot) end)
  end
  if #tarefas > 0 then parallel.waitForAll(table.unpack(tarefas)) end
  return soma
end

-- quantos RCS ainda tem combustivel (motor solido carregado ou queimando)
local function rcsComCombustivel()
  local n = 0
  for _, e in ipairs(P.rcs) do
    if (chamar(e.m.p, "getFuelAmount") or 0) > 0 or chamar(e.m.p, "isBurning") == true then
      n = n + 1
    end
  end
  return n
end

local function desligarTudo()
  for _, m in ipairs(P.motores) do acelerar(m, 0) end
  vetorComando(0, 0)
  vetorEmpuxo(0)
  rcsDesligar()
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

-- orientacao do sublevel (quaternion corpo -> mundo) e o tamanho lido.
-- O CC: Sable entrega um objeto do CC: Advanced Math: campos v (x,y,z) e a (w).
local function sublevelOrientacao()
  if type(sublevel) ~= "table" or type(sublevel.getLogicalPose) ~= "function" then return nil end
  local ok, pose = pcall(sublevel.getLogicalPose)
  if not ok or type(pose) ~= "table" or type(pose.orientation) ~= "table" then return nil end
  local o = pose.orientation
  local x, y, z, w
  if type(o.v) == "table" then
    x, y, z, w = o.v.x, o.v.y, o.v.z, o.a
  else
    x, y, z, w = o.x, o.y, o.z, o.w
  end
  if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(w) ~= "number" then
    return nil
  end
  local len = math.sqrt(x * x + y * y + z * z + w * w)
  if len < 0.9 or len > 1.1 then return nil, len end
  local q = { x = x / len, y = y / len, z = z / len, w = w / len }
  if cfg.conjugarQuat then q = conjugar(q) end
  return q, len
end

-- velocidade linear do sublevel (mundo); so e usada depois de conferida com a posicao
local function velocidadeSublevel()
  if type(sublevel) ~= "table" or type(sublevel.getLinearVelocity) ~= "function" then return nil end
  local ok, v = pcall(sublevel.getLinearVelocity)
  if ok and type(v) == "table" and type(v.x) == "number" and type(v.y) == "number"
    and type(v.z) == "number" then
    return v
  end
end

local function idSublevel()
  if type(sublevel) ~= "table" or type(sublevel.getUniqueId) ~= "function" then return "" end
  local ok, id = pcall(sublevel.getUniqueId)
  return ok and type(id) == "string" and id or ""
end

-- metodos do Create: Avionics que devolvem {x, y, z} (tabela ou 3 valores)
local function lerVetor(p, metodo)
  if not p or type(p[metodo]) ~= "function" then return nil end
  local r = { pcall(p[metodo]) }
  if type(r[2]) == "table" then r = { r[1], r[2][1], r[2][2], r[2][3] } end
  if r[1] and type(r[2]) == "number" and type(r[3]) == "number" and type(r[4]) == "number" then
    return r[2], r[3], r[4]
  end
end

-- gravidade (blocos/s^2): API aero do CC: Sable, gimbal do Create: Avionics, ou 11
local function gravidade()
  if type(aero) == "table" and type(aero.getGravity) == "function" then
    local ok, g = pcall(aero.getGravity)
    if ok and type(g) == "table" then g = g.y end
    if ok and type(g) == "number" and g ~= 0 then return clamp(math.abs(g), 2, 40) end
  end
  local x, y, z = lerVetor(P.gimbal, "getGravity")
  if x and x * x + y * y + z * z > 1 then return clamp(math.sqrt(x * x + y * y + z * z), 2, 40) end
  return 11
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
    auth = 1, contagem = cfg.contagem,
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
  cfg.qCal = sublevelOrientacao() or {}
  cfg.subId = idSublevel()
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

---------------------------------------------------------------- CALIBRAR RCS

-- Marca quais motores solidos sao RCS do cone e para que lado cada um inclina o
-- nariz. Pulsa cada motor solido; o jogador ve para onde o NARIZ inclinou.
local function calibrarRcs()
  if not exigir(false) then return end
  if not cfg.bocalOk then
    aviso("RCS", { "Calibre o bocal antes." }, colors.orange)
    return
  end
  -- candidatos: todos os motores solidos (os ja marcados como RCS voltam para a lista)
  local solidos = {}
  for _, m in ipairs(P.motores) do
    if m.classe == "solido" then table.insert(solidos, m) end
  end
  for _, e in ipairs(P.rcs) do table.insert(solidos, e.m) end
  if #solidos == 0 then
    aviso("RCS", { "Nenhum motor solido encontrado.",
      "Os RCS sao motores solidos montados no cone, apontando para fora." }, colors.orange)
    return
  end
  for _, m in ipairs(solidos) do acelerar(m, 0) end

  local novo = {}
  for i, m in ipairs(solidos) do
    cabecalho(("RCS %d/%d"):format(i, #solidos))
    escrever(2, 3, "Um motor solido vai PULSAR agora.", colors.yellow)
    escrever(2, 4, "Para que lado o NARIZ inclinou?", colors.yellow)
    escrever(2, 6, "N Norte   S Sul   L Leste   O Oeste")
    escrever(2, 7, "C ou ENTER = nao e RCS (motor principal)")
    escrever(2, 9, "Missil na mesma posicao da calibracao!", colors.lightGray)
    escrever(2, 10, "Motor: " .. m.nome, colors.lightGray)
    escrever(2, 11, ("Marcados ate agora: %d"):format((function()
      local n = 0 for _ in pairs(novo) do n = n + 1 end return n end)()), colors.lightGray)
    rodape("N/S/L/O escolhe   C/ENTER pula   BACKSPACE cancela")

    local escolha, cancelou
    parallel.waitForAny(function()
      local ligado = true
      while true do
        acelerar(m, ligado and 1 or 0)
        ligado = not ligado
        sleep(0.4)
      end
    end, function()
      while true do
        local ev, p = os.pullEvent()
        if ev == "char" and LADO_VETOR[p:upper()] and p:upper() ~= "C" then
          escolha = p:upper()
          return
        elseif ev == "char" and p:upper() == "C" then
          return
        elseif ev == "key" and p == keys.enter then
          return
        elseif ev == "key" and p == keys.backspace then
          cancelou = true
          return
        end
      end
    end)
    acelerar(m, 0)
    if cancelou then return end
    if escolha then novo[m.nome] = escolha end
  end

  cfg.rcsMotores = novo
  salvarConfig()
  detectar()
  local linhas, temNS, temLO = {}, false, false
  for nome, lado in pairs(novo) do
    if lado == "N" or lado == "S" then temNS = true end
    if lado == "L" or lado == "O" then temLO = true end
    table.insert(linhas, ("%-26s inclina p/ %s"):format(nome:sub(1, 26), lado))
  end
  if #linhas == 0 then
    aviso("RCS", { "Nenhum motor marcado: o RCS fica desligado no voo.",
      "Sem RCS, o missil nao consegue apontar na queda." }, colors.orange)
    return
  end
  table.insert(linhas, "")
  if temNS and temLO then
    table.insert(linhas, "Cobre os dois eixos. Pronto para a queda guiada.")
  else
    table.insert(linhas, "ATENCAO: falta RCS no eixo " .. (temNS and "leste/oeste." or "norte/sul."))
  end
  aviso("RCS SALVO", linhas, (temNS and temLO) and colors.lime or colors.orange)
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
    alvoN = 0, alvoL = 0, psi = 0, incMax = 0, wy = 0, mapeados = 0, ix = 0, iy = 0,
    errAng = 0,
    acel = cfg.acelerador, integral = cfg.acelBase,
    vel = { n = 0, l = 0, y = 0 }, eventos = {},
  }

  local function evento(txt)
    if S.log then S.log.writeLine(("# %.1f %s"):format(os.clock() - S.inicio, txt)) end
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
    -- guiagem por apontamento: precisa da orientacao completa do sublevel
    S.modoPose = cfg.guiagemPose and sublevelOrientacao() ~= nil
    S.gravidade = gravidade()
  end

  local ativos = {}
  for _, m in ipairs(P.motores) do
    if m.classe ~= "solido" or cfg.usarSolidos then table.insert(ativos, m) end
  end
  local rcsAtivo = guiado and cfg.usarRcs and #P.rcs > 0
  local rcsComb = rcsAtivo and rcsComCombustivel() or 0
  rcsDesligar()

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
      item(7, "Guiagem", S.modoPose and "apontamento (sublevel)" or "inclinacao (gimbal)",
        S.modoPose)
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
    if guiado and cfg.usarRcs then
      item(14, "RCS cone / comb", ("%d / %d"):format(#P.rcs, rcsComb),
        rcsAtivo and rcsComb == #P.rcs)
    end
    if #ativos == 0 then
      escrever(2, 15,"Nenhum motor principal: so o vetor empurra.", colors.orange)
    end
    if contar("solido") > 0 and cfg.usarSolidos then
      escrever(2, 16, "Solidos NAO apagam depois de acesos!", colors.orange)
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

  -- referencia da orientacao: o missil reto como na calibracao do bocal
  -- (mesmo sublevel), senao como esta na plataforma
  if S.modoPose then
    S.q0 = sublevelOrientacao()
    if not S.q0 then
      S.modoPose = false
      evento("Sem orientacao do sublevel: guiagem pelo gimbal")
    elseif cfg.qCal.w and cfg.subId == idSublevel() then
      S.q0 = cfg.qCal
    else
      evento("Sublevel diferente da calibracao: deixe o missil virado como nela")
    end
  end

  -- acelerometro (Create: Avionics): parado ele mede a gravidade ao contrario,
  -- na direcao do nariz. Em voo, a leitura nessa direcao e o empuxo.
  if guiado then
    local ax, ay, az = lerVetor(P.gimbal, "getLinearAcceleration")
    local m = ax and math.sqrt(ax * ax + ay * ay + az * az) or 0
    if math.abs(m - S.gravidade) < 0.3 * S.gravidade then S.acelNariz = { ax / m, ay / m, az / m } end
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
  -- gravador de voo: /voo.csv, salvo no disco a cada 1 s
  if guiado then
    S.log = fs.open("/voo.csv", "w")
    if S.log then
      S.log.writeLine("t,fase,modo,x,y,z,vx,vy,vz,fonteVel,narizX,narizY,narizZ,dirX,dirY,dirZ,erro,empuxo,g,bocalX,bocalY,hz,dist,giro,pedido,aMin,aMax,queda,tgo,solidos,rcs")
    end
  end
  evento("IGNICAO")

  local function detonar(txt)
    S.detonou = true
    S.motivo = "DETONACAO: " .. txt
    ogiva(true)
    evento(S.motivo)
  end

  -- As chamadas a perifericos descartam eventos enquanto esperam o jogo,
  -- entao o voo roda em tarefas paralelas, cada uma com seu proprio sleep.

  -- TAREFA: estabilizacao PID (gimbal ou orientacao do sublevel + vetor)
  local function controle()
    local n0, l0 = lerAngulos()
    local t0 = os.clock()
    local ciclos, tHz = 0, t0
    local envio = nil          -- comando calculado no ciclo anterior {x, y, giro}
    local ultX, ultY, ultG     -- ultimo comando enviado aos bocais
    local rnF, rlF = 0, 0      -- velocidade de inclinacao filtrada
    local iX, iY = 0, 0        -- integral do PID (graus * s)
    local refN, refL = 0, 0    -- inclinacao pedida, com rapidez limitada
    local qAnt, semQ, ultAng   -- apontamento: orientacao anterior, tempo sem ela, ultimo erro
    local erroAlto = 0         -- tempo com erro de apontamento grande
    S.dirCmd = { 0, 1, 0 }
    while true do
      -- Um tick por ciclo: le o gimbal e o giro (ou a orientacao) e envia o
      -- comando do ciclo anterior, tudo junto. Assim o controle roda a ate 20 Hz.
      local n, l, wy, q
      local modoPose = S.modoPose and S.q0 ~= nil
      local tarefas = { function() n, l = lerAngulos() end }
      if modoPose then
        table.insert(tarefas, function() q = sublevelOrientacao() end)
      else
        table.insert(tarefas, function() wy = giroVertical() end)
      end
      if envio then
        tarefasVetor(tarefas, envio[1], envio[2], envio[3])
        ultX, ultY, ultG = envio[1], envio[2], envio[3]
        envio = nil
      end
      parallel.waitForAll(table.unpack(tarefas))
      local t = os.clock()
      if t - t0 < 0.025 then
        -- as chamadas nao esperaram o jogo: garante um tick por ciclo
        sleep(0)
        t = os.clock()
      end
      local dt = math.max(t - t0, 0.05)
      local rn, rl = (n - n0) / dt, (l - l0) / dt
      n0, l0, t0 = n, l, t

      local ang
      if modoPose then
        if q then
          semQ = 0
          -- nariz e velocidade angular no referencial do lancamento
          local nx, ny, nz = narizMundo(q, S.q0)
          local pn, pl = inclinacaoVetor(nx, ny, nz)
          S.nariz = { nx, ny, nz }
          rn, rl = 0, 0
          if qAnt then
            local wx, wv, wz = velAngular(q, qAnt, dt)
            local lx, _, lz = paraLancamento(q, S.q0, wx, wv, wz)
            rn, rl = -math.deg(lx), -math.deg(lz)
            wy = wx * nx + wv * ny + wz * nz -- giro em torno do nariz
          end
          qAnt = q

          -- direcao pedida pela navegacao, virando no maximo taxaVirar graus/s
          if S.dirDes then
            S.dirCmd = aproximarDirecao(S.dirCmd, S.dirDes, math.rad(cfg.taxaVirar) * dt)
          end
          -- erro: angulo entre o nariz e a direcao pedida, em norte/leste
          local dx, dy, dz = paraLancamento(q, S.q0, S.dirCmd[1], S.dirCmd[2], S.dirCmd[3])
          local h = math.sqrt(dx * dx + dz * dz)
          local erro = math.deg(atan2(h, dy))
          if h > 1e-6 then
            ang = { erro * dz / h, -erro * dx / h }
          else
            ang = { dy < 0 and -erro or 0, 0 }
          end
          ultAng, S.errAng = ang, erro
          n, l = pn, pl

          if erro > 60 then erroAlto = erroAlto + dt else erroAlto = 0 end
          if erroAlto > 3 then
            S.motivo = ("ABORTADO: descontrole (erro de %.0f graus)"):format(erro)
            return
          end
        else
          -- leitura falhou: mantem o ultimo erro por 1 s, depois segura o missil
          -- reto pelo gimbal ate a orientacao voltar; aborta apos 5 s
          semQ, qAnt = (semQ or 0) + dt, nil
          if semQ > 5 then
            S.motivo = "ABORTADO: orientacao do sublevel perdida"
            return
          elseif semQ <= 1 then
            rn, rl = rnF, rlF
            ang = ultAng or { 0, 0 }
            n, l = S.n, S.l
          end
        end
        S.incMax = math.max(S.incMax, math.abs(n), math.abs(l))
      end
      rnF = rnF + 0.5 * (rn - rnF)
      rlF = rlF + 0.5 * (rl - rlF)

      if not ang then
        local inc = math.max(math.abs(n), math.abs(l))
        S.incMax = math.max(S.incMax, inc)
        if not modoPose and inc > cfg.abortar then
          S.motivo = ("ABORTADO: inclinacao de %.0f graus"):format(inc)
          return
        end

        -- inclinacao pedida pela navegacao, mudando no maximo taxaIncl graus/s
        local passo = cfg.taxaIncl * dt
        refN = refN + clamp(S.alvoN - refN, -passo, passo)
        refL = refL + clamp(S.alvoL - refL, -passo, passo)
        ang = { n - refN, l - refL }
      end

      -- PID: erro = inclinacao atual - inclinacao pedida
      local giro = { rnF, rlF }
      local inv = cfg.inverter and -1 or 1
      local tx = ang[cfg.eixoX] * cfg.sinalX
      local ty = ang[cfg.eixoY] * cfg.sinalY
      local gx = giro[cfg.eixoX] * cfg.sinalX
      local gy = giro[cfg.eixoY] * cfg.sinalY
      -- PD em cascata: o erro pede uma velocidade de giro de no maximo taxaVirar
      -- graus/s e o KD corrige a diferenca. Assim o missil nunca gira mais rapido
      -- do que consegue frear (com KD = 0 e o PD comum).
      local function pid(e, i, d)
        if cfg.kd > 0 then
          d = d + clamp(cfg.kp / cfg.kd * e, -cfg.taxaVirar, cfg.taxaVirar)
          return -inv * (cfg.kd * d + cfg.ki * i)
        end
        return -inv * (cfg.kp * e + cfg.ki * i)
      end
      -- integral limitada a 30% do bocal e congelada com o bocal no limite
      if cfg.ki > 0 then
        local lim = 0.3 / cfg.ki
        if math.abs(pid(tx, iX, gx)) < 1 then iX = clamp(iX + tx * dt, -lim, lim) end
        if math.abs(pid(ty, iY, gy)) < 1 then iY = clamp(iY + ty * dt, -lim, lim) end
      else
        iX, iY = 0, 0
      end
      local cx = lim1(pid(tx, iX, gx))
      local cy = lim1(pid(ty, iY, gy))
      S.ix, S.iy = cfg.ki * iX, cfg.ki * iY

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

      -- envia no proximo ciclo, junto com a proxima leitura, se mudou
      if not ultX or math.abs(cx - ultX) > 0.01 or math.abs(cy - ultY) > 0.01
        or math.abs(g - ultG) > 0.01 then
        envio = { cx, cy, g }
      end

      -- RCS do cone: na QUEDA os motores e os vetores estao desligados, entao
      -- a atitude (apontar o nariz) vem dos motores solidos do cone. Comando na
      -- mesma escala do bocal, no referencial Norte/Leste (sem o sinal do bocal).
      if S.rcsAtit and modoPose and ang and #P.rcs > 0 then
        local function pidNL(e, dr)
          if cfg.kd > 0 then
            return -(cfg.kd * (dr + clamp(cfg.kp / cfg.kd * e, -cfg.taxaVirar, cfg.taxaVirar)))
          end
          return -(cfg.kp * e)
        end
        S.rcsNivel = rcsAtitude(lim1(pidNL(ang[1], rnF)), lim1(pidNL(ang[2], rlF)))
      elseif not S.rcsAtit and S.rcsNivel then
        rcsDesligar()
        S.rcsNivel = nil
      end

      S.n, S.l, S.cx, S.cy = n, l, cx, cy
      S.giro = math.max(math.abs(rnF), math.abs(rlF))
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
    local uVn, uVl, uVy, velConf, ultFlush = 0, 0, 0, 0, os.clock()
    local velAnt = 0
    local jT, jVn, jVl, sCN, sCL, nC = os.clock(), 0, 0, 0, 0, 0
    local ultAcel, ultVet = -1, -1
    local fatorIncl = 1 -- < 1 quando falta empuxo para segurar a altura

    -- acelerador (0-1): motores liquidos comuns e os vector thrusters.
    -- O vetor fica entre empuxoMin e empuxoVetor: sem empuxo o bocal
    -- nao consegue manter o missil reto.
    local function acelerador(u)
      S.acel = u
      if math.abs(u - ultAcel) >= 0.02 then
        for _, m in ipairs(P.motores) do
          if m.classe ~= "solido" then acelerar(m, u) end
        end
        ultAcel = u
      end
      local lo = math.min(cfg.empuxoMin, cfg.empuxoVetor)
      local hi = math.max(cfg.empuxoMin, cfg.empuxoVetor)
      local uv = lo + (hi - lo) * u
      if math.abs(uv - ultVet) >= 0.02 then
        vetorEmpuxo(uv)
        ultVet = uv
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
        local vs = velocidadeSublevel()
        if vs and S.fonteVel == "sublevel" then
          vn, vl, vy = -vs.z, vs.x, vs.y
        else
          vn = vn + 0.5 * (rVn - vn)
          vl = vl + 0.5 * (rVl - vl)
          vy = vy + 0.5 * (rVy - vy)
          -- a velocidade do sublevel so e usada depois de bater 5 vezes com a posicao
          if vs and velBruta > 3 then
            local e = math.sqrt((vs.x - vl) ^ 2 + (vs.y - vy) ^ 2 + (vs.z + vn) ^ 2)
            velConf = e < 0.35 * velBruta and velConf + 1 or 0
            if velConf >= 5 then S.fonteVel = "sublevel" end
          end
          if P.altimetro then vy = chamar(P.altimetro, "getVerticalSpeed") or vy end
        end
        -- empuxo (por massa) na direcao do nariz: acelerometro ou variacao da velocidade
        if S.modoPose then
          local aN
          if S.acelNariz then
            local ax, ay, az = lerVetor(P.gimbal, "getLinearAcceleration")
            if ax then aN = ax * S.acelNariz[1] + ay * S.acelNariz[2] + az * S.acelNariz[3] end
          elseif S.nariz then
            aN = ((vl - uVl) * S.nariz[1] + (vy - uVy) * S.nariz[2] - (vn - uVn) * S.nariz[3]) / dt
              + S.gravidade * S.nariz[2]
          end
          -- ignora picos (colisao, travada da fisica)
          if aN and aN > 0 and aN < 3 * S.gravidade then
            S.empuxo = S.empuxo and S.empuxo + 0.35 * (aN - S.empuxo) or aN
          end
        end
        uVn, uVl, uVy = vn, vl, vy
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
          -- GATILHO PRINCIPAL: cruzou a altura de detonacao acima do alvo descendo.
          -- E o momento em que a ogiva SABE que esta em cima do alvo. Interpola o
          -- ponto exato entre as duas leituras para pegar o erro horizontal ali.
          local a0 = S.posAnt or p
          local hDet = alvo.y + cfg.altDeton
          if vy < 0 and a0.y > hDet and p.y <= hDet and a0.y > p.y then
            local fr = (a0.y - hDet) / (a0.y - p.y)
            local px = a0.x + (p.x - a0.x) * fr
            local pz = a0.z + (p.z - a0.z) * fr
            detonar(("altura %d (erro %.1f b)"):format(cfg.altDeton, mag(alvo.x - px, alvo.z - pz)))
            return
          end
          -- reserva: menor distancia ao alvo no trecho desde a ultima leitura
          -- (acerta mesmo rapido demais para cair dentro do raio numa leitura)
          local sx, sy, sz = p.x - a0.x, p.y - a0.y, p.z - a0.z
          local s2 = sx * sx + sy * sy + sz * sz
          local k = s2 > 0 and clamp(((alvo.x - a0.x) * sx + (alvo.y - a0.y) * sy + (alvo.z - a0.z) * sz) / s2, 0, 1) or 0
          local _, _, _, dMin = normalizar(a0.x + k * sx - alvo.x, a0.y + k * sy - alvo.y, a0.z + k * sz - alvo.z)
          if dMin <= cfg.raioDetonacao then detonar("alvo atingido") return end
          if cfg.impacto and velAnt > 8 and velBruta < 1.5 then detonar("impacto") return end
          if cfg.tempoMax > 0 and tv >= cfg.tempoMax then detonar("tempo maximo") return end
        elseif cfg.tempoMax > 0 and tv >= cfg.tempoMax then
          S.motivo = "Tempo maximo (ogiva desarmada)"
          return
        end
        velAnt, S.posAnt = velBruta, p

        local tn, tl = 0, 0
        if S.modoPose then
          -- MISSIL POR APONTAMENTO: o nariz aponta para onde o empuxo deve empurrar
          -- e a tarefa gerenciarMotores entrega o empuxo pedido (S.pedido).
          local fase = S.fase
          if fase == "DECOLAGEM" and p.y - o.y >= cfg.altSaida then fase = "SUBIDA" end
          if fase == "SUBIDA" and p.y >= S.cruzeiroY - 3 then fase = "CRUZEIRO" end
          -- CRUZEIRO -> QUEDA quando comeca a descer: aqui os motores principais
          -- e os vector thrusters sao CORTADOS e o missil cai balistico, apontado
          -- pelos RCS do cone e corrigido so com pulsos curtos de motor.
          if fase == "CRUZEIRO" and vy < -1 then fase = "QUEDA" end
          if fase ~= S.fase then
            S.fase = fase
            evento("FASE: " .. fase)
            if fase == "QUEDA" and rcsAtivo then
              S.rcsAtit = true
              evento("MOTORES CORTADOS: RCS no comando")
            end
          end
          -- so corta os motores (queda balistica) se houver RCS para apontar o
          -- missil; sem RCS, mantem a guiagem com empuxo como antes (nao tomba).
          local coast = fase == "QUEDA" and rcsAtivo

          if S.aMax and fase ~= "DECOLAGEM" and not coast then
            if not S.fraco and S.aMax < S.gravidade then
              S.fraco = true
              evento(("EMPUXO INSUFICIENTE: %.1f < gravidade %.1f"):format(S.aMax, S.gravidade))
            elseif S.aMax > 1.1 * S.gravidade then
              S.fraco = false
            end
          end
          local g, vx, vz = S.gravidade, vl, -vn
          local _, _, _, sp = normalizar(vx, vy, vz)
          local fx, fy, fz -- empuxo pedido (blocos/s^2, mundo)
          if fase == "DECOLAGEM" or fase == "SUBIDA" then
            -- sobe reto na velocidade de subida, freando o que escorregar de lado
            fx, fy, fz = -cfg.kGuia * vx, math.max(g + cfg.kGuia * (cfg.velSubida - vy), 0.5 * g), -cfg.kGuia * vz
          else
            -- BALISTICA (CRUZEIRO/QUEDA): simula o voo daqui em diante com o nariz na
            -- velocidade ate cruzar a altura do alvo. Na QUEDA os motores estao cortados,
            -- entao a simulacao usa empuxo zero (queda livre pura) e assim ve o erro real.
            local aMin = coast and 0 or (S.aMin or 0)
            local qx, qy, qz, ux, uy, uz, tgo = p.x, p.y, p.z, vx, vy, vz, 0
            while tgo < 90 and not (uy < 0 and qy <= alvo.y) do
              local _, _, _, su = normalizar(ux, uy, uz)
              local k = su > 1e-6 and aMin / su or 0
              local ax, ay, az = ux * k, uy * k - g, uz * k
              qx, qy, qz = qx + (ux + 0.05 * ax) * 0.1, qy + (uy + 0.05 * ay) * 0.1, qz + (uz + 0.05 * az) * 0.1
              ux, uy, uz = ux + ax * 0.1, uy + ay * 0.1, uz + az * 0.1
              tgo = tgo + 0.1
            end
            if uy < 0 and qy <= alvo.y then
              local tr = (qy - alvo.y) / uy
              qx, qz, tgo = qx - ux * tr, qz - uz * tr, tgo - tr
            else
              qx, qz, tgo = p.x, p.z, math.max(dist / math.max(sp, 5), 2)
            end
            -- erro de queda (ZEM): quanto erra se nao corrigir mais nada.
            local zx, zz = alvo.x - qx, alvo.z - qz
            S.erroQueda, S.tgo = mag(zx, zz), tgo
            local c = cfg.navN / math.max(tgo, 1) ^ 2
            local wx, wy, wz = vx / math.max(sp, 1e-6), vy / math.max(sp, 1e-6), vz / math.max(sp, 1e-6)
            if sp < 1 then wx, wy, wz = 0, 1, 0 end
            local ap = (zx * wx + zz * wz) * c
            local ox, oy, oz = zx * c - ap * wx, -ap * wy, zz * c - ap * wz
            local _, _, _, mo = normalizar(ox, oy, oz)
            local al = math.max(aMin + ap, aMin, mo / math.tan(math.rad(cfg.inclAtaque)))
            fx, fy, fz = al * wx + ox, al * wy + oy, al * wz + oz
            if coast then
              -- QUEDA: aponta o nariz para corrigir e so PULSA o motor quando o erro
              -- previsto vale a pena e ainda ha tempo. Sem pulso, empuxo pedido = 0
              -- (motores desligados); o RCS mantem o nariz apontado.
              S.pedido = (S.erroQueda > cfg.raioDetonacao and tgo > 2) and al or 0
              local dx, dy, dz = normalizar(fx, fy, fz)
              S.dirDes = { dx, dy, dz }
            else
              local dx, dy, dz, f = normalizar(fx, fy, fz)
              if f > 0 then S.dirDes, S.pedido = { dx, dy, dz }, f end
            end
          end
          if fase == "DECOLAGEM" or fase == "SUBIDA" then
            local dx, dy, dz, f = normalizar(fx, fy, fz)
            if f > 0 then S.dirDes, S.pedido = { dx, dy, dz }, f end
          end
        else
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

          if fase == "DECOLAGEM" then
            acelerador(cfg.acelerador)
            S.integral = cfg.acelerador -- a subida comeca sem tranco no empuxo
          else
            -- vertical: o empuxo controla a velocidade de subida/descida
            local vzDes
            if fase == "ATAQUE" then
              vzDes = -cfg.velDescida * clamp(1 - distH / cfg.distAtaque, 0.2, 1)
            else
              vzDes = clamp(cfg.kAlt * (S.cruzeiroY - p.y), -cfg.velDescida, cfg.velSubida)
            end
            local erro = vzDes - vy
            S.integral = clamp(S.integral + cfg.kiVz * erro * dt, 0, 1)
            local u = S.integral + cfg.kVz * erro
            -- inclinado, parte do empuxo vai para o lado: compensa
            local incAtual = math.min(math.max(math.abs(S.n), math.abs(S.l)), 60)
            u = clamp(u / math.max(math.cos(math.rad(incAtual)), 0.5), 0, 1)

            -- prioridade para a altura: empuxo no maximo e mesmo assim
            -- afundando -> inclina menos para sobrar empuxo para cima
            S.limAlt = u >= 0.98 and erro > 1.5
            fatorIncl = fatorIncl + ((S.limAlt and 0.25 or 1) - fatorIncl) * 0.3
            acelerador(u)

            -- horizontal: posicao -> velocidade desejada -> inclinacao desejada
            local vMax, iMax = cfg.velMax, cfg.inclMax * fatorIncl
            if fase == "SUBIDA" then iMax = iMax * 0.5 end
            if fase == "ATAQUE" then vMax = math.min(vMax, math.max(2, distH)) end
            local dvn, dvl = limitarMag(cfg.kPos * en, cfg.kPos * el, vMax)
            tn, tl = limitarMag(cfg.kVel * (dvn - vn), cfg.kVel * (dvl - vl), iMax)
          end
        end

        -- estima o giro do missil no proprio eixo comparando o que foi
        -- pedido com a aceleracao medida pelo GPS (janela de 1 s)
        sCN, sCL, nC = sCN + tn, sCL + tl, nC + 1
        if t - jT >= 1 then
          local dtj = t - jT
          local an, al = (vn - jVn) / dtj, (vl - jVl) / dtj
          local cn, cl = sCN / nC, sCL / nC
          if cfg.corrigirGiro and not S.temGiro and S.fase ~= "DECOLAGEM" and mag(cn, cl) > 4 and mag(an, al) > 0.8 then
            local e = atan2(cn * al - cl * an, cn * an + cl * al)
            S.psi = clamp(S.psi + 0.3 * e, -math.rad(60), math.rad(60))
          end
          jT, jVn, jVl, sCN, sCL, nC = t, vn, vl, 0, 0, 0
        end

        S.alvoN, S.alvoL = rotacionar(tn, tl, -S.psi)

        if S.log then
          local nz, dd = S.nariz or { 0, 0, 0 }, S.dirDes or { 0, 0, 0 }
          S.log.writeLine(("%.2f,%s,%s,%.1f,%.1f,%.1f,%.2f,%.2f,%.2f,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.1f,%.2f,%.2f,%.2f,%.2f,%.1f,%.1f,%.0f,%.2f,%.2f,%.2f,%.1f,%.1f,%.2f,%.2f")
            :format(tv, S.fase, S.modoPose and "pose" or "gimbal", p.x, p.y, p.z, vl, vy, -vn,
              S.fonteVel or (P.altimetro and "altimetro" or "posicao"), nz[1], nz[2], nz[3],
              dd[1], dd[2], dd[3], S.errAng, S.empuxo or 0, S.gravidade, S.cx, S.cy, S.hz, dist, math.deg(S.wy),
              S.pedido or 0, S.aMin or 0, S.aMax or 0, S.erroQueda or 0, S.tgo or 0, S.potSol or 0,
              S.rcsAtit and (S.rcsNivel or 0) or 0))
          if t - ultFlush >= 1 then
            S.log.flush()
            ultFlush = t
          end
        end
      end
    end
  end

  -- TAREFA: empuxo no modo apontamento. A navegacao pede um empuxo (S.pedido) e o
  -- acelerometro mede o real (S.empuxo). A diferenca vira kN (fator aprendido em
  -- voo): primeiro nos liquidos, depois nos solidos, sempre com a MESMA potencia
  -- em todos do grupo (um motor sozinho desequilibra o missil).
  -- Com todos eles desligados, baixa os vector thrusters ate empuxoMin.
  local function gerenciarMotores()
    local vMinBase, vMax = math.min(cfg.empuxoMin, cfg.empuxoVetor), cfg.empuxoVetor
    local vPot, ultV, meta = vMax, vMax, nil
    local lista = {}
    for _, m in ipairs(ativos) do
      table.insert(lista, { m = m, pot = m.classe == "solido" and 1 or cfg.acelerador, max = 0 })
    end
    while true do
      sleep(0.2)
      -- na QUEDA sem pulso de correcao, o piso do vetor cai a zero: o missil
      -- desce balistico e so os RCS do cone o mantem apontado.
      local vMin = (S.coast and (S.pedido or 0) <= 0) and 0 or vMinBase
      local leituras = {}
      for _, e in ipairs(lista) do
        table.insert(leituras, function() e.kn = empuxoKN(e.m) end)
      end
      if #leituras > 0 then parallel.waitForAll(table.unpack(leituras)) end
      local soma, cap = 0, 0
      for _, e in ipairs(lista) do
        if e.pot >= 0.2 then
          -- kN no maximo: sobe na hora, cai devagar (solido acabando)
          local m = e.kn / e.pot
          e.max = m > e.max and m or e.max + 0.2 * (m - e.max)
        end
        soma, cap = soma + e.kn, cap + e.max
      end
      local a, pedido = S.empuxo, S.pedido
      if a and a > 1 then
        -- kN por blocos/s^2, medido com quase tudo ligado. Conta o empuxo dos
        -- vetores como se fosse desses motores: corrige a menos e nao oscila.
        if soma > 0.5 * cap and vPot >= vMax then
          S.kPorA = S.kPorA and S.kPorA + 0.2 * (soma / a - S.kPorA) or soma / a
        end
        if S.kPorA then
          -- parte dos vetores: medida direto quando o resto esta desligado
          local base = soma < 0.02 * cap and a or math.max(a - soma / S.kPorA, 0)
          S.aMin = base * vMin / vPot
          S.aMax = base * vMax / vPot + cap / S.kPorA
          if pedido then
            local erro = pedido - a
            if (meta or soma) <= 0 and (erro < 0 or vPot < vMax) then
              vPot = clamp(vPot + 0.3 * erro / a * vPot, vMin, vMax)
              meta = 0
            else
              meta = clamp((meta or soma) + 0.3 * erro * S.kPorA, 0, cap)
            end
          end
        end
      end
      local resto = meta or math.huge
      local muda = {}
      -- grupo 1: liquidos e outros; grupo 2: solidos (o combustivel nao repoe)
      for _, solido in ipairs({ false, true }) do
        local capG = 0
        for _, e in ipairs(lista) do
          if (e.m.classe == "solido") == solido then capG = capG + e.max end
        end
        local nova = capG > 0 and clamp(resto / capG, 0, 1) or (resto > 0 and 1 or 0)
        resto = resto - nova * capG
        if solido and capG > 0 then S.potSol = nova end
        for _, e in ipairs(lista) do
          if (e.m.classe == "solido") == solido and math.abs(nova - e.pot) >= 0.02 then
            e.pot = nova
            table.insert(muda, function() acelerar(e.m, nova) end)
          end
        end
      end
      if math.abs(vPot - ultV) >= 0.02 then
        ultV = vPot
        table.insert(muda, function() vetorEmpuxo(vPot) end)
      end
      if #muda > 0 then parallel.waitForAll(table.unpack(muda)) end
      S.acel = cap > 0 and soma / cap or vPot
    end
  end

  -- TAREFA: tela e telemetria para a base
  local function telemetria()
    local total, linhas, ultLeitura = 0, {}, nil
    while true do
      -- ler os motores custa varios ticks: so a cada 2 s, para nao roubar
      -- tempo do controle
      if not ultLeitura or os.clock() - ultLeitura >= 2 then
        local algum = false
        total, linhas = 0, {}
        for _, m in ipairs(P.motores) do
          local kn = empuxoKN(m)
          total = total + kn
          local txt, tem = combustivel(m)
          -- so conta motores que estao em uso (solidos desligados nao contam)
          if tem and (m.classe ~= "solido" or cfg.usarSolidos) then algum = true end
          table.insert(linhas, { r = m.rotulo, nome = m.nome, kn = kn, t = txt, ok = tem })
        end
        ultLeitura = os.clock()
        if not guiado and #ativos > 0 and not algum then
          S.motivo = "Combustivel esgotado"
          return
        end
      end

      local tv = os.clock() - S.inicio
      cabecalho(("%s  T+%.1fs"):format(S.fase, tv))
      desenharHorizonte(S.n, S.l, S.alvoN, S.alvoL)
      local x = 18
      escrever(x, 3, ("Incl.  N %5.1f  L %5.1f"):format(S.n, S.l))
      if S.modoPose then
        escrever(x, 4, ("Erro%5.1f queda%5.0f sol%3d%% %s"):format(S.errAng, S.erroQueda or 0,
          math.floor((S.potSol or 0) * 100 + 0.5), S.rcsAtit and "RCS" or ""),
          S.fraco and colors.red or colors.cyan)
      else
        escrever(x, 4, ("Pedido N %5.1f  L %5.1f"):format(S.alvoN, S.alvoL), colors.cyan)
      end
      escrever(x, 5, ("Bocal %5.2f %5.2f  I %5.2f %5.2f"):format(S.cx, S.cy, S.ix, S.iy),
        colors.lightBlue)
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
          math.deg(S.psi)), S.limAlt and colors.red or colors.orange)
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
          queda = S.erroQueda, tgo = S.tgo, sol = S.potSol, erro = S.errAng,
          modo = S.modoPose and "apontamento" or "gimbal", rcs = S.rcsAtit and (S.rcsNivel or 0) or -1,
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
            pos = S.pos, preset = cfg.nome, precisaCodigo = cfg.codigo ~= "", auth = 1,
            vet = #P.vetores, liq = contar("liquido"), sol = contar("solido") }, PROTOCOLO)
        end
      end
    end
  end

  local tarefas = { controle, telemetria, teclado }
  if guiado then table.insert(tarefas, navegacao) end
  if guiado and S.modoPose then table.insert(tarefas, gerenciarMotores) end
  if rednet.isOpen() then table.insert(tarefas, rede) end

  local ok, err = pcall(parallel.waitForAny, table.unpack(tarefas))

  desligarTudo()
  if S.detonou then pcall(sleep, 1) end
  ogiva(false)
  if not ok then
    S.motivo = err == "Terminated" and "Interrompido (CTRL+T)" or ("Erro: " .. tostring(err))
  end
  if S.log then
    S.log.writeLine("# " .. S.motivo)
    S.log.close()
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
    local desafio = nil

    -- confere o codigo: resposta ao desafio (HMAC) ou, se permitido, o codigo aberto
    local function codigoCerto(msg, id, alvo)
      if type(msg.auth) == "string" then
        local d = desafio
        desafio = nil -- cada desafio vale uma vez
        if not d or d.id ~= id or os.clock() > d.ate then return false end
        return cripto.igual(cripto.hex(cripto.hmac(cfg.codigo, mensagemLancar(d.nonce, alvo, id))), msg.auth)
      end
      return not cfg.soCifrado and msg.codigo == cfg.codigo
    end

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
          elseif msg.tipo == "desafio" then
            -- lancamento cifrado: numero unico, vale uma vez por 10 s
            desafio = { nonce = cripto.hex(cripto.aleatorio(16)), id = id, ate = os.clock() + 10 }
            rednet.send(id, { tipo = "desafio", nonce = desafio.nonce }, PROTOCOLO)
          elseif msg.tipo == "lancar" then
            local st = statusMissil()
            local a = type(msg.alvo) == "table" and msg.alvo or {}
            local alvo = { x = tonumber(a.x), y = tonumber(a.y), z = tonumber(a.z) }
            local negar
            if not st.pronto then
              negar = "Nao pronto: " .. table.concat(st.problemas, ", ")
            elseif not (alvo.x and alvo.y and alvo.z) then
              negar = "Alvo invalido"
            elseif cfg.codigo ~= "" and not codigoCerto(msg, id, alvo) then
              negar = "Codigo de lancamento incorreto"
            end
            if negar then
              contato = ("base #%d: NEGADO (%s)"):format(id, negar)
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
    { "empuxoVetor", "Empuxo max do vetor (0-1)", 0, 1 },
    { "empuxoMin", "Empuxo min do vetor (0-1)", 0, 1 },
    { "acelerador", "Acelerador decolagem (0-1)", 0, 1 },
    { "usarSolidos", "Usar motores solidos" },
    { "kp", "KP forca da correcao", 0, 1 },
    { "ki", "KI corrige desvio fixo", 0, 1 },
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
    { "taxaIncl", "Rapidez da inclinacao (g/s)", 1, 90 },
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
  { "Guiagem de missil (sublevel)", {
    { "guiagemPose", "Apontar o nariz (sublevel)" },
    { "conjugarQuat", "Inverter orientacao" },
    { "taxaVirar", "Rapidez para virar (g/s)", 5, 180 },
    { "inclAtaque", "Nariz max fora da rota (g)", 5, 85 },
    { "navN", "Ganho da balistica (N)", 1, 8 },
    { "kGuia", "Ganho da guiagem", 0, 5 },
  } },
  { "RCS (motores no cone)", {
    { "usarRcs", "Usar RCS na queda" },
    { "kRcs", "Forca do RCS (ganho)", 0, 3 },
  } },
  { "Ogiva e seguranca", {
    { "ladoOgiva", "Lado da ogiva (redstone)" },
    { "altDeton", "Detonar a (altura do alvo)", 0, 60 },
    { "raioDetonacao", "Raio de detonacao", 1, 20 },
    { "tempoArme", "Armar apos (segundos)", 0, 60 },
    { "distArme", "Armar a (blocos da base)", 0, 500 },
    { "tempoMax", "Autodestruir apos (s, 0=nao)", 0, 900 },
    { "impacto", "Detonar no impacto" },
  } },
  { "Sistema", {
    { "_label", "Nome do missil" },
    { "codigo", "Codigo de lancamento" },
    { "soCifrado", "So aceitar ordem cifrada" },
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
        "eixoX", "sinalX", "eixoY", "sinalY", "bocalOk", "posMotores", "conjugarQuat", "qCal", "subId", "nome", "rcsMotores",
        "iniciarRemoto" }
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

-- compara a inclinacao pela orientacao do sublevel com a do gimbal
local function testeOrientacao()
  detectar()
  if not P.gimbal then
    aviso("ORIENTACAO", { "Gimbal Sensor nao encontrado." }, colors.red)
    return
  end
  local q0, len = sublevelOrientacao()
  if not q0 then
    aviso("ORIENTACAO", {
      "O sublevel nao entregou a orientacao.",
      len and ("Tamanho do quaternion: %.3f (precisa ser 1)"):format(len)
        or "O computador esta montado na contraption?",
    }, colors.red)
    return
  end
  local soma, total = 0, 0

  local function tela()
    while true do
      local q = sublevelOrientacao()
      local n, l = lerAngulos()
      cabecalho("TESTE DE ORIENTACAO")
      escrever(2, 3, "Missil RETO ao abrir esta tela.", colors.lightGray)
      escrever(2, 4, "Incline para varios lados e compare:", colors.lightGray)
      if q then
        local qn, ql = inclinacaoVetor(narizMundo(q, q0))
        escrever(2, 6, ("Sublevel  N %6.1f   L %6.1f"):format(qn, ql), colors.cyan)
        if math.max(math.abs(n), math.abs(l)) > 4 then
          soma = soma + qn * n + ql * l
          total = total + math.abs(qn * n) + math.abs(ql * l)
        end
      else
        escrever(2, 6, "Sublevel  sem orientacao", colors.red)
      end
      escrever(2, 7, ("Gimbal    N %6.1f   L %6.1f"):format(n, l), colors.lime)
      local txt, c = "Incline mais o missil...", colors.lightGray
      if total > 300 then
        local r = soma / total
        if r > 0.6 then
          txt, c = "CERTO: sublevel e gimbal concordam", colors.lime
        elseif r < -0.6 then
          txt, c = "INVERTIDO: aperte I", colors.red
        else
          txt, c = "Nao bate: gimbal calibrado? mesma direcao?", colors.orange
        end
      end
      escrever(2, 9, txt, c)
      escrever(2, 11, "Inverter orientacao: " .. (cfg.conjugarQuat and "SIM" or "NAO"),
        colors.lightGray)
      rodape("I inverte   BACKSPACE volta")
      sleep(0.1)
    end
  end

  local function teclas()
    while true do
      local _, k = os.pullEvent("key")
      if k == keys.backspace then return end
      if k == keys.i then
        cfg.conjugarQuat = not cfg.conjugarQuat
        if cfg.qCal.w then cfg.qCal = conjugar(cfg.qCal) end
        salvarConfig()
        q0 = conjugar(q0) -- a mesma referencia, lida do outro jeito
        soma, total = 0, 0
      end
    end
  end

  parallel.waitForAny(tela, teclas)
end

-- dispara por 1,5 s os RCS que inclinam o nariz para o lado escolhido
local function testeRcs()
  detectar()
  if #P.rcs == 0 then
    aviso("TESTE RCS", { "Calibre o RCS antes (motores solidos do cone)." }, colors.orange)
    return
  end
  local dirs = { N = { 1, 0 }, S = { -1, 0 }, L = { 0, 1 }, O = { 0, -1 } }
  local msg, msgCor = "", colors.white
  while true do
    cabecalho("TESTE RCS")
    escrever(2, 3, "O nariz vai inclinar. Cuidado, ele se mexe!", colors.yellow)
    escrever(2, 5, "N/S/L/O inclina o nariz 1.5 s para esse lado")
    escrever(2, 7, ("RCS %d   com combustivel %d   ganho %.2f"):format(#P.rcs,
      rcsComCombustivel(), cfg.kRcs), colors.lightGray)
    escrever(2, 9, msg, msgCor)
    rodape("N/S/L/O testa   BACKSPACE volta")
    local ev, k = os.pullEvent()
    if ev == "key" and k == keys.backspace then return end
    local d = ev == "char" and dirs[k:upper()]
    if d then
      escrever(2, 9, ("Inclinando p/ %s..."):format(k:upper()), colors.yellow)
      local soma = rcsAtitude(d[1], d[2])
      sleep(1.5)
      rcsDesligar()
      msg = ("Ultimo: %s, potencia somada %.1f"):format(k:upper(), soma)
      msgCor = soma > 0 and colors.lime or colors.red
    end
  end
end

local function testes()
  while true do
    local i = menu("TESTES", {
      "Painel de status (ao vivo)",
      "Teste de GPS",
      "Controle manual do bocal",
      "Teste da ogiva (use lampada!)",
      "Teste de orientacao (sublevel)",
      "Teste RCS (inclinar N/S/L/O)",
      "Voltar",
    })
    if not i or i == 7 then return end
    if i == 1 then painel()
    elseif i == 2 then testeGps()
    elseif i == 3 then bocalManual()
    elseif i == 4 then testeOgiva()
    elseif i == 5 then testeOrientacao()
    elseif i == 6 then testeRcs() end
    desligarTudo()
    ogiva(false)
  end
end

---------------------------------------------------------------- MENU

local function principal()
  while true do
    detectar()
    abrirRede()
    local extra = (contar("criativo") > 0 and ("  Cri " .. contar("criativo")) or "")
      .. (#P.rcs > 0 and ("  RCS " .. #P.rcs) or "")
    local _, noDisco = localPresets()
    local info = {
      { ("Gimbal %s  Vetor %d  Liq %d  Sol %d  Ion %d%s"):format(
          P.gimbal and "OK" or "--", #P.vetores, contar("liquido"),
          contar("solido"), contar("ion"), extra), colors.lightGray },
      { ("Calib: gimbal %s  bocal %s  giro %d/%d  rcs %s"):format(
          cfg.gimbalOk and "OK" or "PEND.", cfg.bocalOk and "OK" or "PEND.",
          motoresMapeados(), #P.vetores, #P.rcs > 0 and tostring(#P.rcs) or "--"),
        (cfg.gimbalOk and cfg.bocalOk) and colors.lime or colors.orange },
      { ("Rede: %s  %s"):format(nomeRede(), P.modem and "(modem OK)" or "(SEM MODEM)"),
        P.modem and colors.lightGray or colors.orange },
      { ("Preset: %s   Disquete: %s"):format(cfg.nome, noDisco and "SIM" or "NAO"),
        colors.lightGray },
    }
    local acoes = {
      modoRemoto, lancarLocal, voar, calibrarGimbal, calibrarBocal,
      calibrarMotores, calibrarRcs, ajustes, presets, testes,
    }
    local i = menu("MISSIL v" .. VERSAO, {
      "Modo remoto (aguardar base)",
      "Lancar em coordenada",
      "Teste de estabilizacao",
      "Calibrar gimbal",
      "Calibrar bocal",
      "Calibrar giro (lado dos motores)",
      "Calibrar RCS (motores do cone)",
      "Ajustes",
      "Presets (disquete)",
      "Testes",
      "Sair",
    }, info)
    if not i or i == 11 then return end

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
-- base.lua : BlockForge Militar - Centro de Controle de Lancamento
-- BASE v3.0
--  * Autorizacao por disquete: chave unica cifrada, presa ao ID do disquete
--    (copiar os arquivos para outro disquete nao funciona), PIN opcional
--  * Codigo do missil guardado cifrado no disquete; ordem de lancamento
--    assinada com desafio HMAC-SHA256 (missil v4.8 ou mais)
--  * Desacoplagem automatica por redstone (Redstone Link) na ignicao,
--    com confirmacao de separacao
--  * Monitor de missoes: mapa tatico, perfil de altitude, telemetria
--  * Verificacao GO / NO-GO de todos os sistemas e contagem com HOLD
--  * Sirene/luzes, chave mestra (alavanca), registro de seguranca
-- Precisa de: computador avancado + Ender Modem + Disk Drive
-- Opcional: monitor avancado, Redstone Link, sirene/lampadas, alavanca

local VERSAO = "3.0"
local MISSIL_MIN = "4.5"   -- telemetria completa
local MISSIL_CIFRA = "4.8" -- ordem de lancamento com desafio cifrado
local PROTOCOLO = "bfm"
local SERVICO = "bfm_missil"
local ARQ_ALVOS = "bfm_alvos.txt"
local ARQ_ESTADO = "/bfm_base.txt"
local ARQ_VOOS = "/bfm_voos.txt"
local ARQ_CFG = "/bfm_base_cfg.txt"
local ARQ_SEG = "/bfm_seguranca.txt"
local ARQ_LOG = "/bfm_log.txt"
local ARQ_DISCO = "bfm_autorizacao.txt"
local FORMATO_DISCO = "BFM-AUTH-1"
local VOLTAS_PIN = 256 -- PBKDF2: voltas para derivar a chave do PIN

---------------------------------------------------------------- CRIPTOGRAFIA
-- [cripto-inicio]
-- SHA-256, HMAC e PBKDF2 em Lua puro (bit32 do CC: Tweaked).
local cripto = {}
do
  local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
  local rshift, rrotate = bit32.rshift, bit32.rrotate
  local M = 4294967296
  local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }

  function cripto.sha256(msg)
    local ml = #msg
    local bits = ml * 8
    local cauda = {}
    for i = 7, 0, -1 do cauda[#cauda + 1] = string.char(math.floor(bits / 2 ^ (8 * i)) % 256) end
    msg = msg .. "\128" .. string.rep("\0", (55 - ml) % 64) .. table.concat(cauda)
    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local w = {}
    for bloco = 1, #msg, 64 do
      for i = 0, 15 do
        local a, b, c, d = msg:byte(bloco + i * 4, bloco + i * 4 + 3)
        w[i] = ((a * 256 + b) * 256 + c) * 256 + d
      end
      for i = 16, 63 do
        local v, u = w[i - 15], w[i - 2]
        w[i] = (w[i - 16] + bxor(rrotate(v, 7), rrotate(v, 18), rshift(v, 3)) + w[i - 7]
          + bxor(rrotate(u, 17), rrotate(u, 19), rshift(u, 10))) % M
      end
      local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
      for i = 0, 63 do
        local t1 = (h + bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
          + bxor(band(e, f), band(bnot(e), g)) + K[i + 1] + w[i]) % M
        local t2 = (bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
          + bxor(band(a, b), band(a, c), band(b, c))) % M
        h, g, f, e, d, c, b, a = g, f, e, (d + t1) % M, c, b, a, (t1 + t2) % M
      end
      h0, h1, h2, h3 = (h0 + a) % M, (h1 + b) % M, (h2 + c) % M, (h3 + d) % M
      h4, h5, h6, h7 = (h4 + e) % M, (h5 + f) % M, (h6 + g) % M, (h7 + h) % M
    end
    local out = {}
    for _, v in ipairs({ h0, h1, h2, h3, h4, h5, h6, h7 }) do
      out[#out + 1] = string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256,
        math.floor(v / 256) % 256, v % 256)
    end
    return table.concat(out)
  end

  -- a e b com o mesmo tamanho
  function cripto.xor(a, b)
    local r = {}
    for i = 1, #a do r[i] = string.char(bxor(a:byte(i), b:byte(i))) end
    return table.concat(r)
  end

  function cripto.hmac(chave, msg)
    if #chave > 64 then chave = cripto.sha256(chave) end
    chave = chave .. string.rep("\0", 64 - #chave)
    local dentro = cripto.xor(chave, string.rep("\54", 64))
    local fora = cripto.xor(chave, string.rep("\92", 64))
    return cripto.sha256(fora .. cripto.sha256(dentro .. msg))
  end

  -- PBKDF2-HMAC-SHA256 com 32 bytes; cede a vez de tempos em tempos
  function cripto.derivar(senha, sal, voltas)
    local u = cripto.hmac(senha, sal .. "\0\0\0\1")
    local r = u
    for i = 2, voltas do
      u = cripto.hmac(senha, u)
      r = cripto.xor(r, u)
      if i % 32 == 0 then
        os.queueEvent("bfm_cripto")
        os.pullEvent("bfm_cripto")
      end
    end
    return r
  end

  function cripto.hex(s)
    return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
  end

  function cripto.deHex(h)
    if type(h) ~= "string" or #h % 2 == 1 or h:find("[^%x]") then return nil end
    return (h:gsub("%x%x", function(p) return string.char(tonumber(p, 16)) end))
  end

  -- compara sem parar no primeiro byte diferente
  function cripto.igual(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
    local d = 0
    for i = 1, #a do d = bor(d, bxor(a:byte(i), b:byte(i))) end
    return d == 0
  end

  -- bytes imprevisiveis: relogios, sorteio e enderecos de memoria misturados no SHA-256
  local reserva, contador = "", 0
  function cripto.aleatorio(n)
    local out, tam = {}, 0
    while tam < n do
      contador = contador + 1
      reserva = cripto.sha256(table.concat({ reserva, tostring(os.epoch and os.epoch("utc") or 0),
        tostring(os.clock()), tostring(math.random()), tostring(os.getComputerID()),
        tostring(contador), tostring({}) }, "|"))
      out[#out + 1] = reserva
      tam = tam + 32
    end
    return table.concat(out):sub(1, n)
  end
end

-- mensagem assinada na ordem de lancamento (base e missil montam igual)
local function mensagemLancar(nonce, alvo, idBase)
  return ("BFM-LANCAR|%s|%.2f|%.2f|%.2f|%d"):format(nonce, alvo.x, alvo.y, alvo.z, idBase)
end
-- [cripto-fim]

---------------------------------------------------------------- TELA

local W, H = term.getSize()
local COR = term.isColor()

local function cor(c) if COR then term.setTextColor(c) end end
local function fundo(c) if COR then term.setBackgroundColor(c) end end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function arred(v) return math.floor(v + 0.5) end

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
  term.write(" BLOCKFORGE")
  cor(colors.lightGray)
  term.write(" CONTROLE")
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

-- lista de opcoes. 'opcoes' e 'info' podem ser funcoes (redesenha a cada 1 s);
-- 'painel(x, y)' desenha um painel de status a direita em telas largas.
local function menu(titulo, opcoes, info, painel)
  local sel = 1
  local timer = os.startTimer(1)
  local lista
  local redesenhar = true
  while true do
    if redesenhar then
      lista = type(opcoes) == "function" and opcoes() or opcoes
      cabecalho(titulo)
      local y = 3
      local infoL = type(info) == "function" and info() or info
      if infoL then
        for _, l in ipairs(infoL) do
          escrever(2, y, tostring(l[1]):sub(1, W - 2), l[2])
          y = y + 1
        end
        y = y + 1
      end
      local largura = W - 2
      if painel and W >= 46 then
        largura = W - 28
        painel(W - 23, 3)
      end
      local visiveis = math.max(1, H - y)
      local topo = 1
      if sel > visiveis then topo = sel - visiveis + 1 end
      for i = topo, math.min(#lista, topo + visiveis - 1) do
        local txt, c = lista[i], colors.white
        if type(txt) == "table" then txt, c = txt[1], txt[2] end
        txt = ("%s%s %s"):format(i == sel and ">" or " ", i <= 9 and tostring(i) or " ", txt)
        txt = txt:sub(1, largura)
        if i == sel then
          escrever(2, y, txt .. string.rep(" ", largura - #txt), colors.black, colors.yellow)
        else
          escrever(2, y, txt, c)
        end
        y = y + 1
      end
      rodape("SETAS/NUMERO escolhe  ENTER ok  BACKSPACE volta")
      redesenhar = false
    end
    local ev, p = os.pullEvent()
    if ev == "timer" and p == timer then
      timer = os.startTimer(1)
      redesenhar = painel ~= nil or type(opcoes) == "function" or type(info) == "function"
    elseif ev == "key" then
      redesenhar = true
      if p == keys.up then
        sel = sel > 1 and sel - 1 or #lista
      elseif p == keys.down then
        sel = sel < #lista and sel + 1 or 1
      elseif p == keys.enter then
        os.cancelTimer(timer)
        return sel
      elseif p == keys.backspace then
        os.cancelTimer(timer)
        return nil
      end
    elseif ev == "char" then
      local n = tonumber(p)
      if n and n >= 1 and n <= #lista then
        os.cancelTimer(timer)
        return n
      end
    elseif ev == "term_resize" then
      W, H = term.getSize()
      redesenhar = true
    end
  end
end

-- texto longo com rolagem
local function visualizar(titulo, linhas, c)
  local topo = 1
  local area = H - 3
  while true do
    cabecalho(titulo)
    for i = 0, area - 1 do
      local l = linhas[topo + i]
      if type(l) == "table" then
        escrever(2, 3 + i, tostring(l[1]):sub(1, W - 2), l[2])
      elseif l then
        escrever(2, 3 + i, tostring(l):sub(1, W - 2), c)
      end
    end
    local maxTopo = math.max(1, #linhas - area + 1)
    rodape(#linhas > area and ("SETAS rolam (%d/%d)   BACKSPACE volta"):format(topo, maxTopo)
      or "BACKSPACE volta")
    local _, k = os.pullEvent("key")
    if k == keys.up then
      topo = math.max(1, topo - 1)
    elseif k == keys.down then
      topo = math.min(maxTopo, topo + 1)
    elseif k == keys.pageUp then
      topo = math.max(1, topo - area)
    elseif k == keys.pageDown then
      topo = math.min(maxTopo, topo + area)
    elseif k == keys.backspace or k == keys.enter then
      return
    end
  end
end

---------------------------------------------------------------- DESENHO
-- funcoes que desenham em qualquer tela (terminal, monitor ou janela)

local function pintor(t, colorido)
  local tw, th = t.getSize()
  return function(x, y, txt, fg, bg)
    txt = tostring(txt)
    if y < 1 or y > th or x > tw then return end
    if x < 1 then
      txt = txt:sub(2 - x)
      x = 1
    end
    if #txt > tw - x + 1 then txt = txt:sub(1, tw - x + 1) end
    if txt == "" then return end
    t.setCursorPos(x, y)
    if colorido then
      t.setTextColor(fg or colors.white)
      t.setBackgroundColor(bg or colors.black)
    end
    t.write(txt)
  end
end

local FONTE = {
  ["0"] = { "###", "# #", "# #", "# #", "###" },
  ["1"] = { " # ", "## ", " # ", " # ", "###" },
  ["2"] = { "###", "  #", "###", "#  ", "###" },
  ["3"] = { "###", "  #", " ##", "  #", "###" },
  ["4"] = { "# #", "# #", "###", "  #", "  #" },
  ["5"] = { "###", "#  ", "###", "  #", "###" },
  ["6"] = { "###", "#  ", "###", "# #", "###" },
  ["7"] = { "###", "  #", "  #", "  #", "  #" },
  ["8"] = { "###", "# #", "###", "# #", "###" },
  ["9"] = { "###", "# #", "###", "  #", "###" },
  ["T"] = { "###", " # ", " # ", " # ", " # " },
  ["-"] = { "   ", "   ", "###", "   ", "   " },
}

-- texto grande (3x5 por letra, 4 colunas por letra)
local function textoGrande(put, x, y, txt, c)
  for i = 1, #txt do
    local g = FONTE[txt:sub(i, i)]
    if g then
      for l = 1, 5 do
        for k = 1, 3 do
          if g[l]:sub(k, k) == "#" then put(x + (i - 1) * 4 + k - 1, y + l - 1, " ", c, c) end
        end
      end
    end
  end
end

local function barra(put, x, y, larg, frac, c)
  local cheio = math.floor((larg - 2) * clamp(frac, 0, 1) + 0.5)
  put(x, y, "[", colors.gray)
  if cheio > 0 then put(x + 1, y, string.rep(" ", cheio), c, c) end
  put(x + 1 + cheio, y, string.rep("-", larg - 2 - cheio), colors.gray)
  put(x + larg - 1, y, "]", colors.gray)
end

local function distH(a, b)
  local dx, dz = b.x - a.x, b.z - a.z
  return math.sqrt(dx * dx + dz * dz)
end

local function dist3(a, b)
  local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- mapa visto de cima (norte para cima). d = {origem, alvo, base, pos, vel, trilha}
local function desenharMapa(put, x0, y0, w, h, d)
  for yy = y0, y0 + h - 1 do put(x0, yy, string.rep(" ", w)) end
  if w < 6 or h < 4 then return end
  local pts = {}
  local function add(p) if type(p) == "table" and p.x and p.z then table.insert(pts, p) end end
  add(d.origem)
  add(d.alvo)
  add(d.base)
  add(d.pos)
  for _, p in ipairs(d.trilha or {}) do add(p) end
  if #pts == 0 then
    put(x0 + 1, y0 + math.floor(h / 2), "sem posicoes", colors.gray)
    return
  end
  local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(pts) do
    minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
    minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
  end
  -- blocos por coluna; a linha e 1,5x mais alta que a coluna
  local ex = math.max((maxX - minX) * 1.15 / (w - 2), (maxZ - minZ) * 1.15 / ((h - 2) * 1.5), 0.5)
  local ez = ex * 1.5
  local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
  local function tela(p)
    return x0 + math.floor((w - 1) / 2 + (p.x - cx) / ex + 0.5),
      y0 + math.floor((h - 1) / 2 + (p.z - cz) / ez + 0.5)
  end
  for yy = y0, y0 + h - 1, 3 do
    for xx = x0, x0 + w - 1, 6 do put(xx, yy, ".", colors.gray) end
  end
  put(x0 + w - 2, y0, "N", colors.lightGray)
  local escala = ("1:%db"):format(math.max(1, arred(ex)))
  put(x0, y0 + h - 1, escala, colors.gray)
  for _, p in ipairs(d.trilha or {}) do
    local x, y = tela(p)
    put(x, y, ".", colors.lightBlue)
  end
  if d.base then
    local x, y = tela(d.base)
    put(x, y, "H", colors.black, colors.lightGray)
  end
  if d.origem then
    local x, y = tela(d.origem)
    put(x, y, "B", colors.black, colors.lime)
  end
  if d.alvo then
    local x, y = tela(d.alvo)
    put(x, y, "X", colors.white, colors.red)
  end
  if d.pos then
    local x, y = tela(d.pos)
    local seta = "*"
    local v = d.vel
    if v and (math.abs(v.n or 0) + math.abs(v.l or 0)) > 0.5 then
      if math.abs(v.n) >= math.abs(v.l) then
        seta = v.n > 0 and "^" or "v"
      else
        seta = v.l > 0 and ">" or "<"
      end
    end
    put(x, y, seta, colors.black, colors.yellow)
  end
end

-- perfil de altitude: distancia horizontal desde a origem x altura
local function desenharPerfil(put, x0, y0, w, h, d)
  for yy = y0, y0 + h - 1 do put(x0, yy, string.rep(" ", w)) end
  local o, a = d.origem, d.alvo
  if not (o and a) or h < 3 or w < 10 then return end
  local total = math.max(distH(o, a), 1)
  local minY, maxY = math.min(o.y, a.y), math.max(o.y, a.y)
  for _, p in ipairs(d.trilha or {}) do
    minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
  end
  if d.pos then minY, maxY = math.min(minY, d.pos.y), math.max(maxY, d.pos.y) end
  if d.cruzeiroY then maxY = math.max(maxY, d.cruzeiroY) end
  maxY = maxY + 2
  local function tela(p)
    local frac = clamp(distH(o, p) / total, 0, 1)
    return x0 + math.floor(frac * (w - 1) + 0.5),
      y0 + h - 1 - math.floor((p.y - minY) / math.max(maxY - minY, 1) * (h - 1) + 0.5)
  end
  if d.cruzeiroY then
    local _, y = tela({ x = o.x, z = o.z, y = d.cruzeiroY })
    put(x0, y, string.rep("-", w), colors.gray)
  end
  for _, p in ipairs(d.trilha or {}) do
    local x, y = tela(p)
    put(x, y, ".", colors.lightBlue)
  end
  local x, y = tela(o)
  put(x, y, "B", colors.black, colors.lime)
  x, y = tela(a)
  put(x, y, "X", colors.white, colors.red)
  if d.pos then
    x, y = tela(d.pos)
    put(x, y, "*", colors.black, colors.yellow)
  end
end

---------------------------------------------------------------- DADOS

local PADRAO_CFG = {
  -- desacoplagem (Redstone Link)
  desacoplar = true, saidaDesac = "back", atrasoDesac = 0.5, pulsoDesac = 1,
  inverterDesac = false, separacao = 3, tempoSeparacao = 10, abortarSemSeparar = true,
  -- lancamento
  contagem = 10, alcanceMin = 30, alcanceMax = 2000, zonaExclusao = 50, exigirCodigo = true,
  -- sinalizacao
  sirene = "", chaveMestra = "",
  -- seguranca
  tentativasPin = 3, bloqueio = 60,
  -- monitor
  escalaMonitor = 0.5,
}

local C = {}
local sel = { id = nil, nome = nil }
local alvo = nil -- { nome, x, y, z }

-- estado da base compartilhado entre as tarefas
local E = {
  frota = {},     -- [id] = { st = status, visto = os.clock() }
  voo = nil,      -- voo acompanhado (ver novoVoo)
  contagem = nil, -- { t = segundos }
  basePos = nil,  -- posicao da base (zona de exclusao)
  log = {},       -- ultimas linhas do registro
}

-- sessao de autorizacao
local SEG = { estado = "SEM_DISCO" }

local TEXTO_SEG = {
  NAO_CONFIGURADO = { "NENHUM DISQUETE EMITIDO", colors.orange },
  SEM_DRIVE = { "SEM DISK DRIVE", colors.red },
  SEM_DISCO = { "INSIRA O DISQUETE", colors.orange },
  INVALIDO = { "DISQUETE INVALIDO", colors.red },
  REVOGADO = { "DISQUETE REVOGADO", colors.red },
  COPIA = { "COPIA NAO AUTORIZADA", colors.red },
  PIN = { "AGUARDANDO PIN", colors.yellow },
  BLOQUEADO = { "BLOQUEADO (PIN ERRADO)", colors.red },
  ENCERRADA = { "SESSAO ENCERRADA", colors.orange },
  AUTORIZADO = { "AUTORIZADO", colors.lime },
}

local function textoSeg()
  local t = TEXTO_SEG[SEG.estado] or { SEG.estado, colors.white }
  return t[1], t[2]
end

local function lerTabela(caminho)
  if not fs.exists(caminho) then return nil end
  local f = fs.open(caminho, "r")
  if not f then return nil end
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

local function carregarCfg()
  C = {}
  for k, v in pairs(PADRAO_CFG) do C[k] = v end
  local d = lerTabela(ARQ_CFG)
  if d then
    for k, v in pairs(d) do
      if PADRAO_CFG[k] ~= nil and type(v) == type(PADRAO_CFG[k]) then C[k] = v end
    end
  end
end

local function salvarCfg()
  gravarTabela(ARQ_CFG, C)
end

local function carregarEstado()
  local e = lerTabela(ARQ_ESTADO)
  if e then
    sel = e.sel or sel
    alvo = e.alvo
    E.basePos = e.basePos
  end
end

local function salvarEstado()
  gravarTabela(ARQ_ESTADO, { sel = sel, alvo = alvo, basePos = E.basePos })
end

-- registro de seguranca e operacao (/bfm_log.txt, ultimas 200 linhas)
local function registrar(txt)
  local linha = os.date("%d/%m %H:%M:%S") .. " " .. tostring(txt)
  table.insert(E.log, 1, linha)
  if #E.log > 20 then table.remove(E.log) end
  local f = fs.open(ARQ_LOG, "a")
  if f then
    f.writeLine(linha)
    f.close()
  end
  if fs.exists(ARQ_LOG) and fs.getSize(ARQ_LOG) > 24000 then
    local r = fs.open(ARQ_LOG, "r")
    local todas = {}
    local l = r.readLine()
    while l do
      table.insert(todas, l)
      l = r.readLine()
    end
    r.close()
    local w = fs.open(ARQ_LOG, "w")
    for i = math.max(1, #todas - 199), #todas do w.writeLine(todas[i]) end
    w.close()
  end
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
  return lerTabela((arquivoAlvos())) or {}
end

local function gravarAlvos(lista)
  gravarTabela((arquivoAlvos()), lista)
end

local function coords(a)
  return ("%d %d %d"):format(math.floor(a.x), math.floor(a.y), math.floor(a.z))
end

local function versaoNum(s)
  local a, b = tostring(s):match("(%d+)%.(%d+)")
  return a and tonumber(a) * 1000 + tonumber(b) or 0
end

local function versaoOk(v) return versaoNum(v) >= versaoNum(MISSIL_MIN) end

local function nomeSel()
  return sel.nome or (sel.id and ("#" .. sel.id)) or "nenhum"
end

local function statusSel()
  local f = sel.id and E.frota[sel.id]
  return f and f.st, f and (os.clock() - f.visto)
end

---------------------------------------------------------------- REDE

local function modemSemFio()
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.hasType(nome, "modem") and peripheral.call(nome, "isWireless") then
      return nome
    end
  end
  return nil
end

local function abrirModem()
  local nome = modemSemFio()
  if nome and not rednet.isOpen(nome) then rednet.open(nome) end
  return nome
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
  local st = esperar(id, { status = true }, 2)
  if st then E.frota[id] = { st = st, visto = os.clock() } end
  return st
end

---------------------------------------------------------------- REDSTONE
-- "lado" no computador ou "nome_do_relay:lado" num Redstone Relay

local function resolverRs(spec)
  if type(spec) ~= "string" or spec == "" then return nil end
  local nome, lado = spec:match("^(.+):(%a+)$")
  if nome then
    if peripheral.isPresent(nome) and peripheral.hasType(nome, "redstone_relay") then
      return peripheral.wrap(nome), lado
    end
    return nil
  end
  for _, l in ipairs(rs.getSides()) do
    if l == spec then return redstone, spec end
  end
  return nil
end

local function saidaRs(spec, ligado)
  local dev, lado = resolverRs(spec)
  if dev then pcall(dev.setOutput, lado, ligado) end
  return dev ~= nil
end

local function entradaRs(spec)
  local dev, lado = resolverRs(spec)
  if not dev then return nil end
  local ok, v = pcall(dev.getInput, lado)
  return ok and v == true
end

-- sinal da desacoplagem (true = soltar)
local function saidaDesac(soltar)
  return saidaRs(C.saidaDesac, soltar ~= C.inverterDesac)
end

local function sinalizar(ligado)
  if C.sirene ~= "" then saidaRs(C.sirene, ligado) end
end

local function repouso()
  if C.saidaDesac ~= "" then saidaDesac(false) end
  sinalizar(false)
end

---------------------------------------------------------------- SEGURANCA

local function agora() return os.epoch("utc") / 1000 end

local function lerSeg()
  local s = lerTabela(ARQ_SEG) or {}
  s.discos = s.discos or {}
  s.falhas = s.falhas or 0
  s.bloqueioAte = s.bloqueioAte or 0
  return s
end

local function discosAtivos(s)
  local n = 0
  for _, r in ipairs(s.discos) do
    if not r.revogado then n = n + 1 end
  end
  return n
end

local function lerDisco(d)
  if not (d and d.isDiskPresent() and d.hasData()) then return nil end
  local caminho = fs.combine(d.getMountPath(), ARQ_DISCO)
  local t = lerTabela(caminho)
  if t and t.formato == FORMATO_DISCO then return t, caminho end
  return nil
end

-- o que a base guarda: so o hash da chave, preso ao ID do disquete
local function hashChave(chave, discoId, serial)
  return cripto.hex(cripto.sha256("BFM|" .. chave .. "|" .. tostring(discoId) .. "|" .. serial))
end

local function cifrarCodigo(chave, nome, codigo)
  local iv = cripto.aleatorio(8)
  local c = cripto.xor(codigo, cripto.hmac(chave, "COD|" .. nome .. "|" .. iv):sub(1, #codigo))
  return { iv = cripto.hex(iv), c = cripto.hex(c),
    tag = cripto.hex(cripto.hmac(chave, "TAG|" .. nome .. "|" .. iv .. c):sub(1, 16)) }
end

local function decifrarCodigo(chave, nome, e)
  if type(e) ~= "table" then return nil end
  local iv, c = cripto.deHex(e.iv), cripto.deHex(e.c)
  if not iv or not c or #c > 32 then return nil end
  local tag = cripto.hex(cripto.hmac(chave, "TAG|" .. nome .. "|" .. iv .. c):sub(1, 16))
  if not cripto.igual(tag, e.tag) then return nil end
  return cripto.xor(c, cripto.hmac(chave, "COD|" .. nome .. "|" .. iv):sub(1, #c))
end

-- confere o disquete do drive. Devolve estado, dados do disco, registro e chave
local function conferirDisco(pin)
  local s = lerSeg()
  if #s.discos == 0 then return "NAO_CONFIGURADO" end
  if s.bloqueioAte > agora() then return "BLOQUEADO" end
  local d = peripheral.find("drive")
  if not d then return "SEM_DRIVE" end
  if not d.isDiskPresent() then return "SEM_DISCO" end
  local dados = lerDisco(d)
  if not dados then return "INVALIDO" end
  local reg
  for _, r in ipairs(s.discos) do
    if r.serial == dados.serial then reg = r end
  end
  if not reg then return "INVALIDO", dados end
  if reg.revogado then return "REVOGADO", dados, reg end
  if reg.discoId ~= d.getDiskID() then return "COPIA", dados, reg end
  if dados.comPin and not pin then return "PIN", dados, reg end
  local sal, cif = cripto.deHex(dados.sal), cripto.deHex(dados.chave)
  if not sal or not cif or #cif ~= 32 then return "INVALIDO", dados, reg end
  local kek = cripto.derivar(dados.comPin and pin or "", sal, dados.voltas or VOLTAS_PIN)
  local chave = cripto.xor(cif, kek)
  if not cripto.igual(hashChave(chave, reg.discoId, dados.serial), reg.hash) then
    return dados.comPin and "PIN_ERRADO" or "INVALIDO", dados, reg
  end
  return "AUTORIZADO", dados, reg, chave
end

local function definirSessao(estado, dados, reg, chave, discoId)
  local antes = SEG.estado
  SEG = { estado = estado, dados = dados, reg = reg, chave = chave, discoId = discoId }
  if estado == "AUTORIZADO" then
    SEG.codigos = {}
    for nome, e in pairs(dados.codigos or {}) do
      SEG.codigos[nome] = decifrarCodigo(chave, nome, e)
    end
    if antes ~= "AUTORIZADO" then
      registrar(("AUTORIZADO: operador %s, disquete %s"):format(dados.operador, dados.serial))
    end
  elseif (estado == "COPIA" or estado == "REVOGADO") and antes ~= estado then
    registrar(("ALERTA: %s (serial %s)"):format(TEXTO_SEG[estado][1], dados and dados.serial or "?"))
  end
end

local vistoDisco = false -- ID do disquete na ultima conferencia automatica

local function encerrarSessao(motivo, manual)
  if SEG.estado == "AUTORIZADO" then registrar("SESSAO ENCERRADA: " .. motivo) end
  local d = peripheral.find("drive")
  local id = d and d.isDiskPresent() and d.getDiskID() or nil
  if manual then
    SEG = { estado = "ENCERRADA", discoId = id }
    vistoDisco = id
  else
    SEG = { estado = "SEM_DISCO" }
    vistoDisco = false
  end
end

-- chamada pela tarefa vigia: trava na hora quando o disquete sai
local function atualizarSeguranca(forcar)
  local d = peripheral.find("drive")
  local id = nil
  if d and d.isDiskPresent() then id = d.getDiskID() end
  if SEG.estado == "AUTORIZADO" then
    if d and id and id == SEG.discoId then return end
    encerrarSessao(id and "disquete trocado" or "disquete removido")
  end
  if SEG.estado == "ENCERRADA" then
    if id == SEG.discoId then return end
    vistoDisco = false
  end
  if not forcar and id == vistoDisco and SEG.estado ~= "BLOQUEADO"
    and SEG.estado ~= "NAO_CONFIGURADO" then
    return
  end
  vistoDisco = id
  local estado, dados, reg, chave = conferirDisco(nil)
  -- o estado pode ter mudado enquanto a chave era derivada
  if SEG.estado == "AUTORIZADO" then return end
  definirSessao(estado, dados, reg, chave, id)
end

-- pede o PIN do disquete no drive
local function desbloquear()
  if SEG.estado == "AUTORIZADO" then return true end
  local estado, dados, reg, chave = conferirDisco(nil)
  if estado == "AUTORIZADO" then
    -- disquete sem PIN que a tarefa vigia ainda nao tinha conferido
    local id = peripheral.find("drive").getDiskID()
    definirSessao(estado, dados, reg, chave, id)
    vistoDisco = id
    return true
  end
  if estado ~= "PIN" then
    local t = TEXTO_SEG[estado] or { estado }
    aviso("AUTORIZACAO", { t[1], "", "Insira um disquete de autorizacao valido no Disk Drive." },
      colors.red)
    return false
  end
  local s = lerSeg()
  cabecalho("AUTORIZACAO")
  escrever(2, 3, ("Disquete %s  -  operador %s"):format(dados.serial, dados.operador), colors.yellow)
  escrever(2, 4, ("Tentativas antes do bloqueio: %d"):format(math.max(1, C.tentativasPin - s.falhas)),
    colors.lightGray)
  local pin = perguntar(6, "PIN: ", nil, true)
  if not pin or pin == "" then return false end
  escrever(2, 8, "Verificando...", colors.lightGray)
  local d = peripheral.find("drive")
  local id = d and d.isDiskPresent() and d.getDiskID()
  local est, dd, rr, kk = conferirDisco(pin)
  s = lerSeg()
  if est == "AUTORIZADO" then
    s.falhas = 0
    gravarTabela(ARQ_SEG, s)
    definirSessao(est, dd, rr, kk, id)
    vistoDisco = id
    return true
  end
  if est == "PIN_ERRADO" then
    s.falhas = s.falhas + 1
    local linhas = { "PIN incorreto." }
    registrar(("PIN ERRADO no disquete %s (%d/%d)"):format(dd.serial, s.falhas, C.tentativasPin))
    if s.falhas >= C.tentativasPin then
      s.falhas = 0
      s.bloqueioAte = agora() + C.bloqueio
      registrar(("BLOQUEIO de %d s por PIN errado"):format(C.bloqueio))
      table.insert(linhas, ("Base BLOQUEADA por %d segundos."):format(C.bloqueio))
      SEG = { estado = "BLOQUEADO" }
    end
    gravarTabela(ARQ_SEG, s)
    aviso("AUTORIZACAO NEGADA", linhas, colors.red)
    return false
  end
  aviso("AUTORIZACAO", { (TEXTO_SEG[est] or { est })[1] }, colors.red)
  return false
end

-- acoes perigosas pedem autorizacao (livres so antes do primeiro disquete)
local function exigirAutorizacao(titulo)
  if SEG.estado == "AUTORIZADO" then return true end
  if #lerSeg().discos == 0 then return true end
  if SEG.estado == "PIN" then return desbloquear() end
  aviso(titulo, { "Precisa de autorizacao: " .. textoSeg(), "",
    "Insira um disquete de autorizacao valido." }, colors.red)
  return false
end

local function codigoDoDisco(nome)
  return SEG.estado == "AUTORIZADO" and SEG.codigos and SEG.codigos[nome] or nil
end

---------------------------------------------------------------- SISTEMAS GO / NO-GO

local function monitorPresente()
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.hasType(nome, "monitor") then return nome end
  end
  return nil
end

-- estado de cada sistema, sem esperar nada (serve para o monitor)
local function sistemas()
  local L = {}
  local function item(nome, go, detalhe, critico)
    table.insert(L, { nome = nome, go = go and true or false, detalhe = detalhe or "",
      critico = critico ~= false })
  end
  local modem = modemSemFio()
  item("REDE", modem ~= nil, modem and ("modem " .. modem) or "sem modem sem fio")
  local segTxt = textoSeg()
  if SEG.estado == "AUTORIZADO" and SEG.dados then
    segTxt = ("%s  #%s"):format(SEG.dados.operador, SEG.dados.serial)
  end
  item("AUTORIZACAO", SEG.estado == "AUTORIZADO", segTxt)
  if C.chaveMestra ~= "" then
    local v = entradaRs(C.chaveMestra)
    item("CHAVE MESTRA", v, v == nil and "entrada invalida" or (v and "ARMADA" or "em SEGURO"))
  end
  local st, idade = statusSel()
  local contato = st and idade < 30
  if not sel.id then
    item("MISSIL", false, "nenhum selecionado")
  elseif not st then
    item("MISSIL", false, nomeSel() .. ": sem resposta")
  else
    item("MISSIL", contato, contato and (nomeSel() .. " v" .. tostring(st.versao))
      or ("sem contato ha %ds"):format(math.floor(idade)))
    item("VERSAO", versaoOk(st.versao), ("v%s (min v%s)"):format(tostring(st.versao), MISSIL_MIN))
    item("PRONTIDAO", st.pronto and not st.emVoo, st.emVoo and "missil em voo"
      or (st.pronto and "calibrado e pronto" or table.concat(st.problemas or {}, ", ")))
    if st.precisaCodigo then
      local tem = codigoDoDisco(st.nome or nomeSel()) ~= nil
      item("CODIGO", true, tem and "cifrado no disquete" or "sera digitado no lancamento")
      item("CIFRA", st.auth ~= nil, st.auth and "desafio HMAC-SHA256"
        or ("codigo aberto: atualize o missil p/ v" .. MISSIL_CIFRA), false)
    else
      item("CODIGO", not C.exigirCodigo, "missil sem codigo de lancamento", C.exigirCodigo)
    end
  end
  item("ALVO", alvo ~= nil, alvo and (alvo.nome .. "  " .. coords(alvo)) or "nao definido")
  if alvo then
    if st and st.pos then
      local d = distH(st.pos, alvo)
      item("ALCANCE", d >= C.alcanceMin and d <= C.alcanceMax,
        ("%d blocos (%d a %d)"):format(arred(d), C.alcanceMin, C.alcanceMax))
    else
      item("ALCANCE", false, "posicao do missil desconhecida", false)
    end
    local b = E.basePos or (st and st.pos)
    if b then
      local d = distH(b, alvo)
      item("ZONA SEGURA", d >= C.zonaExclusao,
        ("%d b da base (min %d)"):format(arred(d), C.zonaExclusao))
    end
  end
  if C.desacoplar then
    local ok = resolverRs(C.saidaDesac) ~= nil
    item("DESACOPLAGEM", ok, ok and ("saida " .. C.saidaDesac) or "saida de redstone invalida")
  else
    item("DESACOPLAGEM", false, "automatica desligada", false)
  end
  if E.voo and not E.voo.fim then
    item("VOO", false, "ha um voo em andamento")
  end
  local mon = monitorPresente()
  item("MONITOR", mon ~= nil, mon or "sem monitor", false)
  return L
end

local function contarNoGo(L)
  local n, primeiro = 0, nil
  for _, it in ipairs(L) do
    if it.critico and not it.go then
      n = n + 1
      primeiro = primeiro or it.nome
    end
  end
  return n, primeiro
end

---------------------------------------------------------------- VOO

local function eventoVoo(v, txt)
  local t = v.ignicao and ("T+%.0f "):format(os.clock() - v.ignicao) or ""
  table.insert(v.eventos, 1, t .. tostring(txt))
  if #v.eventos > 12 then table.remove(v.eventos) end
end

local function registrarVoo(v)
  local lista = lerTabela(ARQ_VOOS) or {}
  local trilha = {}
  local passo = math.max(1, math.ceil(#v.trilha / 80))
  for i = 1, #v.trilha, passo do
    local p = v.trilha[i]
    table.insert(trilha, { x = arred(p.x), y = arred(p.y), z = arred(p.z) })
  end
  table.insert(lista, 1, { quando = os.date("%d/%m %H:%M"), missil = v.nome, alvo = v.alvo,
    motivo = v.fim, t = v.T and v.T.t, dist = v.T and v.T.dist, origem = v.origem,
    trilha = trilha, separado = v.separado, operador = v.operador, serial = v.serial })
  while #lista > 20 do table.remove(lista) end
  gravarTabela(ARQ_VOOS, lista)
end

local function finalizarVoo(v, motivo)
  if v.fim then return end
  v.fim = motivo
  v.fimClock = os.clock()
  sinalizar(false)
  if v.desac and not v.desacSolto then
    saidaDesac(false)
    v.desacSolto = true
  end
  eventoVoo(v, "FIM: " .. motivo)
  registrar(("VOO ENCERRADO (%s): %s"):format(v.nome, motivo))
  pcall(registrarVoo, v)
end

local function abortarVoo(v, motivo)
  for _ = 1, 3 do rednet.send(v.id, { tipo = "abortar" }, PROTOCOLO) end
  eventoVoo(v, "ABORTAR enviado: " .. motivo)
  registrar(("ABORTAR %s: %s"):format(v.nome, motivo))
end

local function desacoplar(v, modo)
  if v.desac or not saidaDesac(true) then return false end
  v.desac = os.clock()
  v.desacModo = modo
  if C.pulsoDesac <= 0 then v.desacSolto = false end
  eventoVoo(v, "DESACOPLAGEM (" .. modo .. ")")
  registrar(("DESACOPLAGEM %s de %s pela saida %s"):format(modo, v.nome, C.saidaDesac))
  return true
end

local function dadosMapa(v)
  if v then
    return { origem = v.origem, alvo = v.alvo, trilha = v.trilha, base = E.basePos,
      pos = v.T and v.T.pos, vel = v.T and v.T.vel, cruzeiroY = v.T and v.T.cruzeiroY }
  end
  local st = statusSel()
  return { origem = st and st.pos, alvo = alvo, base = E.basePos }
end

-- linhas de telemetria {rotulo, texto, cor} (terminal e monitor)
local function linhasTelemetria(v)
  local L = {}
  local function add(r, txt, c) table.insert(L, { r, txt, c or colors.white }) end
  local T = v.T
  if not T then
    add("SINAL", v.fim and "sem telemetria" or (v.ignicao and "aguardando dados..."
      or "contagem do missil..."), colors.lightGray)
  else
    add("FASE", tostring(T.fase), colors.yellow)
    add("T+", ("%.1f s"):format(T.t or 0))
    if T.pos then add("ALTITUDE", ("Y %d"):format(arred(T.pos.y))) end
    local vel = T.vel or {}
    local vn, vl, vy = vel.n or 0, vel.l or 0, vel.y or 0
    local vh = math.sqrt(vn * vn + vl * vl)
    add("VELOCIDADE", ("%.1f b/s  vy %+.1f"):format(math.sqrt(vh * vh + vy * vy), vy))
    if T.dist then
      add("DISTANCIA", ("%d b  hor %d"):format(arred(T.dist), arred(T.distH or 0)), colors.yellow)
    end
    if T.queda then
      add("IMPACTO", ("em %ds  erro %.1f b"):format(arred(math.max(T.tgo or 0, 0)), T.queda),
        T.queda <= 4 and colors.lime or colors.orange)
    elseif T.distH and vh > 1 then
      add("CHEGADA", ("~%d s"):format(arred(T.distH / vh)))
    end
    if T.modo then add("APONTAMENTO", ("erro %.1f graus"):format(T.erro or 0)) end
    add("MOTORES", ("%dHz ac%d%%%s"):format(arred(T.hz or 0), arred((T.acel or 0) * 100),
      T.sol and (" sol%d%%"):format(arred(T.sol * 100)) or ""),
      (T.hz or 0) >= 5 and colors.lime or colors.red)
    add("OGIVA", T.armado and "ARMADA" or "desarmada", T.armado and colors.red or colors.lime)
  end
  if v.desac then
    add("DESACOPLAR", ("%s T+%.1f"):format(v.desacModo, v.desac - (v.ignicao or v.desac)), colors.lime)
    add("SEPARACAO", v.separado and "CONFIRMADA" or (v.falhaSep and "FALHOU" or "verificando..."),
      v.separado and colors.lime or (v.falhaSep and colors.red or colors.yellow))
  elseif not v.fim then
    add("DESACOPLAR", C.desacoplar and (v.ignicao and "aguardando atraso" or "na ignicao")
      or "manual (tecla D)", colors.lightGray)
  end
  if not v.fim and v.ultimo then
    local s = os.clock() - v.ultimo
    add("SINAL", s > 3 and ("PERDIDO ha %ds"):format(math.floor(s)) or "OK",
      s > 3 and colors.red or colors.lime)
  end
  return L
end

---------------------------------------------------------------- TELAS: VERIFICACAO

local function rotuloGo(it)
  if it.go then return " GO  ", colors.black, colors.lime end
  if it.critico then return "NO-GO", colors.white, colors.red end
  return "AVISO", colors.black, colors.orange
end

-- verificacao pre-lancamento: consulta o missil e chama cada sistema
local function verificacao(paraLancar)
  cabecalho("VERIFICACAO GO / NO-GO")
  escrever(2, 3, "Consultando o missil e os sistemas...", colors.yellow)
  if sel.id and modemSemFio() then consultar(sel.id) end
  local L = sistemas()
  cabecalho("VERIFICACAO GO / NO-GO")
  escrever(2, 2, "DIRETOR DE LANCAMENTO: chamada dos sistemas", colors.lightGray)
  local y = 3
  for i, it in ipairs(L) do
    if y > H - 2 then
      escrever(2, H - 2, ("... e mais %d"):format(#L - i + 1), colors.lightGray)
      break
    end
    escrever(2, y, it.nome, colors.white)
    escrever(16, y, " ... ", colors.gray)
    sleep(0.1)
    local rot, fg, bg = rotuloGo(it)
    escrever(16, y, rot, fg, bg)
    escrever(22, y, it.detalhe:sub(1, W - 22), it.go and colors.lightGray or bg)
    y = y + 1
  end
  local nogo, primeiro = contarNoGo(L)
  local faixa = nogo == 0 and " TODOS OS SISTEMAS: GO "
    or (" NO-GO: %d sistema(s), primeiro %s "):format(nogo, primeiro)
  escrever(2, H - 1, faixa .. string.rep(" ", math.max(0, W - 2 - #faixa)),
    nogo == 0 and colors.black or colors.white, nogo == 0 and colors.lime or colors.red)
  registrar(nogo == 0 and "VERIFICACAO: todos GO" or ("VERIFICACAO: NO-GO em %s"):format(primeiro))
  if not paraLancar then
    rodape("Aperte qualquer tecla")
    os.pullEvent("key")
    return nogo == 0
  end
  rodape(nogo == 0 and "ENTER prossegue   BACKSPACE cancela" or "BACKSPACE volta")
  while true do
    local _, k = os.pullEvent("key")
    if k == keys.backspace then return false end
    if k == keys.enter and nogo == 0 then return true end
  end
end

---------------------------------------------------------------- TELAS: SEGURANCA

local function pedirPin(y)
  escrever(2, y, "PIN de 4 a 16 caracteres (vazio = sem PIN).", colors.lightGray)
  while true do
    local p1 = perguntar(y + 1, "PIN:      ", nil, true)
    if not p1 then return nil end
    if p1 == "" then return "" end
    if #p1 >= 4 and #p1 <= 16 then
      local p2 = perguntar(y + 2, "Repita:   ", nil, true)
      if p2 == p1 then return p1 end
      escrever(2, y + 3, "Os PINs nao conferem. Tente de novo.", colors.red)
    else
      escrever(2, y + 3, "O PIN precisa de 4 a 16 caracteres.   ", colors.red)
    end
    term.setCursorPos(1, y + 1)
    term.clearLine()
    term.setCursorPos(1, y + 2)
    term.clearLine()
  end
end

local function emitirDisco()
  local s = lerSeg()
  local ativos = discosAtivos(s)
  if ativos > 0 and SEG.estado ~= "AUTORIZADO" then
    if not exigirAutorizacao("EMITIR DISQUETE") then return end
  end
  local d = peripheral.find("drive")
  if not d then
    aviso("EMITIR DISQUETE", { "Coloque um Disk Drive na base." }, colors.red)
    return
  end
  local emissor = SEG.dados and SEG.dados.operador or "primeira configuracao"
  local idAtual = SEG.discoId
  -- guarda os codigos da sessao para copiar ao disquete novo
  local codigos = {}
  for nome, c in pairs(SEG.codigos or {}) do codigos[nome] = c end

  -- espera um disquete que nao seja o de autorizacao em uso
  local timer = os.startTimer(0)
  while true do
    local ev, p = os.pullEvent()
    if ev == "key" and p == keys.backspace then return end
    if ev == "timer" and p == timer then
      cabecalho("EMITIR DISQUETE")
      if ativos > 0 then
        escrever(2, 3, "Retire o disquete de autorizacao e", colors.yellow)
        escrever(2, 4, "insira o disquete NOVO no drive.", colors.yellow)
      else
        escrever(2, 3, "Primeira configuracao da seguranca.", colors.yellow)
        escrever(2, 4, "Insira um disquete no drive.", colors.yellow)
      end
      escrever(2, 6, "A autorizacao fica presa a ESTE disquete:", colors.lightGray)
      escrever(2, 7, "copiar os arquivos para outro nao funciona.", colors.lightGray)
      rodape("BACKSPACE cancela")
      local id = d.isDiskPresent() and d.getDiskID() or nil
      if id and id ~= idAtual then break end
      timer = os.startTimer(0.5)
    end
  end

  local id = d.getDiskID()
  for _, r in ipairs(s.discos) do
    if r.discoId == id and not r.revogado then
      aviso("EMITIR DISQUETE", { ("Este disquete ja e a autorizacao %s."):format(r.serial),
        "Revogue-o antes de emitir de novo." }, colors.orange)
      return
    end
  end

  cabecalho("EMITIR DISQUETE")
  escrever(2, 3, ("Disquete #%d detectado."):format(id), colors.lime)
  escrever(2, 5, "Nome do operador (letras, numeros, _ ou -)", colors.yellow)
  local operador = perguntar(6, "> ")
  if not operador or not operador:match("^[%w_%-]+$") or #operador > 16 then
    aviso("EMITIR DISQUETE", { "Nome invalido (1 a 16 caracteres)." }, colors.red)
    return
  end
  local pin = pedirPin(8)
  if not pin then return end

  cabecalho("EMITIR DISQUETE")
  escrever(2, 3, "Gerando chave de 256 bits...", colors.yellow)
  local chave = cripto.aleatorio(32)
  local sal = cripto.aleatorio(16)
  local serial = cripto.hex(cripto.aleatorio(3)):upper()
  local kek = cripto.derivar(pin, sal, VOLTAS_PIN)
  local dados = {
    formato = FORMATO_DISCO, serial = serial, operador = operador,
    emitido = os.date("%d/%m/%Y %H:%M"), emissor = emissor, comPin = pin ~= "",
    voltas = VOLTAS_PIN, sal = cripto.hex(sal), chave = cripto.hex(cripto.xor(chave, kek)),
    codigos = {},
  }
  local n = 0
  for nome, c in pairs(codigos) do
    dados.codigos[nome] = cifrarCodigo(chave, nome, c)
    n = n + 1
  end
  if not d.isDiskPresent() or d.getDiskID() ~= id then
    aviso("EMITIR DISQUETE", { "O disquete saiu do drive. Nada foi gravado." }, colors.red)
    return
  end
  gravarTabela(fs.combine(d.getMountPath(), ARQ_DISCO), dados)
  pcall(d.setDiskLabel, "AUTORIZACAO " .. serial)
  table.insert(s.discos, { serial = serial, discoId = id, hash = hashChave(chave, id, serial),
    operador = operador, emitido = dados.emitido, comPin = dados.comPin })
  gravarTabela(ARQ_SEG, s)
  registrar(("DISQUETE EMITIDO %s para %s (por %s, PIN %s)"):format(serial, operador, emissor,
    dados.comPin and "sim" or "nao"))

  local linhas = {
    ("Disquete %s emitido para %s."):format(serial, operador),
    dados.comPin and "Protegido por PIN." or "Sem PIN: basta inserir o disquete.",
  }
  if n > 0 then table.insert(linhas, ("%d codigo(s) de missil copiados."):format(n)) end
  table.insert(linhas, "")
  table.insert(linhas, "Guarde-o bem: sem um disquete valido a base NAO lanca.")
  if ativos == 0 then
    table.insert(linhas, "A partir de agora a base exige autorizacao.")
  end
  aviso("DISQUETE EMITIDO", linhas, colors.lime)
  atualizarSeguranca(true)
end

local function listaDiscos()
  if not exigirAutorizacao("DISQUETES EMITIDOS") then return end
  while true do
    local s = lerSeg()
    if #s.discos == 0 then
      aviso("DISQUETES EMITIDOS", { "Nenhum disquete emitido." }, colors.orange)
      return
    end
    local ops = {}
    for _, r in ipairs(s.discos) do
      local uso = SEG.dados and SEG.dados.serial == r.serial and " <em uso>" or ""
      table.insert(ops, { ("%s %-10s %s%s"):format(r.serial, r.operador, r.revogado and "REVOGADO" or "ativo",
        uso), r.revogado and colors.gray or colors.white })
    end
    table.insert(ops, "Voltar")
    local i = menu("DISQUETES EMITIDOS", ops)
    if not i or i == #ops then return end
    local r = s.discos[i]
    if r.revogado then
      aviso("DISQUETE " .. r.serial, { "Ja revogado.", "Operador: " .. r.operador,
        "Emitido: " .. tostring(r.emitido) }, colors.lightGray)
    elseif confirmar("REVOGAR " .. r.serial, ("Revogar o disquete de %s (emitido %s)? Ele deixa de funcionar para sempre.")
      :format(r.operador, tostring(r.emitido))) then
      if discosAtivos(s) == 1 and not confirmar("REVOGAR", "E o ULTIMO disquete ativo: a base so lanca depois de emitir outro. Continuar?") then
        return
      end
      r.revogado = true
      gravarTabela(ARQ_SEG, s)
      registrar(("DISQUETE REVOGADO %s (%s)"):format(r.serial, r.operador))
      if SEG.dados and SEG.dados.serial == r.serial then encerrarSessao("disquete revogado") end
      atualizarSeguranca(true)
    end
  end
end

local function gravarCodigoDisco(nome, codigo)
  local d = peripheral.find("drive")
  local dados, caminho = lerDisco(d)
  if not dados or SEG.estado ~= "AUTORIZADO" or dados.serial ~= SEG.dados.serial then return false end
  dados.codigos = dados.codigos or {}
  dados.codigos[nome] = codigo and cifrarCodigo(SEG.chave, nome, codigo) or nil
  gravarTabela(caminho, dados)
  SEG.dados = dados
  SEG.codigos[nome] = codigo
  registrar(("CODIGO do missil %s %s no disquete %s"):format(nome, codigo and "gravado" or "apagado",
    dados.serial))
  return true
end

local function codigosMisseis()
  if not exigirAutorizacao("CODIGOS DOS MISSEIS") then return end
  while SEG.estado == "AUTORIZADO" do
    local nomes = {}
    for nome in pairs(SEG.codigos or {}) do table.insert(nomes, nome) end
    table.sort(nomes)
    local ops = {}
    for _, n in ipairs(nomes) do table.insert(ops, n .. "  (cifrado)") end
    table.insert(ops, "Gravar codigo de um missil")
    table.insert(ops, "Voltar")
    local i = menu("CODIGOS NO DISQUETE", ops, {
      { "O codigo e o mesmo do Ajuste 'Codigo de lancamento'", colors.lightGray },
      { "no computador do missil. Fica cifrado no disquete.", colors.lightGray },
    })
    if not i or i == #ops then return end
    if i <= #nomes then
      if confirmar("APAGAR CODIGO", "Apagar o codigo de '" .. nomes[i] .. "' do disquete?") then
        gravarCodigoDisco(nomes[i], nil)
      end
    else
      cabecalho("GRAVAR CODIGO")
      escrever(2, 3, "Nome do missil na rede (o que aparece na busca)", colors.yellow)
      local nome = perguntar(4, "> ", sel.nome)
      if nome and nome ~= "" then
        local codigo = perguntar(6, "Codigo:  ", nil, true)
        local repete = codigo and codigo ~= "" and perguntar(7, "Repita:  ", nil, true)
        if not codigo or codigo == "" then
          -- cancelado
        elseif #codigo > 32 then
          aviso("GRAVAR CODIGO", { "Maximo de 32 caracteres." }, colors.red)
        elseif repete ~= codigo then
          aviso("GRAVAR CODIGO", { "Os codigos nao conferem." }, colors.red)
        elseif gravarCodigoDisco(nome, codigo) then
          aviso("GRAVAR CODIGO", { "Codigo de '" .. nome .. "' gravado cifrado." }, colors.lime)
        else
          aviso("GRAVAR CODIGO", { "Nao foi possivel gravar: o disquete saiu?" }, colors.red)
        end
      end
    end
  end
end

local function trocarPin()
  if not exigirAutorizacao("TROCAR PIN") then return end
  local d = peripheral.find("drive")
  local dados, caminho = lerDisco(d)
  if not dados or dados.serial ~= SEG.dados.serial then
    aviso("TROCAR PIN", { "Insira o disquete da sessao." }, colors.red)
    return
  end
  cabecalho("TROCAR PIN")
  escrever(2, 3, ("Disquete %s  -  %s"):format(dados.serial, dados.operador), colors.yellow)
  local pin = pedirPin(5)
  if not pin then return end
  local sal = cripto.aleatorio(16)
  escrever(2, 10, "Cifrando...", colors.lightGray)
  local kek = cripto.derivar(pin, sal, VOLTAS_PIN)
  dados.sal, dados.voltas = cripto.hex(sal), VOLTAS_PIN
  dados.chave = cripto.hex(cripto.xor(SEG.chave, kek))
  dados.comPin = pin ~= ""
  gravarTabela(caminho, dados)
  local s = lerSeg()
  for _, r in ipairs(s.discos) do
    if r.serial == dados.serial then r.comPin = dados.comPin end
  end
  gravarTabela(ARQ_SEG, s)
  SEG.dados = dados
  registrar(("PIN TROCADO no disquete %s"):format(dados.serial))
  aviso("TROCAR PIN", { dados.comPin and "PIN trocado." or "PIN removido: basta inserir o disquete." },
    colors.lime)
end

local function verRegistro()
  local linhas = {}
  if fs.exists(ARQ_LOG) then
    local f = fs.open(ARQ_LOG, "r")
    local l = f.readLine()
    while l do
      table.insert(linhas, 1, l)
      l = f.readLine()
    end
    f.close()
  end
  if #linhas == 0 then linhas = { "Registro vazio." } end
  local cores = {}
  for i, l in ipairs(linhas) do
    local c = colors.white
    if l:find("ALERTA") or l:find("ERRADO") or l:find("BLOQUEIO") or l:find("REVOGADO")
      or l:find("NEGADO") or l:find("ABORT") then
      c = colors.red
    elseif l:find("AUTORIZADO") or l:find("EMITIDO") then
      c = colors.lime
    end
    cores[i] = { l, c }
  end
  visualizar("REGISTRO DE SEGURANCA", cores)
end

local function menuSeguranca()
  while true do
    local i = menu("SEGURANCA", function()
      return {
        SEG.estado == "PIN" and { "Digitar PIN do disquete", colors.yellow } or "Digitar PIN do disquete",
        "Encerrar sessao (travar a base)",
        "Emitir disquete de autorizacao",
        "Disquetes emitidos / revogar",
        "Codigos dos misseis no disquete",
        "Trocar PIN deste disquete",
        "Registro de seguranca",
        "Voltar",
      }
    end, function()
      local t, c = textoSeg()
      local info = { { "Estado: " .. t, c } }
      if SEG.dados then
        table.insert(info, { ("Disquete %s  operador %s"):format(SEG.dados.serial or "?",
          SEG.dados.operador or "?"), colors.lightGray })
      end
      local s = lerSeg()
      table.insert(info, { ("Disquetes ativos: %d"):format(discosAtivos(s)), colors.lightGray })
      return info
    end)
    if not i or i == 8 then return end
    if i == 1 then
      desbloquear()
    elseif i == 2 then
      if SEG.estado == "AUTORIZADO" then encerrarSessao("pelo operador", true) end
      aviso("SEGURANCA", { "Base travada.", "Retire e insira o disquete para autorizar de novo." },
        colors.orange)
    elseif i == 3 then
      emitirDisco()
    elseif i == 4 then
      listaDiscos()
    elseif i == 5 then
      codigosMisseis()
    elseif i == 6 then
      trocarPin()
    elseif i == 7 then
      verRegistro()
    end
  end
end

---------------------------------------------------------------- TELAS: CONFIGURACAO

local GRUPOS_CFG = {
  { "Desacoplagem (Redstone Link)", {
    { "desacoplar", "Desacoplar na ignicao" },
    { "saidaDesac", "Saida de redstone", "saida" },
    { "atrasoDesac", "Atraso apos ignicao (s)", 0, 10 },
    { "pulsoDesac", "Pulso (s, 0 = manter)", 0, 10 },
    { "inverterDesac", "Invertido (solta desligando)" },
    { "separacao", "Separou apos (blocos)", 1, 50 },
    { "tempoSeparacao", "Prazo para separar (s)", 2, 60 },
    { "abortarSemSeparar", "Abortar se nao separar" },
    { "_testeDesac", "TESTAR desacoplagem agora" },
  } },
  { "Lancamento e zona segura", {
    { "contagem", "Contagem da base (s)", 3, 60 },
    { "alcanceMin", "Alcance minimo (blocos)", 0, 5000 },
    { "alcanceMax", "Alcance maximo (blocos)", 50, 20000 },
    { "zonaExclusao", "Zona de exclusao da base", 0, 2000 },
    { "exigirCodigo", "Exigir codigo no missil" },
    { "_posBase", "Posicao da base" },
  } },
  { "Sirene e chave mestra", {
    { "sirene", "Sirene/luzes (saida)", "saida" },
    { "chaveMestra", "Chave mestra (entrada)", "saida" },
    { "_testeSirene", "TESTAR sirene (3 s)" },
  } },
  { "Seguranca", {
    { "tentativasPin", "Tentativas de PIN", 1, 10 },
    { "bloqueio", "Bloqueio apos erros (s)", 10, 3600 },
  } },
  { "Monitor", {
    { "escalaMonitor", "Escala do texto (0.5-5)", 0.5, 5 },
  } },
}

local function valorCfg(chave)
  if chave == "_posBase" then return E.basePos and coords(E.basePos) or "(missil)" end
  if chave:sub(1, 1) == "_" then return "" end
  local v = C[chave]
  if type(v) == "boolean" then return v and "SIM" or "NAO" end
  if v == "" then return "(nenhuma)" end
  return tostring(v)
end

local function escolherSaida(titulo, atual)
  local ops, valores = {}, {}
  table.insert(ops, "(nenhuma)")
  table.insert(valores, "")
  for _, lado in ipairs(rs.getSides()) do
    local ocupado = peripheral.isPresent(lado) and (" [" .. tostring(peripheral.getType(lado)) .. "]") or ""
    table.insert(ops, { lado .. ocupado, lado == atual and colors.yellow or colors.white })
    table.insert(valores, lado)
  end
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.hasType(nome, "redstone_relay") then
      for _, lado in ipairs(rs.getSides()) do
        local v = nome .. ":" .. lado
        table.insert(ops, { v, v == atual and colors.yellow or colors.white })
        table.insert(valores, v)
      end
    end
  end
  table.insert(ops, "Voltar")
  local i = menu(titulo, ops, { { "Lado do computador ou Redstone Relay", colors.lightGray } })
  if not i or i == #ops then return nil end
  return valores[i]
end

local function posicaoBase()
  cabecalho("POSICAO DA BASE")
  escrever(2, 3, "Usada na zona de exclusao (alvo longe da base).", colors.lightGray)
  escrever(2, 4, "Procurando GPS...", colors.yellow)
  local x, y, z = gps.locate(2)
  if x then
    if confirmar("POSICAO DA BASE", ("GPS: %d %d %d. Usar esta posicao?"):format(arred(x), arred(y), arred(z))) then
      E.basePos = { x = x, y = y, z = z }
      salvarEstado()
      return
    end
  end
  cabecalho("POSICAO DA BASE")
  escrever(2, 3, x and "Digite a posicao:" or "Sem GPS. Digite a posicao (F3):", colors.yellow)
  escrever(2, 4, "Vazio = usar a posicao do missil.", colors.lightGray)
  local function numero(yy, rotulo)
    local r = perguntar(yy, rotulo)
    return r and tonumber((r:gsub(",", ".")))
  end
  local bx = numero(6, "X: ")
  local by = bx and numero(7, "Y: ")
  local bz = by and numero(8, "Z: ")
  E.basePos = (bx and by and bz) and { x = bx, y = by, z = bz } or nil
  salvarEstado()
end

local function testeDesac()
  if E.voo and not E.voo.fim then
    aviso("TESTE", { "Ha um voo em andamento." }, colors.red)
    return
  end
  if not resolverRs(C.saidaDesac) then
    aviso("TESTE", { "Saida de redstone invalida: " .. tostring(C.saidaDesac) }, colors.red)
    return
  end
  if not confirmar("TESTE DE DESACOPLAGEM", "Vai mandar o sinal de SOLTAR pela saida '" .. C.saidaDesac
    .. "'. Um missil na plataforma sera solto! Continuar?") then
    return
  end
  registrar("TESTE de desacoplagem pela saida " .. C.saidaDesac)
  cabecalho("TESTE DE DESACOPLAGEM")
  escrever(2, 4, "SINAL DE SOLTAR ENVIADO", colors.red)
  saidaDesac(true)
  sleep(C.pulsoDesac > 0 and C.pulsoDesac or 2)
  saidaDesac(false)
  aviso("TESTE DE DESACOPLAGEM", { "Sinal voltou ao repouso.",
    "O Redstone Link do outro lado recebeu? A trava soltou?" }, colors.lime)
end

local function editarCfg(grupo)
  while true do
    local ops = {}
    for _, it in ipairs(grupo[2]) do
      table.insert(ops, ("%-28s %s"):format(it[2], valorCfg(it[1])))
    end
    table.insert(ops, "Voltar")
    local i = menu(grupo[1]:upper(), ops)
    if not i or i == #ops then return end
    local chave, nome, min, max = table.unpack(grupo[2][i])
    if chave == "_testeDesac" then
      testeDesac()
    elseif chave == "_testeSirene" then
      if C.sirene == "" then
        aviso("SIRENE", { "Escolha a saida da sirene antes." }, colors.orange)
      else
        saidaRs(C.sirene, true)
        cabecalho("SIRENE")
        escrever(2, 4, "SIRENE LIGADA", colors.red)
        sleep(3)
        sinalizar(false)
      end
    elseif chave == "_posBase" then
      posicaoBase()
    elseif min == "saida" then
      local v = escolherSaida(nome:upper(), C[chave])
      if v then
        if chave == "saidaDesac" then saidaDesac(false) end
        if chave == "sirene" then sinalizar(false) end
        C[chave] = v
        if chave == "saidaDesac" and v ~= "" then saidaDesac(false) end
      end
    elseif type(C[chave]) == "boolean" then
      C[chave] = not C[chave]
      if chave == "inverterDesac" then saidaDesac(false) end
    else
      cabecalho(grupo[1]:upper())
      escrever(2, 3, nome, colors.yellow)
      escrever(2, 4, ("Valor entre %s e %s"):format(min, max), colors.lightGray)
      local r = perguntar(6, "Novo valor: ", C[chave])
      local v = r and tonumber((r:gsub(",", ".")))
      if v and v >= min and v <= max then
        C[chave] = v
      else
        aviso("CONFIGURACAO", { "Valor invalido." }, colors.red)
      end
    end
    salvarCfg()
    if chave:sub(1, 1) ~= "_" then registrar(("CONFIG %s = %s"):format(chave, valorCfg(chave))) end
  end
end

local function configuracao()
  if not exigirAutorizacao("CONFIGURACAO") then return end
  while true do
    local ops = {}
    for _, g in ipairs(GRUPOS_CFG) do table.insert(ops, g[1]) end
    table.insert(ops, "Voltar")
    local i = menu("CONFIGURACAO DA BASE", ops)
    if not i or i == #ops then return end
    -- a sessao pode ter caido (disquete removido)
    if SEG.estado ~= "AUTORIZADO" and #lerSeg().discos > 0 then
      aviso("CONFIGURACAO", { "Autorizacao perdida: " .. textoSeg() }, colors.red)
      return
    end
    editarCfg(GRUPOS_CFG[i])
  end
end

---------------------------------------------------------------- TELAS: MISSIL E ALVO

local function procurar()
  cabecalho("PROCURAR MISSEIS")
  escrever(2, 3, "Procurando misseis em modo remoto...", colors.yellow)
  local ids = { rednet.lookup(SERVICO) }
  local achados = {}
  for _, id in ipairs(ids) do
    escrever(2, 5, ("Consultando #%d...   "):format(id), colors.lightGray)
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
    table.insert(ops, ("%-16s v%-4s %s"):format((a.st.nome or ("#" .. a.id)):sub(1, 16),
      tostring(a.st.versao), a.st.emVoo and "EM VOO" or (a.st.pronto and "PRONTO" or "NAO PRONTO")))
  end
  table.insert(ops, "Voltar")
  local i = menu("SELECIONAR MISSIL", ops)
  if not i or i == #ops then return end

  local a = achados[i]
  sel = { id = a.id, nome = a.st.nome }
  salvarEstado()
  registrar(("MISSIL SELECIONADO %s (#%d)"):format(a.st.nome or "?", a.id))
  local linhas = {
    "Selecionado: " .. (a.st.nome or ("#" .. a.id)),
    "Versao: v" .. tostring(a.st.versao)
      .. (versaoOk(a.st.versao) and "" or ("  (antiga: atualize para v" .. MISSIL_MIN .. ")")),
    "Preset: " .. tostring(a.st.preset),
    ("Motores: vetor %d, liquidos %d, solidos %d"):format(a.st.vet or 0, a.st.liq or 0, a.st.sol or 0),
    "Codigo de lancamento: " .. (a.st.precisaCodigo and "exigido" or "nenhum"),
    "Ordem cifrada: " .. (a.st.auth and "SIM (desafio HMAC)" or ("NAO (missil < v" .. MISSIL_CIFRA .. ")")),
  }
  if a.st.pos then
    table.insert(linhas, "Posicao: " .. coords(a.st.pos))
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
  registrar("ALVO DEFINIDO " .. coords(alvo))
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
    local st = statusSel()
    local ops = {}
    for _, a in ipairs(lista) do
      local d = st and st.pos and ("%6d b"):format(arred(distH(st.pos, a))) or ""
      table.insert(ops, ("%-16s %-16s %s"):format(a.nome:sub(1, 16), coords(a), d))
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
      registrar("ALVO DEFINIDO " .. a.nome .. " " .. coords(alvo))
      salvarEstado()
      return
    elseif j == 2 and confirmar("APAGAR ALVO", "Apagar '" .. a.nome .. "'?") then
      table.remove(lista, i)
      gravarAlvos(lista)
    end
  end
end

---------------------------------------------------------------- TELAS: VOO

local function telaVoo(v, confirmaAbort)
  cabecalho("VOO " .. v.nome)
  local put = pintor(term, COR)
  if v.fim then
    escrever(2, 2, ("ENCERRADO: %s"):format(v.fim):sub(1, W - 2), colors.red)
  end
  local mapa = W >= 46
  local L = linhasTelemetria(v)
  local larg = mapa and 30 or W - 2
  for i, l in ipairs(L) do
    local y = 2 + i
    if y > H - 5 then break end
    escrever(2, y, l[1], colors.lightGray)
    escrever(14, y, tostring(l[2]):sub(1, larg - 12), l[3])
  end
  if mapa then desenharMapa(put, 33, 3, W - 33, H - 8, dadosMapa(v)) end
  local T = v.T
  if v.dist0 and T and T.dist and v.dist0 > 0 then
    barra(put, 2, H - 4, W - 2, 1 - T.dist / v.dist0, colors.orange)
  end
  for i = 1, 3 do
    local e = v.eventos[i]
    if e then escrever(2, H - 4 + i, tostring(e):sub(1, W - 2), colors.lightGray) end
  end
  if v.fim then
    rodape("BACKSPACE volta")
  elseif confirmaAbort then
    rodape("APERTE A DE NOVO PARA ABORTAR")
  else
    rodape("A abortar  D desacoplar  F encerrar  BACKSPACE volta")
  end
end

local function acompanhar()
  local v = E.voo
  if not v then
    aviso("ACOMPANHAR VOO", { "Nenhum voo nesta sessao.",
      "Os voos anteriores estao no Historico." }, colors.orange)
    return
  end
  local confirmaAbort = nil
  local timer = os.startTimer(0)
  while true do
    local ev, p = os.pullEvent()
    if ev == "timer" and p == timer then
      if confirmaAbort and os.clock() - confirmaAbort > 3 then confirmaAbort = nil end
      telaVoo(v, confirmaAbort)
      timer = os.startTimer(0.25)
    elseif ev == "key" then
      if p == keys.backspace then
        os.cancelTimer(timer)
        return
      elseif not v.fim and p == keys.a then
        if confirmaAbort then
          abortarVoo(v, "operador")
          confirmaAbort = nil
        else
          confirmaAbort = os.clock()
        end
      elseif not v.fim and p == keys.d then
        if not desacoplar(v, "manual") then eventoVoo(v, "Desacoplagem: ja enviada ou saida invalida") end
      elseif not v.fim and p == keys.f then
        os.cancelTimer(timer)
        if confirmar("ENCERRAR", "Parar de acompanhar este voo? (o missil NAO e abortado)") then
          finalizarVoo(v, "acompanhamento encerrado pelo operador")
        end
        timer = os.startTimer(0)
      end
    end
  end
end

-- problemas que interrompem a contagem (confere direto, sem esperar a tarefa vigia)
local function problemaContagem()
  local d = peripheral.find("drive")
  if SEG.estado ~= "AUTORIZADO" or not d or not d.isDiskPresent() or d.getDiskID() ~= SEG.discoId then
    return "Disquete de autorizacao removido"
  end
  if C.chaveMestra ~= "" and not entradaRs(C.chaveMestra) then
    return "Chave mestra em SEGURO"
  end
  local st, idade = statusSel()
  if not st or idade > 8 then return "O missil parou de responder" end
  if st.emVoo or not st.pronto then return "Missil nao esta pronto" end
  if not modemSemFio() then return "Modem removido" end
  return nil
end

local function contagemTerminal()
  local restante = C.contagem
  E.contagem = { t = restante }
  sinalizar(true)
  registrar(("CONTAGEM T-%d iniciada: %s -> %s"):format(restante, nomeSel(), coords(alvo)))
  local put = pintor(term, COR)
  local timer = os.startTimer(1)
  local ultimoPing = os.clock()
  rednet.send(sel.id, { tipo = "ping" }, PROTOCOLO)

  local function abortar(motivo)
    os.cancelTimer(timer)
    E.contagem = nil
    sinalizar(false)
    registrar("HOLD / CONTAGEM ABORTADA: " .. motivo)
    aviso("HOLD - CONTAGEM ABORTADA", { motivo, "", "Nenhuma ordem foi enviada ao missil." }, colors.red)
    return false
  end

  while true do
    cabecalho("CONTAGEM TERMINAL")
    local txt = ("T-%02d"):format(restante)
    if COR then
      textoGrande(put, math.floor((W - 15) / 2) + 1, 3, txt, colors.red)
    else
      escrever(math.floor((W - #txt) / 2) + 1, 5, txt)
    end
    escrever(2, 9, "Missil", colors.lightGray)
    escrever(14, 9, nomeSel(), colors.yellow)
    escrever(2, 10, "Alvo", colors.lightGray)
    escrever(14, 10, ("%s  %s"):format(alvo.nome, coords(alvo)))
    escrever(2, 11, "Autorizacao", colors.lightGray)
    escrever(14, 11, ("%s  #%s"):format(SEG.dados.operador, SEG.dados.serial), colors.lime)
    escrever(2, 13, "Remover o disquete, desligar a chave mestra ou", colors.lightGray)
    escrever(2, 14, "perder o missil interrompe a contagem (HOLD).", colors.lightGray)
    rodape("A ou BACKSPACE = ABORTAR CONTAGEM")
    if restante <= 0 then break end

    local ev, p = os.pullEvent()
    if ev == "timer" and p == timer then
      local problema = problemaContagem()
      if problema then return abortar(problema) end
      restante = restante - 1
      E.contagem.t = restante
      if os.clock() - ultimoPing >= 3 then
        rednet.send(sel.id, { tipo = "ping" }, PROTOCOLO)
        ultimoPing = os.clock()
      end
      timer = os.startTimer(1)
    elseif ev == "disk_eject" or ev == "redstone" or ev == "peripheral_detach" then
      local problema = problemaContagem()
      if problema then return abortar(problema) end
    elseif ev == "key" and (p == keys.a or p == keys.backspace) then
      return abortar("Abortada pelo operador")
    end
  end
  return true
end

-- desafio cifrado (missil v4.7+) ou codigo aberto (missil antigo)
local function enviarOrdem(st, codigo)
  local ordem = { tipo = "lancar", alvo = { x = alvo.x, y = alvo.y, z = alvo.z } }
  if codigo and st.auth then
    rednet.send(sel.id, { tipo = "desafio" }, PROTOCOLO)
    local r = esperar(sel.id, { desafio = true }, 3)
    if not r or type(r.nonce) ~= "string" then return nil, "O missil nao respondeu ao desafio" end
    ordem.auth = cripto.hex(cripto.hmac(codigo, mensagemLancar(r.nonce, ordem.alvo, os.getComputerID())))
  elseif codigo then
    ordem.codigo = codigo
  end
  rednet.send(sel.id, ordem, PROTOCOLO)
  local resp = esperar(sel.id, { lancar_ok = true, lancar_negado = true }, 3)
  if not resp then return nil, "Sem resposta do missil" end
  return resp
end

local function lancar()
  if E.voo and not E.voo.fim then
    aviso("LANCAMENTO", { "Ha um voo em andamento.", "Acompanhe ou encerre antes." }, colors.orange)
    return
  end
  if not sel.id then
    aviso("LANCAMENTO", { "Selecione um missil primeiro." }, colors.orange)
    return
  end
  if not alvo then
    aviso("LANCAMENTO", { "Defina o alvo primeiro." }, colors.orange)
    return
  end
  if SEG.estado == "PIN" and not desbloquear() then return end
  if not verificacao(true) then return end

  local st = statusSel()
  local nome = st.nome or nomeSel()
  local codigo, origemCodigo = nil, "nenhum (missil sem codigo)"
  if st.precisaCodigo then
    codigo = codigoDoDisco(nome)
    origemCodigo = "cifrado no disquete"
    if not codigo then
      cabecalho("CODIGO DE LANCAMENTO")
      escrever(2, 3, "O codigo de '" .. nome .. "' nao esta no disquete.", colors.yellow)
      codigo = perguntar(5, "Codigo: ", nil, true)
      if not codigo or codigo == "" then return end
      origemCodigo = "digitado"
      if #codigo <= 32 and confirmar("CODIGO DE LANCAMENTO", "Gravar este codigo cifrado no disquete?") then
        gravarCodigoDisco(nome, codigo)
      end
    end
  end

  cabecalho("CONFIRMAR LANCAMENTO")
  local cinza = colors.lightGray
  local function linha(y, r, txt, c)
    escrever(2, y, r, cinza)
    escrever(16, y, tostring(txt):sub(1, W - 16), c)
  end
  linha(3, "Missil", ("%s  v%s  preset %s"):format(nome, tostring(st.versao), tostring(st.preset)), colors.yellow)
  linha(4, "Alvo", ("%s  (%s)"):format(alvo.nome, coords(alvo)), colors.yellow)
  if st.pos then
    linha(5, "Distancia", ("%d blocos  (altura %+d)"):format(arred(distH(st.pos, alvo)),
      math.floor(alvo.y - st.pos.y)))
  end
  linha(6, "Autorizacao", ("%s  disquete %s"):format(SEG.dados.operador, SEG.dados.serial), colors.lime)
  linha(7, "Codigo", origemCodigo .. (codigo and (st.auth and ", ordem HMAC" or ", ordem ABERTA") or ""),
    (codigo and not st.auth) and colors.orange or colors.white)
  linha(8, "Desacoplagem", C.desacoplar and ("%s, %.1fs apos a ignicao"):format(C.saidaDesac, C.atrasoDesac)
    or "manual", C.desacoplar and colors.white or colors.orange)
  linha(9, "Contagem", ("base %ds + missil %ss"):format(C.contagem, tostring(st.contagem or "?")))
  escrever(2, 11, "Digite LANCAR para iniciar a contagem:", colors.red)
  local r = perguntar(12, "> ", nil)
  if not r or r:upper() ~= "LANCAR" then
    registrar("LANCAMENTO cancelado na confirmacao")
    aviso("LANCAMENTO", { "Lancamento cancelado." }, colors.orange)
    return
  end
  registrar(("LANCAMENTO autorizado por %s (disquete %s): %s -> %s %s"):format(SEG.dados.operador,
    SEG.dados.serial, nome, alvo.nome, coords(alvo)))

  if not contagemTerminal() then return end

  cabecalho("LANCAMENTO")
  escrever(2, 4, "T-00  ENVIANDO ORDEM AO MISSIL...", colors.red)
  local operador, serial = SEG.dados.operador, SEG.dados.serial
  local resp, erro = enviarOrdem(st, codigo)
  E.contagem = nil
  if not resp or resp.tipo == "lancar_negado" then
    sinalizar(false)
    local motivo = resp and tostring(resp.motivo) or erro
    registrar("LANCAMENTO NEGADO: " .. motivo)
    aviso("LANCAMENTO NEGADO", { motivo }, colors.red)
    return
  end
  E.voo = { id = sel.id, nome = nome, alvo = { nome = alvo.nome, x = alvo.x, y = alvo.y, z = alvo.z },
    inicio = os.clock(), eventos = {}, trilha = {}, origem = st.pos, contagemMissil = st.contagem,
    operador = operador, serial = serial }
  registrar(("ORDEM ACEITA por %s"):format(nome))
  eventoVoo(E.voo, "Ordem aceita pelo missil")
  acompanhar()
end

local function historico()
  while true do
    local lista = lerTabela(ARQ_VOOS) or {}
    if #lista == 0 then
      aviso("HISTORICO DE VOOS", { "Nenhum voo registrado.",
        "Os voos entram aqui quando acompanhados pela base." }, colors.orange)
      return
    end
    local ops = {}
    for _, v in ipairs(lista) do
      table.insert(ops, ("%s %-10s %s"):format(v.quando, tostring(v.missil):sub(1, 10), tostring(v.motivo)))
    end
    table.insert(ops, "Voltar")
    local i = menu("HISTORICO DE VOOS", ops)
    if not i or i == #ops then return end
    local v = lista[i]
    cabecalho("VOO " .. tostring(v.quando))
    local put = pintor(term, COR)
    local larg = W >= 46 and 26 or W - 2
    local linhas = {
      { "Missil", tostring(v.missil) },
      { "Resultado", tostring(v.motivo) },
      { "Alvo", v.alvo and coords(v.alvo) or "?" },
      { "Tempo", ("%.0f s"):format(v.t or 0) },
      { "Dist final", v.dist and ("%.1f b"):format(v.dist) or "?" },
      { "Separacao", v.separado and "confirmada" or "nao confirmada" },
      { "Operador", tostring(v.operador or "?") },
      { "Disquete", tostring(v.serial or "?") },
    }
    for k, l in ipairs(linhas) do
      escrever(2, 2 + k, l[1], colors.lightGray)
      escrever(13, 2 + k, l[2]:sub(1, larg - 11))
    end
    if W >= 46 then
      desenharMapa(put, 29, 3, W - 29, H - 4, { origem = v.origem, alvo = v.alvo, trilha = v.trilha,
        base = E.basePos, pos = v.trilha and v.trilha[#v.trilha] })
    end
    rodape("Aperte qualquer tecla")
    os.pullEvent("key")
  end
end

---------------------------------------------------------------- MENU PRINCIPAL

local function painelPrincipal(x, y)
  for yy = 3, H - 1 do escrever(x - 2, yy, "|", colors.gray) end
  local larg = W - x
  local function lin(txt, c)
    if y < H then escrever(x, y, tostring(txt):sub(1, larg), c) end
    y = y + 1
  end
  local segT, segC = textoSeg()
  lin("SEGURANCA", colors.lightGray)
  lin(segT, segC)
  if SEG.estado == "AUTORIZADO" and SEG.dados then
    lin(("%s #%s"):format(SEG.dados.operador, SEG.dados.serial))
  end
  lin("MISSIL", colors.lightGray)
  local st, idade = statusSel()
  if not sel.id then
    lin("nenhum", colors.orange)
  else
    lin(nomeSel() .. (st and (" v" .. tostring(st.versao)) or ""))
    if not st or idade > 30 then
      lin("sem contato", colors.orange)
    else
      lin(st.emVoo and "EM VOO" or (st.pronto and "PRONTO" or "NAO PRONTO"),
        st.pronto and colors.lime or colors.orange)
    end
  end
  lin("ALVO", colors.lightGray)
  lin(alvo and alvo.nome or "nenhum", alvo and colors.white or colors.orange)
  if alvo then lin(coords(alvo)) end
  local L = sistemas()
  local nogo, primeiro = contarNoGo(L)
  lin("SISTEMAS", colors.lightGray)
  if y < H then
    local xx = x
    for _, it in ipairs(L) do
      if xx <= W then
        local _, _, bg = rotuloGo(it)
        escrever(xx, y, " ", nil, bg)
        xx = xx + 1
      end
    end
  end
  y = y + 1
  lin(nogo == 0 and "TODOS GO" or ("NO-GO: " .. primeiro), nogo == 0 and colors.lime or colors.red)
  if E.voo and not E.voo.fim then lin("VOO EM ANDAMENTO", colors.orange) end
end

local function principal()
  while true do
    local i = menu("BASE v" .. VERSAO, function()
      local emVoo = E.voo and not E.voo.fim
      return {
        "Verificacao GO/NO-GO",
        "Selecionar missil",
        "Definir alvo",
        "Alvos salvos",
        { "LANCAMENTO", SEG.estado == "AUTORIZADO" and colors.red or colors.gray },
        { "Acompanhar voo", emVoo and colors.orange or colors.white },
        { "Seguranca/disquetes", SEG.estado == "PIN" and colors.yellow or colors.white },
        "Configuracao",
        "Historico de voos",
        "Sair",
      }
    end, nil, painelPrincipal)
    if not i or i == 10 then return end

    local precisaModem = { [2] = true, [5] = true }
    if precisaModem[i] and not abrirModem() then
      aviso("ERRO", { "Coloque um modem sem fio (Ender Modem) na base." }, colors.red)
    else
      local acoes = { function() verificacao(false) end, procurar, definirAlvo, alvosSalvos, lancar,
        acompanhar, menuSeguranca, configuracao, historico }
      local ok, err = pcall(acoes[i])
      if not ok then
        if err == "Terminated" then error(err, 0) end
        E.contagem = nil
        aviso("ERRO", { tostring(err) }, colors.red)
      end
    end
    salvarEstado()
  end
end

---------------------------------------------------------------- TAREFAS DE FUNDO

-- recebe status e telemetria de todos os misseis
local function tarefaRede()
  while true do
    local id, msg = rednet.receive(PROTOCOLO)
    if type(msg) == "table" then
      if msg.tipo == "status" then
        E.frota[id] = { st = msg, visto = os.clock() }
      end
      local v = E.voo
      if v and id == v.id and not v.fim then
        if msg.tipo == "telemetria" then
          v.T = msg
          v.ultimo = os.clock()
          if not v.ignicao then v.ignicao = os.clock() end
          if msg.dist and not v.dist0 then v.dist0 = msg.dist end
          local p = msg.pos
          if type(p) == "table" and p.x then
            v.origem = v.origem or p
            local ult = v.trilha[#v.trilha]
            if not ult or dist3(ult, p) >= 2 then
              table.insert(v.trilha, { x = p.x, y = p.y, z = p.z })
              if #v.trilha > 400 then
                local menor = {}
                for k = 1, #v.trilha, 2 do table.insert(menor, v.trilha[k]) end
                v.trilha = menor
              end
            end
          end
        elseif msg.tipo == "evento" then
          local txt = tostring(msg.texto)
          if txt == "IGNICAO" and not v.ignicao then v.ignicao = os.clock() end
          if msg.fim then
            finalizarVoo(v, txt)
          else
            eventoVoo(v, txt)
          end
        end
      end
    end
  end
end

-- desacoplagem, separacao e perda de sinal
local function tarefaSequencia()
  while true do
    local v = E.voo
    if v and not v.fim then
      local t = os.clock()
      if C.desacoplar and v.ignicao and not v.desac and t >= v.ignicao + C.atrasoDesac then
        if not desacoplar(v, "auto") and not v.avisoSaida then
          v.avisoSaida = true
          eventoVoo(v, "DESACOPLAGEM FALHOU: saida invalida")
          registrar("ALERTA: desacoplagem sem saida valida")
        end
      end
      if v.desac and not v.desacSolto and C.pulsoDesac > 0 and t >= v.desac + C.pulsoDesac then
        saidaDesac(false)
        v.desacSolto = true
      end
      if v.desac and not v.separado and not v.falhaSep then
        local p = v.T and v.T.pos
        if p and v.origem and dist3(p, v.origem) >= C.separacao then
          v.separado = true
          eventoVoo(v, "SEPARACAO CONFIRMADA")
          registrar("SEPARACAO CONFIRMADA: " .. v.nome)
        elseif t >= v.desac + C.tempoSeparacao then
          v.falhaSep = true
          eventoVoo(v, "FALHA DE SEPARACAO")
          registrar("ALERTA: falha de separacao de " .. v.nome)
          if C.abortarSemSeparar then abortarVoo(v, "falha de separacao") end
        end
      end
      if not v.ignicao and not v.avisoIgn and t > v.inicio + (tonumber(v.contagemMissil) or 5) + 15 then
        v.avisoIgn = true
        eventoVoo(v, "SEM IGNICAO: o missil nao mandou dados")
      end
      local ultimo = v.ultimo or v.inicio
      if t - ultimo > 60 then
        finalizarVoo(v, "SINAL PERDIDO")
      end
    end
    sleep(0.1)
  end
end

-- seguranca: confere o disquete na hora em que entra ou sai
local function tarefaVigia()
  local timer = os.startTimer(0)
  while true do
    local ev, p = os.pullEvent()
    if ev == "disk" or ev == "disk_eject" or ev == "peripheral" or ev == "peripheral_detach" then
      atualizarSeguranca(true)
    elseif ev == "timer" and p == timer then
      atualizarSeguranca(false)
      timer = os.startTimer(1)
    end
  end
end

-- status dos misseis da rede (para o painel e o monitor)
local function tarefaFrota()
  while true do
    if abrirModem() and not E.contagem then
      local ids = { rednet.lookup(SERVICO) }
      for _, id in ipairs(ids) do
        if not (E.voo and not E.voo.fim and E.voo.id == id) then
          rednet.send(id, { tipo = "ping" }, PROTOCOLO)
        end
      end
    end
    sleep(15)
  end
end

---------------------------------------------------------------- MONITOR

local MON = { pagina = 1 }

local function faixaMon(put, y, w, txt, fg, bg)
  put(1, y, string.rep(" ", w), fg, bg)
  put(math.max(1, math.floor((w - #txt) / 2) + 1), y, txt, fg, bg)
end

local function estadoGeral(L)
  local v = E.voo
  if E.contagem then return ("CONTAGEM  T-%02d"):format(E.contagem.t), colors.white, colors.red end
  if v and not v.fim then
    return "MISSIL EM VOO  -  " .. tostring(v.T and v.T.fase or "IGNICAO"), colors.black, colors.orange
  end
  if v and v.fim and os.clock() - v.fimClock < 120 then
    return "VOO ENCERRADO  -  " .. tostring(v.fim), colors.white, colors.gray
  end
  if SEG.estado ~= "AUTORIZADO" then return "SEGURO  -  " .. textoSeg(), colors.black, colors.yellow end
  local nogo = contarNoGo(L)
  if nogo > 0 then return ("NO-GO  -  %d SISTEMA(S)"):format(nogo), colors.white, colors.red end
  return "PRONTO  -  TODOS OS SISTEMAS GO", colors.black, colors.lime
end

local function monitorStatus(put, w, h, L)
  local col = math.max(math.floor(w / 2), w - 32)
  put(2, 4, "SISTEMAS", colors.lightGray)
  local y = 5
  for _, it in ipairs(L) do
    if y > h then break end
    local rot, fg, bg = rotuloGo(it)
    put(2, y, rot, fg, bg)
    put(8, y, it.nome, colors.white)
    put(21, y, it.detalhe:sub(1, math.max(0, col - 21)), it.go and colors.lightGray or bg)
    y = y + 1
  end
  local x = col + 2
  y = 4
  local function sec(t)
    if y > 4 then y = y + 1 end
    put(x, y, t, colors.lightGray)
    y = y + 1
  end
  local function lin(t, c)
    put(x, y, tostring(t):sub(1, w - x), c or colors.white)
    y = y + 1
  end
  local segT, segC = textoSeg()
  sec("SEGURANCA")
  lin(segT, segC)
  if SEG.dados then
    lin("operador " .. tostring(SEG.dados.operador))
    lin("disquete " .. tostring(SEG.dados.serial))
  end
  sec("MISSIL")
  local st = statusSel()
  lin(nomeSel() .. (st and ("  v" .. tostring(st.versao)) or ""), sel.id and colors.yellow or colors.orange)
  if st and st.pos then lin("pos " .. coords(st.pos)) end
  sec("ALVO")
  lin(alvo and (alvo.nome .. "  " .. coords(alvo)) or "nenhum", alvo and colors.white or colors.orange)
  if alvo and st and st.pos then lin(("%d blocos do missil"):format(arred(distH(st.pos, alvo)))) end
  sec("FROTA NA REDE")
  local ids = {}
  for id in pairs(E.frota) do table.insert(ids, id) end
  table.sort(ids)
  if #ids == 0 then lin("nenhum missil em modo remoto", colors.gray) end
  for _, id in ipairs(ids) do
    if y > h - 2 then break end
    local f = E.frota[id]
    local idade = os.clock() - f.visto
    local s = idade > 45 and "sem contato" or (f.st.emVoo and "EM VOO" or (f.st.pronto and "PRONTO" or "NAO PRONTO"))
    lin(("%-14s v%-4s %s"):format(tostring(f.st.nome or ("#" .. id)):sub(1, 14), tostring(f.st.versao), s),
      idade > 45 and colors.gray or (f.st.pronto and colors.lime or colors.orange))
  end
  if y <= h - 1 then
    sec("REGISTRO")
    for _, l in ipairs(E.log) do
      if y > h then break end
      lin(l, colors.lightGray)
    end
  end
end

local function monitorMissao(put, w, h)
  local v = E.voo
  local ativo = v and not v.fim
  local mapW = math.floor(w * 0.5)
  local perfilH = h >= 22 and 7 or 0
  local mapH = h - 3 - perfilH
  local dados = dadosMapa(E.contagem and nil or v)
  put(2, 3, "MAPA TATICO", colors.lightGray)
  desenharMapa(put, 1, 4, mapW, mapH - 1, dados)
  if perfilH > 0 then
    put(2, 3 + mapH, "PERFIL DE ALTITUDE", colors.lightGray)
    desenharPerfil(put, 1, 4 + mapH, mapW, perfilH - 1, dados)
  end
  for yy = 3, h do put(mapW + 1, yy, "|", colors.gray) end
  local x = mapW + 3
  local rw = w - x
  if E.contagem then
    textoGrande(put, x, 4, ("T-%02d"):format(E.contagem.t), colors.red)
    local y = 10
    local function lin(r, t, c)
      put(x, y, r, colors.lightGray)
      put(x + 12, y, tostring(t):sub(1, math.max(0, rw - 12)), c)
      y = y + 1
    end
    lin("MISSIL", nomeSel(), colors.yellow)
    lin("ALVO", alvo and coords(alvo) or "?")
    lin("OPERADOR", SEG.dados and SEG.dados.operador or "?", colors.lime)
    lin("DESACOPLAR", C.desacoplar and (C.saidaDesac .. " +" .. C.atrasoDesac .. "s") or "manual")
    return
  end
  local y = 3
  put(x, y, (v.nome .. (ativo and "" or "  -  ENCERRADO")):sub(1, rw), ativo and colors.yellow or colors.red)
  y = y + 1
  for _, l in ipairs(linhasTelemetria(v)) do
    if y > h - 5 then break end
    put(x, y, l[1], colors.lightGray)
    put(x + 13, y, tostring(l[2]):sub(1, math.max(0, rw - 13)), l[3])
    y = y + 1
  end
  local T = v.T
  if v.dist0 and T and T.dist and v.dist0 > 0 and y <= h - 4 then
    barra(put, x, y, math.max(4, rw), 1 - T.dist / v.dist0, colors.orange)
    y = y + 1
  end
  if v.fim then
    put(x, y, tostring(v.fim):sub(1, rw), colors.red)
    y = y + 1
  end
  for _, e in ipairs(v.eventos) do
    if y > h then break end
    put(x, y, tostring(e):sub(1, rw), colors.lightGray)
    y = y + 1
  end
end

local function monitorCompacto(put, w, h, L)
  local y = 1
  local function lin(t, c)
    if y <= h then put(1, y, tostring(t):sub(1, w), c) end
    y = y + 1
  end
  local txt, _, bg = estadoGeral(L)
  lin(txt, bg)
  lin("SEG: " .. textoSeg())
  lin("MSL: " .. nomeSel())
  lin("ALVO: " .. (alvo and coords(alvo) or "-"))
  local v = E.voo
  if v then
    for _, l in ipairs(linhasTelemetria(v)) do lin(l[1] .. " " .. l[2], l[3]) end
  else
    for _, it in ipairs(L) do lin((it.go and "GO    " or "NO-GO ") .. it.nome, it.go and colors.lime or colors.red) end
  end
end

local function desenharMonitor(win, w, h, colorido)
  local put = pintor(win, colorido)
  win.setBackgroundColor(colors.black)
  win.clear()
  local L = sistemas()
  if w < 36 or h < 12 then
    monitorCompacto(put, w, h, L)
    return
  end
  local v = E.voo
  local missao = E.contagem or (v and (not v.fim or os.clock() - v.fimClock < 120))
  put(1, 1, string.rep(" ", w), colors.white, colors.gray)
  put(2, 1, "BLOCKFORGE MILITAR", colors.yellow, colors.gray)
  put(21, 1, "CENTRO DE CONTROLE DE MISSOES", colors.white, colors.gray)
  local relogio = os.date("%H:%M:%S")
  put(w - #relogio, 1, relogio, colors.lightGray, colors.gray)
  local txt, fg, bg = estadoGeral(L)
  faixaMon(put, 2, w, txt, fg, bg)
  if missao then
    monitorMissao(put, w, h)
  elseif MON.pagina == 2 then
    put(2, 3, "MAPA TATICO  (toque para voltar)", colors.lightGray)
    desenharMapa(put, 1, 4, w, h - 3, dadosMapa(nil))
  else
    monitorStatus(put, w, h, L)
  end
end

local function tarefaMonitor()
  while true do
    local nome = monitorPresente()
    for _, n in ipairs(peripheral.getNames()) do
      if peripheral.hasType(n, "monitor") and peripheral.call(n, "isColor") then nome = n end
    end
    if not nome then
      local timer = os.startTimer(5)
      repeat
        local ev, p = os.pullEvent()
      until ev == "peripheral" or (ev == "timer" and p == timer)
    else
      local mon = peripheral.wrap(nome)
      local escala = C.escalaMonitor
      pcall(mon.setTextScale, escala)
      local w, h = mon.getSize()
      local win = window.create(mon, 1, 1, w, h, false)
      local colorido = mon.isColor()
      local timer = os.startTimer(0)
      while true do
        local ev, p = os.pullEvent()
        if ev == "timer" and p == timer then
          if C.escalaMonitor ~= escala or not peripheral.isPresent(nome) then break end
          win.setVisible(false)
          desenharMonitor(win, w, h, colorido)
          win.setVisible(true)
          timer = os.startTimer(0.5)
        elseif ev == "monitor_touch" and p == nome then
          MON.pagina = MON.pagina % 2 + 1
          timer = os.startTimer(0)
        elseif ev == "monitor_resize" or ev == "peripheral" or (ev == "peripheral_detach" and p == nome) then
          break
        end
      end
    end
  end
end

-- tarefa de fundo que nao derruba a base se der erro
local function protegida(nome, fn)
  return function()
    while true do
      local ok, err = pcall(fn)
      if not ok then
        if err == "Terminated" then error(err, 0) end
        registrar(("ERRO na tarefa %s: %s"):format(nome, tostring(err)))
        sleep(2)
      end
    end
  end
end

---------------------------------------------------------------- INICIO

carregarCfg()
carregarEstado()
math.randomseed(os.epoch("utc") % 2147483647)
abrirModem()
repouso()
registrar("BASE v" .. VERSAO .. " iniciada")

local ok, err = pcall(parallel.waitForAny, principal,
  protegida("rede", tarefaRede), protegida("sequencia", tarefaSequencia),
  protegida("vigia", tarefaVigia), protegida("frota", tarefaFrota),
  protegida("monitor", tarefaMonitor))

sinalizar(false)
if E.voo and not E.voo.fim and E.voo.desac and not E.voo.desacSolto then saidaDesac(false) end
local mon = monitorPresente()
if mon then
  pcall(function()
    local m = peripheral.wrap(mon)
    m.setBackgroundColor(colors.black)
    m.clear()
    m.setCursorPos(2, 2)
    m.setTextColor(colors.gray)
    m.write("BASE DESLIGADA")
  end)
end
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
  elseif p.chave == "base" then
    escrever(2, 8, "Primeiro: Seguranca > Emitir disquete.", colors.lightGray)
    escrever(2, 9, "Sem disquete de autorizacao a base nao lanca.", colors.lightGray)
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
