-- base.lua : BlockForge Militar - Base de Lancamento
-- Controla os misseis que estao em "modo remoto" pela rede (rednet)
-- Precisa de: computador (de preferencia avancado) + Ender Modem
-- Telemetria completa (previsao de impacto) com missil v4.5 ou mais

local VERSAO = "2.0"
local MISSIL_MIN = "4.5"
local PROTOCOLO = "bfm"
local SERVICO = "bfm_missil"
local ARQ_ALVOS = "bfm_alvos.txt"
local ARQ_ESTADO = "/bfm_base.txt"
local ARQ_VOOS = "/bfm_voos.txt"

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

-- versao "a.b" do missil >= MISSIL_MIN
local function versaoOk(v)
  local function num(s)
    local a, b = tostring(s):match("(%d+)%.(%d+)")
    return a and tonumber(a) * 1000 + tonumber(b) or 0
  end
  return num(v) >= num(MISSIL_MIN)
end

-- guarda os ultimos 20 voos acompanhados
local function registrarVoo(T, motivo)
  local lista = lerTabela(ARQ_VOOS) or {}
  table.insert(lista, 1, { quando = os.date("%d/%m %H:%M"), missil = sel.nome or ("#" .. sel.id),
    alvo = T and T.alvo, motivo = motivo, t = T and T.t, dist = T and T.dist })
  while #lista > 20 do table.remove(lista) end
  gravarTabela(ARQ_VOOS, lista)
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
    table.insert(ops, ("%-18s v%-4s %s"):format(a.st.nome or ("#" .. a.id), tostring(a.st.versao),
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
    "Versao: v" .. tostring(a.st.versao)
      .. (versaoOk(a.st.versao) and "" or ("  (antiga: atualize para v" .. MISSIL_MIN .. ")")),
    "Preset: " .. tostring(a.st.preset),
    ("Motores: vetor %d, liquidos %d, solidos %d"):format(a.st.vet or 0, a.st.liq or 0, a.st.sol or 0),
    "Codigo de lancamento: " .. (a.st.precisaCodigo and "exigido" or "nenhum"),
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
          if msg.fim and not fim then
            fim = msg.texto
            registrarVoo(T, fim)
          end
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
        local function linha(y, rotulo, txt, c)
          escrever(2, y, rotulo, cinza)
          escrever(14, y, txt, c)
        end
        if T.pos then linha(5, "Posicao", ("%.0f %.0f %.0f"):format(T.pos.x, T.pos.y, T.pos.z)) end
        if T.alvo then linha(6, "Alvo", coords(T.alvo)) end
        if T.dist then
          linha(7, "Distancia", ("%.0f blocos  (horizontal %.0f)"):format(T.dist, T.distH or 0), colors.yellow)
        end
        local vel = T.vel or { n = 0, l = 0, y = 0 }
        local vh = math.sqrt(vel.n * vel.n + vel.l * vel.l)
        linha(8, "Velocidade", ("%.1f b/s   vertical %.1f"):format(math.sqrt(vh * vh + vel.y * vel.y), vel.y))
        if T.queda then
          -- missil v4.5+: previsao do ponto de queda pela guiagem balistica
          linha(9, "Impacto", ("em %.0f s   erro previsto %.1f blocos"):format(T.tgo or 0, T.queda),
            T.queda <= 4 and colors.lime or colors.orange)
        elseif T.distH and vh > 1 then
          linha(9, "Chegada", ("~%.0f s"):format(T.distH / vh))
        end
        if T.modo then
          linha(10, "Apontamento", ("erro %.1f graus   (%s)"):format(T.erro or 0, T.modo))
        else
          linha(10, "Inclinacao", ("N %.1f  L %.1f   rumo %.0f"):format(T.n or 0, T.l or 0, T.psi or 0))
        end
        linha(11, "Motores", ("%.0f Hz   acelerador %d%%%s"):format(T.hz or 0,
          math.floor((T.acel or 0) * 100 + 0.5),
          T.sol and ("   solidos %d%%"):format(math.floor(T.sol * 100 + 0.5)) or ""),
          (T.hz or 0) >= 5 and colors.lime or colors.red)
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
    escrever(14, 6, ("%d blocos  (altura %+d)"):format(math.floor(math.sqrt(dx * dx + dz * dz)),
      math.floor(alvo.y - st.pos.y)))
  end
  if not versaoOk(st.versao) then
    escrever(2, 7, ("Missil v%s: atualize para v%s ou mais"):format(tostring(st.versao), MISSIL_MIN),
      colors.orange)
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

local function historico()
  local lista = lerTabela(ARQ_VOOS) or {}
  if #lista == 0 then
    aviso("HISTORICO DE VOOS", { "Nenhum voo registrado.",
      "Os voos entram aqui quando acompanhados pela base." }, colors.orange)
    return
  end
  local linhas = {}
  for _, v in ipairs(lista) do
    table.insert(linhas, ("%s %s: %s"):format(v.quando, v.missil, v.motivo))
    table.insert(linhas, ("   alvo %s   T+%.0fs   dist final %s"):format(v.alvo and coords(v.alvo) or "?",
      v.t or 0, v.dist and ("%.0f"):format(v.dist) or "?"))
  end
  aviso("HISTORICO DE VOOS", linhas)
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
      "Historico de voos",
      "Sair",
    }, info)
    if not i or i == 7 then return end

    if not modem then
      aviso("ERRO", { "Coloque um modem sem fio (Ender Modem) na base." }, colors.red)
    else
      local acoes = { procurar, definirAlvo, alvosSalvos, lancar, acompanhar, historico }
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
