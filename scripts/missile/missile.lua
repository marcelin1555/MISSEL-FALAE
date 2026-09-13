-- missil.lua : BlockForge Militar - Controle de Missil
-- Create Aeronautics + Create Propulsion: Simulated + CC: Tweaked
-- uso: missil            (menu)
--      missil lancar     (vai direto para o lancamento)

local VERSAO = "2.0"
local argumentos = { ... }
local ARQ_CONFIG = "/bfm_config.txt"
local PASTA_PRESETS = "bfm_presets"
local LIMIAR = 3 -- inclinacao minima (graus) aceita nas calibracoes
local RADIO_PROTOCOLO = "BFM_REMOTE_1"
local RADIO_COMANDO = 4210
local RADIO_TELEMETRIA = 4211
local RADIO_TIMEOUT = 3
local radio = nil

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
  escrever(2, 3, pergunta, colors.yellow)
  rodape("S = sim   N = nao")
  while true do
    local _, ch = os.pullEvent("char")
    ch = ch:lower()
    if ch == "s" then return true end
    if ch == "n" then return false end
  end
end

local function perguntar(y, rotulo, padrao)
  escrever(2, y, rotulo, colors.lightGray)
  term.setCursorPos(2 + #rotulo, y)
  cor(colors.white)
  return read(nil, nil, nil, padrao ~= nil and tostring(padrao) or nil)
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

---------------------------------------------------------------- CONFIG

local PADRAO = {
  nome = "sem_nome",
  -- gimbal
  offX = 0, offZ = 0,
  eixoN = 1, sinalN = 1, eixoL = 2, sinalL = 1,
  gimbalOk = false,
  -- bocal
  eixoX = 2, sinalX = 1, eixoY = 1, sinalY = 1,
  bocalOk = false,
  -- voo
  kp = 0.04, kd = 0.015, inverter = false,
  empuxoVetor = 0.5, acelerador = 1.0, usarSolidos = true,
  abortar = 60, contagem = 3,
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
    if PADRAO[k] ~= nil and type(v) == type(PADRAO[k]) then cfg[k] = v end
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

local P = { vetores = {}, motores = {}, modem = nil }

local function temTipo(nome, lista)
  for _, t in ipairs(lista) do
    if peripheral.hasType(nome, t) then return true end
  end
  return false
end

local function detectar()
  P = { gimbal = nil, drive = nil, vetores = {}, motores = {}, modem = nil }
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.hasType(nome, "modem") then
      local candidato = peripheral.wrap(nome)
      if candidato and candidato.isWireless and candidato.isWireless() then
        P.modem = P.modem or { nome = nome, p = candidato }
      end
    elseif peripheral.hasType(nome, "gimbal_sensor") then
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
  radio = P.modem and P.modem.p or nil
  if radio then radio.open(RADIO_COMANDO) end
end

local function contar(classe)
  local n = 0
  for _, m in ipairs(P.motores) do
    if m.classe == classe then n = n + 1 end
  end
  return n
end

local function radioEnviar(tipo, dados)
  if not radio then return end
  local pacote = { protocolo = RADIO_PROTOCOLO, tipo = tipo, dados = dados or {} }
  pcall(radio.transmit, RADIO_TELEMETRIA, RADIO_COMANDO, textutils.serialize(pacote))
end

local function radioReceber(timeout)
  if not radio then return nil end
  local timer = os.startTimer(timeout or RADIO_TIMEOUT)
  while true do
    local ev, p1, canal, _, mensagem = os.pullEvent()
    if ev == "modem_message" and canal == RADIO_COMANDO then
      local ok, pacote = pcall(textutils.unserialize, mensagem)
      if ok and type(pacote) == "table" and pacote.protocolo == RADIO_PROTOCOLO then
        return pacote
      end
    elseif ev == "timer" and p1 == timer then
      return nil
    end
  end
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

local function vetorComando(x, y)
  for _, v in ipairs(P.vetores) do pcall(v.p.setVector, x, y) end
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
    "Pronto para lancar. Dica: salve um preset!",
  }, colors.lime)
end

---------------------------------------------------------------- AJUSTES

local AJUSTES = {
  { chave = "empuxoVetor", nome = "Empuxo do vetor (0-1)",     min = 0, max = 1 },
  { chave = "acelerador",  nome = "Acelerador liq/ion (0-1)",  min = 0, max = 1 },
  { chave = "usarSolidos", nome = "Usar motores solidos" },
  { chave = "kp",          nome = "KP forca da correcao",      min = 0, max = 1 },
  { chave = "kd",          nome = "KD amortecimento",          min = 0, max = 1 },
  { chave = "inverter",    nome = "Inverter correcao" },
  { chave = "abortar",     nome = "Abortar acima de (graus)",  min = 5, max = 90 },
  { chave = "contagem",    nome = "Contagem regressiva (s)",   min = 0, max = 30 },
}

local function formatar(v)
  if type(v) == "boolean" then return v and "SIM" or "NAO" end
  return tostring(v)
end

local function ajustes()
  while true do
    local ops = {}
    for _, a in ipairs(AJUSTES) do
      table.insert(ops, ("%-26s %s"):format(a.nome, formatar(cfg[a.chave])))
    end
    table.insert(ops, "Voltar")
    local i = menu("AJUSTES", ops)
    if not i or i == #ops then return end

    local a = AJUSTES[i]
    if type(cfg[a.chave]) == "boolean" then
      cfg[a.chave] = not cfg[a.chave]
    else
      cabecalho("AJUSTES")
      escrever(2, 3, a.nome, colors.yellow)
      escrever(2, 4, ("Valor entre %s e %s"):format(a.min, a.max), colors.lightGray)
      local r = perguntar(6, "Novo valor: ", cfg[a.chave])
      local v = r and tonumber((r:gsub(",", ".")))
      if v and v >= a.min and v <= a.max then
        cfg[a.chave] = v
      else
        aviso("AJUSTES", { "Valor invalido." }, colors.red)
      end
    end
    salvarConfig()
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
        if not fs.exists(caminho) or confirmar("SALVAR PRESET", "'" .. nome .. "' ja existe. Substituir?") then
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
          cfg = copiar(PADRAO)
          aplicar(dados)
          cfg.nome = nome
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
    if #P.motores == 0 then
      escrever(2, y, "Nenhum motor encontrado", colors.orange)
      y = y + 1
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
  local x, y, pot = 0, 0, 0
  local PASSO = 0.1
  local function lim(v, a, b) return math.max(a, math.min(b, v)) end
  local v = P.vetores[1].p

  while true do
    vetorComando(x, y)
    vetorEmpuxo(pot)
    cabecalho("BOCAL MANUAL")
    escrever(2, 3, "SETAS   inclinar o bocal", colors.lightGray)
    escrever(2, 4, "W / S   empuxo do vetor", colors.lightGray)
    escrever(2, 5, "ESPACO  centralizar", colors.lightGray)
    escrever(2, 7, ("Alvo    X %5.2f   Y %5.2f"):format(x, y))
    escrever(2, 8, ("Atual   X %5.2f   Y %5.2f"):format(
      chamar(v, "getVectorX") or 0, chamar(v, "getVectorY") or 0))
    escrever(2, 9, ("Empuxo  %d%%"):format(math.floor(pot * 100 + 0.5)),
      pot > 0 and colors.orange or colors.white)
    rodape("BACKSPACE sai (zera o bocal)")

    local timer = os.startTimer(0.2)
    local ev, k = os.pullEvent()
    if ev == "key" then
      if k == keys.left then x = lim(x - PASSO, -1, 1)
      elseif k == keys.right then x = lim(x + PASSO, -1, 1)
      elseif k == keys.up then y = lim(y + PASSO, -1, 1)
      elseif k == keys.down then y = lim(y - PASSO, -1, 1)
      elseif k == keys.w then pot = lim(pot + PASSO, 0, 1)
      elseif k == keys.s then pot = lim(pot - PASSO, 0, 1)
      elseif k == keys.space then x, y = 0, 0
      elseif k == keys.backspace then return end
    end
    os.cancelTimer(timer)
  end
end

local function testes()
  while true do
    local i = menu("TESTES", { "Painel de status (ao vivo)", "Controle manual do bocal", "Voltar" })
    if not i or i == 3 then return end
    if i == 1 then painel() else bocalManual() end
    desligarTudo()
  end
end

---------------------------------------------------------------- VOO

local function lim1(v) return math.max(-1, math.min(1, v)) end

local function desenharHorizonte(n, l)
  -- caixa de 13x7 com o centro em (8, 6)
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

  local px = 8 + math.floor(l / 30 * 5 + 0.5)
  local py = 6 - math.floor(n / 30 * 2 + 0.5)
  px = math.max(3, math.min(13, px))
  py = math.max(4, math.min(8, py))
  local inc = math.max(math.abs(n), math.abs(l))
  local c = colors.lime
  if inc > 25 then c = colors.red elseif inc > 10 then c = colors.yellow end
  escrever(px, py, "@", c)
end

local function voo(remoto)
  detectar()
  if not exigir(true) then return end

  local ativos = {}
  for _, m in ipairs(P.motores) do
    if m.classe ~= "solido" or cfg.usarSolidos then table.insert(ativos, m) end
  end

  -- checklist local; o modo remoto confirma a prontidao na estacao
  if not remoto then
  cabecalho("LANCAMENTO")
  local function item(y, rotulo, valor, bom)
    escrever(2, y, rotulo, colors.lightGray)
    escrever(24, y, valor, bom and colors.lime or colors.orange)
  end
  item(3, "Preset", cfg.nome, true)
  item(4, "Gimbal calibrado", cfg.gimbalOk and "SIM" or "NAO", cfg.gimbalOk)
  item(5, "Bocal calibrado", cfg.bocalOk and "SIM" or "NAO", cfg.bocalOk)
  item(6, "Vector thrusters", tostring(#P.vetores), true)
  item(7, "Motores liquidos", tostring(contar("liquido")), true)
  item(8, "Motores solidos", ("%d%s"):format(contar("solido"),
    cfg.usarSolidos and "" or " (desligados)"), true)
  item(9, "Motores ion/criativo", tostring(contar("ion") + contar("criativo")), true)
  item(10, "Empuxo vetor / acel.", ("%d%% / %d%%"):format(
    math.floor(cfg.empuxoVetor * 100 + 0.5), math.floor(cfg.acelerador * 100 + 0.5)), true)
  if #ativos == 0 then
    escrever(2, 12, "Nenhum motor principal: so o vetor vai empurrar.", colors.orange)
  end
  if contar("solido") > 0 and cfg.usarSolidos then
    escrever(2, 13, "Solidos NAO apagam depois de acesos!", colors.orange)
  end
  rodape("ENTER lancar   BACKSPACE cancelar")
    while true do
      local _, k = os.pullEvent("key")
      if k == keys.enter then break end
      if k == keys.backspace then return end
    end
  end

  -- contagem regressiva
  for i = cfg.contagem, 1, -1 do
    cabecalho("LANCAMENTO")
    local txt = ("T-%d"):format(i)
    escrever(math.floor((W - #txt) / 2) + 1, math.floor(H / 2), txt, colors.yellow)
    rodape("BACKSPACE cancela")
    local timer = os.startTimer(1)
    while true do
      local ev, p = os.pullEvent()
      if ev == "timer" and p == timer then break end
      if ev == "key" and p == keys.backspace then
        aviso("LANCAMENTO", { "Lancamento cancelado." }, colors.orange)
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

  local inicio = os.clock()
  local incMax = 0
  local motivo = "Fim"
  local ehAtivo = {}
  for _, m in ipairs(ativos) do ehAtivo[m] = true end

  -- estado compartilhado entre as tarefas
  local E = { n = 0, l = 0, giro = 0, cx = 0, cy = 0, hz = 0 }

  local function enviarEstadoRemoto(total)
    radioEnviar("telemetria", {
      status = "voo", norte = E.n, leste = E.l, giro = E.giro,
      bocalX = E.cx, bocalY = E.cy, empuxo = total, hz = E.hz,
      tempo = os.clock() - inicio, anguloMaximo = incMax,
    })
  end

  -- As chamadas a perifericos descartam eventos enquanto esperam o jogo,
  -- entao o voo roda em 3 tarefas paralelas, cada uma com seu proprio sleep.

  -- TAREFA 1: controle PD (so gimbal + vetor, o mais rapido possivel)
  local function controle()
    local n0, l0 = lerAngulos()
    local t0 = os.clock()
    local ultX, ultY
    local ciclos, tHz = 0, t0
    while true do
      sleep(0.05)
      local n, l = lerAngulos()
      local t = os.clock()
      local dt = math.max(t - t0, 0.05)
      local rn, rl = (n - n0) / dt, (l - l0) / dt
      n0, l0, t0 = n, l, t

      local inc = math.max(math.abs(n), math.abs(l))
      incMax = math.max(incMax, inc)
      if inc > cfg.abortar then
        motivo = ("ABORTADO: inclinacao de %.0f graus"):format(inc)
        return
      end

      local ang, giro = { n, l }, { rn, rl }
      local inv = cfg.inverter and -1 or 1
      local tx = ang[cfg.eixoX] * cfg.sinalX
      local ty = ang[cfg.eixoY] * cfg.sinalY
      local gx = giro[cfg.eixoX] * cfg.sinalX
      local gy = giro[cfg.eixoY] * cfg.sinalY
      local cx = lim1(-inv * (cfg.kp * tx + cfg.kd * gx))
      local cy = lim1(-inv * (cfg.kp * ty + cfg.kd * gy))

      -- so manda para o bocal se mudou (cada chamada custa tempo)
      if not ultX or math.abs(cx - ultX) > 0.01 or math.abs(cy - ultY) > 0.01 then
        vetorComando(cx, cy)
        ultX, ultY = cx, cy
      end

      E.n, E.l, E.cx, E.cy = n, l, cx, cy
      E.giro = math.max(math.abs(rn), math.abs(rl))
      ciclos = ciclos + 1
      if t - tHz >= 1 then
        E.hz = ciclos / (t - tHz)
        ciclos, tHz = 0, t
      end
    end
  end

  -- TAREFA 2: telemetria, combustivel e tela (devagar)
  local function telemetria()
    while true do
      local algum, total, linhas = false, 0, {}
      for _, m in ipairs(P.motores) do
        local kn = empuxoKN(m)
        total = total + kn
        local txt, tem = "desligado", false
        if ehAtivo[m] then
          txt, tem = combustivel(m)
          if tem then algum = true end
        end
        table.insert(linhas, { m = m, kn = kn, txt = txt, tem = tem })
      end
      enviarEstadoRemoto(total)
      if #ativos > 0 and not algum then
        motivo = "Combustivel esgotado"
        return
      end

      cabecalho(("EM VOO  T+%.1fs"):format(os.clock() - inicio))
      desenharHorizonte(E.n, E.l)
      escrever(18, 3, ("Norte   %6.1f"):format(E.n))
      escrever(18, 4, ("Leste   %6.1f"):format(E.l))
      escrever(18, 5, ("Giro    %6.0f /s"):format(E.giro))
      escrever(18, 7, ("Bocal X %6.2f"):format(E.cx), colors.lightBlue)
      escrever(18, 8, ("Bocal Y %6.2f"):format(E.cy), colors.lightBlue)
      escrever(18, 9, ("Empuxo  %6.2f kN"):format(total), colors.orange)
      escrever(18, 10, ("Controle %5.1f Hz"):format(E.hz),
        E.hz >= 5 and colors.lime or colors.red)
      local y = 12
      for _, li in ipairs(linhas) do
        if y >= H - 1 then break end
        escrever(2, y, ("%s %-12s %7.2f kN  %s"):format(li.m.rotulo, li.m.nome:sub(1, 12),
          li.kn, li.txt), li.tem and colors.white or colors.red)
        y = y + 1
      end
      rodape("X ou BACKSPACE = ABORTAR")
      sleep(0.5)
    end
  end

  -- TAREFA 3: teclado
  local function teclado()
    while true do
      local _, k = os.pullEvent("key")
      if k == keys.x or k == keys.backspace then
        motivo = "Abortado pelo operador"
        return
      end
    end
  end

  local function comandoRemoto()
    while true do
      local pacote = radioReceber(0.5)
      if pacote and pacote.tipo == "comando" then
        local acao = pacote.dados and pacote.dados.acao
        if acao == "abortar" then
          motivo = "Abortado pela estacao"
          return
        elseif acao == "ping" then
          radioEnviar("pong", { status = "voo", tempo = os.clock() - inicio })
        end
      end
    end
  end

  local ok, err = pcall(parallel.waitForAny, controle, telemetria, teclado, comandoRemoto)

  desligarTudo()
  if not ok then
    motivo = err == "Terminated" and "Interrompido (CTRL+T)" or ("Erro: " .. tostring(err))
  end

  local linhas = {
    motivo,
    "",
    ("Tempo de voo:       %.1f s"):format(os.clock() - inicio),
    ("Inclinacao maxima:  %.1f graus"):format(incMax),
  }
  if contar("solido") > 0 and cfg.usarSolidos then
    table.insert(linhas, "")
    table.insert(linhas, "Solidos podem continuar queimando!")
  end
  aviso("VOO ENCERRADO", linhas, ok and colors.white or colors.red)
end

local function modoRemoto()
  detectar()
  if not radio then
    aviso("RADIO", { "Modem wireless nao encontrado.", "Conecte um modem ao computador." }, colors.red)
    return
  end
  radioEnviar("pronto", { status = "aguardando", versao = VERSAO })
  while true do
    local pacote = radioReceber(30)
    if pacote and pacote.tipo == "comando" then
      local acao = pacote.dados and pacote.dados.acao
      if acao == "ping" then
        radioEnviar("pong", { status = "aguardando", versao = VERSAO })
      elseif acao == "lancar" then
        radioEnviar("estado", { status = "iniciando" })
        voo(true)
        radioEnviar("estado", { status = "encerrado" })
      elseif acao == "sair" then
        radioEnviar("estado", { status = "encerrado" })
        return
      end
    end
  end
end

---------------------------------------------------------------- MENU

local function principal()
  while true do
    detectar()
    local extra = contar("criativo") > 0 and ("  Cri " .. contar("criativo")) or ""
    local _, noDisco = localPresets()
    local info = {
      { ("Gimbal %s  Vetor %d  Liq %d  Sol %d  Ion %d%s"):format(
          P.gimbal and "OK" or "--", #P.vetores, contar("liquido"),
          contar("solido"), contar("ion"), extra), colors.lightGray },
      { ("Calibracao: gimbal %s  bocal %s"):format(
          cfg.gimbalOk and "OK" or "PENDENTE", cfg.bocalOk and "OK" or "PENDENTE"),
        (cfg.gimbalOk and cfg.bocalOk) and colors.lime or colors.orange },
      { ("Preset: %s   Disquete: %s"):format(cfg.nome, noDisco and "SIM" or "NAO"),
        colors.lightGray },
    }
    local i = menu("MISSIL v" .. VERSAO, {
      "Lancar / estabilizar",
      "Calibrar gimbal",
      "Calibrar bocal",
      "Ajustes de voo",
      "Presets (disquete)",
      "Modo remoto / estacao",
      "Testar componentes",
      "Sair",
    }, info)

    local acoes = { voo, calibrarGimbal, calibrarBocal, ajustes, presets, modoRemoto, testes }
    if not i or i == 8 then return end

    local ok, err = pcall(acoes[i])
    detectar()
    desligarTudo()
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
  if argumentos[1] == "lancar" then voo()
  elseif argumentos[1] == "remoto" then modoRemoto()
  else principal() end
end)
pcall(detectar)
pcall(desligarTudo)
fundo(colors.black)
cor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok and err ~= "Terminated" then
  printError(err)
else
  print("BlockForge Militar - ate a proxima!")
end
