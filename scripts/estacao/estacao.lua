-- Estacao BlockForge Remote v1
-- Implementacao nova, sem dependencia da antiga estacao.lua.
-- Protocolo: BFM_REMOTE_1 / canais 4210 comando e 4211 telemetria.

local PROTOCOLO = "BFM_REMOTE_1"
local CANAL_COMANDO = 4210
local CANAL_TELEMETRIA = 4211
local TIMEOUT = 3
local modem
local monitor
local tela
local estado = {
  link = false,
  status = "desconectado",
  ultima = 0,
  norte = 0,
  leste = 0,
  giro = 0,
  bocalX = 0,
  bocalY = 0,
  empuxo = 0,
  hz = 0,
  tempo = 0,
  anguloMaximo = 0,
  mensagem = "Iniciando estação",
}

local function encontrarModem()
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.hasType(nome, "modem") then
      local p = peripheral.wrap(nome)
      if p and p.isWireless and p.isWireless() then return p end
    end
  end
end

local function enviar(acao, dados)
  if not modem then return end
  local pacote = { protocolo = PROTOCOLO, tipo = "comando", dados = dados or { acao = acao } }
  pacote.dados.acao = acao
  modem.transmit(CANAL_COMANDO, CANAL_TELEMETRIA, textutils.serialize(pacote))
end

local function cor(c)
  if tela and tela.isColor and tela.isColor() then tela.setTextColor(c) end
end

local function fundo(c)
  if tela and tela.isColor and tela.isColor() then tela.setBackgroundColor(c) end
end

local function limpar()
  fundo(colors.black)
  cor(colors.white)
  tela.clear()
  tela.setCursorPos(1, 1)
end

local function texto(x, y, valor, color)
  if y < 1 then return end
  valor = tostring(valor or "")
  local w = select(1, tela.getSize())
  if #valor > w - x + 1 then valor = valor:sub(1, math.max(0, w - x + 1)) end
  tela.setCursorPos(x, y)
  cor(color or colors.white)
  tela.write(valor)
end

local function barra(y, valor, maximo, largura)
  local w = select(1, tela.getSize())
  largura = math.min(largura or 20, math.max(1, w - 4))
  local preenchido = math.floor(math.max(0, math.min(1, valor / maximo)) * largura)
  tela.setCursorPos(2, y)
  fundo(colors.gray)
  tela.write(string.rep(" ", largura))
  tela.setCursorPos(2, y)
  fundo(valor > maximo * 0.8 and colors.orange or colors.lime)
  tela.write(string.rep(" ", preenchido))
  fundo(colors.black)
end

local function desenhar()
  if not tela then return end
  local w, h = tela.getSize()
  limpar()
  fundo(colors.gray)
  cor(colors.yellow)
  tela.setCursorPos(1, 1)
  tela.clearLine()
  tela.write(" BLOCKFORGE REMOTE v1")
  cor(colors.white)
  fundo(colors.black)
  texto(2, 3, "LINK: " .. (estado.link and "CONECTADO" or "DESCONECTADO"), estado.link and colors.lime or colors.red)
  texto(2, 4, "STATUS: " .. string.upper(estado.status), estado.status == "voo" and colors.orange or colors.cyan)
  texto(2, 6, string.format("NORTE %8.2f", estado.norte), colors.white)
  texto(2, 7, string.format("LESTE %8.2f", estado.leste), colors.white)
  texto(2, 8, string.format("GIRO  %8.2f", estado.giro), colors.white)
  texto(2, 10, string.format("BOCAL X %7.2f", estado.bocalX), colors.lightBlue)
  texto(2, 11, string.format("BOCAL Y %7.2f", estado.bocalY), colors.lightBlue)
  texto(2, 13, string.format("EMPuxo %.2f kN", estado.empuxo), colors.orange)
  texto(2, 14, string.format("CONTROLE %.1f Hz", estado.hz), colors.white)
  texto(2, 15, string.format("TEMPO %.1f s", estado.tempo), colors.white)
  texto(2, 16, string.format("ANGULO MAX %.1f", estado.anguloMaximo), estado.anguloMaximo > 30 and colors.red or colors.white)
  barra(18, estado.empuxo, math.max(1, estado.empuxo), math.min(30, w - 4))
  texto(2, math.max(20, h - 5), "P ping   L lançar   X abortar", colors.lightGray)
  texto(2, math.max(21, h - 4), "R reconectar   Q sair", colors.lightGray)
  texto(2, math.max(23, h - 2), estado.mensagem, colors.yellow)
end

local function processar(pacote)
  if type(pacote) ~= "table" or pacote.protocolo ~= PROTOCOLO then return end
  estado.link = true
  estado.ultima = os.clock()
  local dados = pacote.dados or {}
  estado.status = dados.status or pacote.tipo or estado.status
  estado.mensagem = "Recebido: " .. tostring(pacote.tipo)
  for _, chave in ipairs({"norte", "leste", "giro", "bocalX", "bocalY", "empuxo", "hz", "tempo", "anguloMaximo"}) do
    if dados[chave] ~= nil then estado[chave] = tonumber(dados[chave]) or estado[chave] end
  end
end

local function receber()
  while true do
    local event, _, canal, _, mensagem = os.pullEvent("modem_message")
    if canal == CANAL_TELEMETRIA then
      local ok, pacote = pcall(textutils.unserialize, mensagem)
      if ok then processar(pacote) end
    end
  end
end

local function teclado()
  while true do
    local event, key = os.pullEvent()
    if event == "key" then
      if key == keys.p then enviar("ping")
      elseif key == keys.l then
        enviar("lancar")
        estado.mensagem = "Comando de lançamento enviado"
      elseif key == keys.x then
        enviar("abortar")
        estado.mensagem = "Comando de abortar enviado"
      elseif key == keys.r then
        estado.link = false
        enviar("ping")
        estado.mensagem = "Reconectando"
      elseif key == keys.q then
        enviar("sair")
        return
      end
    end
  end
end

local function telaLoop()
  while true do
    if os.clock() - estado.ultima > TIMEOUT then estado.link = false end
    desenhar()
    sleep(0.25)
  end
end

local function main()
  modem = encontrarModem()
  if not modem then error("Modem wireless nao encontrado") end
  modem.open(CANAL_TELEMETRIA)
  tela = peripheral.find("monitor") or term.current()
  if tela.setTextScale and peripheral.find("monitor") then tela.setTextScale(0.5) end
  enviar("ping")
  parallel.waitForAny(receber, teclado, telaLoop)
  fundo(colors.black)
  cor(colors.white)
  tela.clear()
  tela.setCursorPos(1, 1)
  tela.write("Estacao encerrada.")
end

local ok, err = pcall(main)
if not ok and err ~= "Terminated" then printError(err) end
