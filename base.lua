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
