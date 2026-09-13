-- Veiculo teleguiado - controlador v3
-- Reescrita modular baseada no codigo BlockForge fornecido pelo usuario.
-- Seguro por padrao: empuxo desativado e sem rotina de carga/detonacao.

local args = { ... }
local VERSION = "3.0.0"
local CONFIG_PATH = "/vehicle_controller.cfg"
local LOOP_DT = 0.05
local DIAG_DT = 0.5
local MAX_MESSAGE = 80

local W, H = term.getSize()
local hasColor = term.isColor()

local DEFAULTS = {
  profile = "default",
  thrust_enabled = false,
  vector_power = 0.20,
  main_power = 0.20,
  kp = 0.04,
  kd = 0.015,
  abort_angle = 45,
  test_seconds = 5,
  telemetry_seconds = 0.5,
  axis_n = 1,
  sign_n = 1,
  axis_l = 2,
  sign_l = 1,
  axis_x = 2,
  sign_x = 1,
  axis_y = 1,
  sign_y = 1,
  invert = false,
  calibrated = false,
}

local COLORS = {
  bg = colors.black,
  panel = colors.gray,
  text = colors.white,
  muted = colors.lightGray,
  title = colors.yellow,
  ok = colors.lime,
  warn = colors.orange,
  danger = colors.red,
  info = colors.cyan,
  accent = colors.lightBlue,
}

local cfg = {}
local P = { gimbal = nil, vectors = {}, motors = {}, drive = nil, modem = nil }
local runtime = {
  page = "home",
  message = "Pronto. Empuxo desativado por padrao.",
  last_angle_n = 0,
  last_angle_l = 0,
  last_rate_n = 0,
  last_rate_l = 0,
  loop_hz = 0,
  max_angle = 0,
  started = 0,
  reason = "",
}

local function copyTable(source)
  local result = {}
  for k, v in pairs(source) do result[k] = v end
  return result
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function setText(color)
  if hasColor then term.setTextColor(color) end
end

local function setBackground(color)
  if hasColor then term.setBackgroundColor(color) end
end

local function clear()
  setBackground(COLORS.bg)
  setText(COLORS.text)
  term.clear()
  term.setCursorPos(1, 1)
end

local function line(y, text, color, background)
  if y < 1 or y > H then return end
  text = tostring(text or "")
  if #text > W - 2 then text = text:sub(1, W - 2) end
  setBackground(background or COLORS.bg)
  setText(color or COLORS.text)
  term.setCursorPos(2, y)
  term.clearLine()
  term.write(text)
  setBackground(COLORS.bg)
  setText(COLORS.text)
end

local function header(title)
  clear()
  setBackground(COLORS.panel)
  setText(COLORS.title)
  term.setCursorPos(1, 1)
  term.clearLine()
  term.write(" VEHICLE CONTROL v" .. VERSION)
  setText(COLORS.text)
  term.setCursorPos(math.max(22, W - #title), 1)
  term.write(title)
  setBackground(COLORS.bg)
end

local function footer(text)
  setBackground(COLORS.panel)
  setText(COLORS.text)
  term.setCursorPos(1, H)
  term.clearLine()
  term.write(" " .. tostring(text or ""))
  setBackground(COLORS.bg)
end

local function waitKey()
  while true do
    local event = { os.pullEvent() }
    if event[1] == "key" or event[1] == "char" then return end
  end
end

local function notice(title, messages, color)
  header(title)
  local y = 3
  for _, message in ipairs(messages) do
    local text = tostring(message)
    while #text > W - 3 do
      line(y, text:sub(1, W - 3), color or COLORS.text)
      text = text:sub(W - 2)
      y = y + 1
    end
    line(y, text, color or COLORS.text)
    y = y + 1
    if y >= H - 1 then break end
  end
  footer("Pressione uma tecla para continuar")
  waitKey()
end

local function confirm(title, question)
  header(title)
  line(3, question, COLORS.warn)
  line(5, "S confirma    N cancela", COLORS.muted)
  while true do
    local event, value = os.pullEvent()
    if event == "char" then
      value = value:lower()
      if value == "s" then return true end
      if value == "n" then return false end
    end
  end
end

local function loadConfig()
  cfg = copyTable(DEFAULTS)
  if not fs.exists(CONFIG_PATH) then return end
  local file = fs.open(CONFIG_PATH, "r")
  local data = file and textutils.unserialize(file.readAll()) or nil
  if file then file.close() end
  if type(data) ~= "table" then return end
  for key, value in pairs(data) do
    if DEFAULTS[key] ~= nil and type(DEFAULTS[key]) == type(value) then
      cfg[key] = value
    end
  end
end

local function saveConfig()
  local file = fs.open(CONFIG_PATH, "w")
  if file then
    file.write(textutils.serialize(cfg))
    file.close()
  end
end

local function safeHasType(name, peripheralType)
  local ok, result = pcall(peripheral.hasType, name, peripheralType)
  return ok and result == true
end

local function safeWrap(name)
  local ok, result = pcall(peripheral.wrap, name)
  return ok and result or nil
end

local function hasAnyType(name, types)
  for _, peripheralType in ipairs(types) do
    if safeHasType(name, peripheralType) then return true end
  end
  return false
end

local function detect()
  P = { gimbal = nil, vectors = {}, motors = {}, drive = nil, modem = nil }
  for _, name in ipairs(peripheral.getNames()) do
    local wrapped = safeWrap(name)
    if wrapped then
      if safeHasType(name, "gimbal_sensor") then
        P.gimbal = P.gimbal or { name = name, p = wrapped }
      elseif safeHasType(name, "modem") then
        if not P.modem or (wrapped.isWireless and wrapped.isWireless()) then
          P.modem = { name = name, p = wrapped }
        end
      elseif safeHasType(name, "drive") then
        P.drive = P.drive or { name = name, p = wrapped }
      elseif hasAnyType(name, {"vector_thruster", "liquid_vector_thruster", "creative_vector_thruster"}) then
        table.insert(P.vectors, { name = name, p = wrapped })
      elseif hasAnyType(name, {"solid_fuel_thruster", "thruster", "ion_thruster", "creative_thruster"}) then
        local class, label = "unknown", "MOT"
        if safeHasType(name, "solid_fuel_thruster") then class, label = "solid", "SOL" end
        if safeHasType(name, "ion_thruster") then class, label = "ion", "ION" end
        if safeHasType(name, "creative_thruster") then class, label = "creative", "CRI" end
        if class == "unknown" then class, label = "liquid", "LIQ" end
        table.insert(P.motors, { name = name, p = wrapped, class = class, label = label })
      end
    end
  end
end

local function methodsOf(device)
  if not device then return {} end
  local result = peripheral.getMethods(device.name)
  return result or {}
end

local function hasMethod(device, method)
  if not device or type(device.p[method]) ~= "function" then return false end
  for _, candidate in ipairs(methodsOf(device)) do
    if candidate == method then return true end
  end
  return false
end

local function call(device, method, ...)
  if not hasMethod(device, method) then return false, nil end
  local ok, result = pcall(device.p[method], ...)
  return ok, result
end

local function setPower(device, power)
  power = clamp(power, 0, 1)
  if hasMethod(device, "setPowerNormalized") then return call(device, "setPowerNormalized", power) end
  if hasMethod(device, "setThrustNormalized") then return call(device, "setThrustNormalized", power) end
  if hasMethod(device, "setThrottle") then return call(device, "setThrottle", power * 15) end
  if hasMethod(device, "setThrust") then return call(device, "setThrust", power * 15) end
  return false, "sem metodo de potencia"
end

local function setVector(device, x, y)
  if hasMethod(device, "setVector") then return call(device, "setVector", clamp(x, -1, 1), clamp(y, -1, 1)) end
  return false, "sem metodo de vetor"
end

local function allOff()
  for _, motor in ipairs(P.motors) do setPower(motor, 0) end
  for _, vector in ipairs(P.vectors) do
    setVector(vector, 0, 0)
    setPower(vector, 0)
  end
end

local function rawAngles()
  if not P.gimbal then return nil, nil end
  local ok, a, b = call(P.gimbal, "getAngles")
  if not ok then return nil, nil end
  if type(a) == "table" then return a[1] or 0, a[2] or 0 end
  return tonumber(a) or 0, tonumber(b) or 0
end

local function angles()
  local a, b = rawAngles()
  if a == nil then return nil, nil end
  local values = { a, b }
  local n = (values[cfg.axis_n] or 0) * cfg.sign_n
  local l = (values[cfg.axis_l] or 0) * cfg.sign_l
  return n, l
end

local function updateRates(n, l, previousN, previousL, previousT)
  local now = os.clock()
  local dt = math.max(now - previousT, 0.001)
  return (n - previousN) / dt, (l - previousL) / dt, now
end

local function statusLine()
  local gimbal = P.gimbal and "GIM OK" or "GIM --"
  local vector = #P.vectors > 0 and ("VET " .. #P.vectors) or "VET --"
  local motors = "MOT " .. #P.motors
  local thrust = cfg.thrust_enabled and "EMPUXO ON" or "EMPUXO OFF"
  return gimbal .. "  " .. vector .. "  " .. motors .. "  " .. thrust
end

local function diagnostic()
  detect()
  header("DIAGNOSTICO")
  line(3, statusLine(), COLORS.info)
  line(5, "Peripherals detectados:", COLORS.title)
  local y = 6
  for _, name in ipairs(peripheral.getNames()) do
    local types = peripheral.getType(name)
    local typeText = type(types) == "table" and table.concat(types, ",") or tostring(types)
    line(y, name .. "  [" .. typeText .. "]", COLORS.text)
    y = y + 1
    if y >= H - 3 then break end
  end
  if y < H - 2 then
    line(y + 1, "Gimbal: " .. (P.gimbal and P.gimbal.name or "nao encontrado"), P.gimbal and COLORS.ok or COLORS.danger)
    line(y + 2, "Modem: " .. (P.modem and P.modem.name or "nao encontrado"), P.modem and COLORS.ok or COLORS.warn)
  end
  footer("ENTER atualiza    BACKSPACE volta")
  while true do
    local event, key = os.pullEvent()
    if event == "key" and key == keys.enter then detect(); diagnostic(); return end
    if event == "key" and key == keys.backspace then return end
  end
end

local function methodsPage()
  detect()
  header("METODOS")
  local y = 3
  for _, name in ipairs(peripheral.getNames()) do
    local methods = peripheral.getMethods(name) or {}
    line(y, name .. ": " .. table.concat(methods, ", "), COLORS.text)
    y = y + 1
    if y >= H - 2 then break end
  end
  footer("BACKSPACE volta")
  waitKey()
end

local function calibrate()
  detect()
  if not P.gimbal then
    notice("CALIBRACAO", {"Gimbal nao encontrado.", "Use Diagnostico para ver os tipos reais."}, COLORS.danger)
    return
  end
  header("CALIBRACAO")
  line(3, "Mantenha o veiculo montado, reto e parado.", COLORS.warn)
  line(4, "ENTER mede o zero atual; BACKSPACE cancela.", COLORS.muted)
  footer("ENTER confirma")
  while true do
    local event, key = os.pullEvent()
    if event == "key" and key == keys.backspace then return end
    if event == "key" and key == keys.enter then break end
  end
  local totalA, totalB, count = 0, 0, 0
  for _ = 1, 20 do
    local a, b = rawAngles()
    if a == nil then
      notice("CALIBRACAO", {"Falha ao ler getAngles."}, COLORS.danger)
      return
    end
    totalA, totalB, count = totalA + a, totalB + b, count + 1
    sleep(0.05)
  end
  cfg.axis_n, cfg.axis_l = 1, 2
  cfg.sign_n, cfg.sign_l = 1, 1
  cfg.calibrated = count > 0
  runtime.last_angle_n = totalA / math.max(count, 1)
  runtime.last_angle_l = totalB / math.max(count, 1)
  saveConfig()
  notice("CALIBRACAO", {"Zero salvo.", "Eixos padrao: X=Norte, Z=Leste.", "Se a resposta ficar invertida, ajuste em Configuracao."}, COLORS.ok)
end

local function setAllVectors(x, y, power)
  for _, vector in ipairs(P.vectors) do
    setVector(vector, x, y)
    setPower(vector, power)
  end
end

local function actuatorTest()
  detect()
  if #P.vectors == 0 and #P.motors == 0 then
    notice("TESTE", {"Nenhum atuador reconhecido."}, COLORS.warn)
    return
  end
  if not cfg.thrust_enabled then
    notice("TESTE", {"Empuxo esta DESATIVADO na configuracao.", "Ative somente depois de conferir os peripherals."}, COLORS.warn)
    return
  end
  if not confirm("TESTE", "Executar pulsos curtos de atuadores?") then return end
  allOff()
  for _, vector in ipairs(P.vectors) do
    setVector(vector, 0.15, 0)
    setPower(vector, math.min(cfg.vector_power, 0.10))
  end
  sleep(0.4)
  allOff()
  notice("TESTE", {"Pulso concluido e todos os atuadores foram zerados."}, COLORS.ok)
end

local function settings()
  while true do
    header("CONFIGURACAO")
    line(3, "1 Empuxo: " .. (cfg.thrust_enabled and "ATIVADO" or "DESATIVADO"), cfg.thrust_enabled and COLORS.danger or COLORS.ok)
    line(4, "2 Potencia vetor: " .. string.format("%.2f", cfg.vector_power), COLORS.text)
    line(5, "3 Potencia principal: " .. string.format("%.2f", cfg.main_power), COLORS.text)
    line(6, "4 KP/KD: " .. string.format("%.3f / %.3f", cfg.kp, cfg.kd), COLORS.text)
    line(7, "5 Limite de inclinacao: " .. string.format("%.1f", cfg.abort_angle), COLORS.text)
    line(8, "6 Duracao do teste: " .. string.format("%.1f s", cfg.test_seconds), COLORS.text)
    line(9, "7 Inverter correcao: " .. (cfg.invert and "SIM" or "NAO"), COLORS.text)
    footer("SETAS escolhem  ENTER edita  BACKSPACE volta")
    local event, key = os.pullEvent()
    if event == "key" and key == keys.backspace then return end
    if event == "char" then
      if key == "1" then
        if cfg.thrust_enabled then
          cfg.thrust_enabled = false
        elseif confirm("SEGURANCA", "Ativar empuxo real para testes?") then
          cfg.thrust_enabled = true
        end
        saveConfig()
      elseif key == "2" then cfg.vector_power = clamp(tonumber(read()) or cfg.vector_power, 0, 1); saveConfig()
      elseif key == "3" then cfg.main_power = clamp(tonumber(read()) or cfg.main_power, 0, 1); saveConfig()
      elseif key == "4" then cfg.kp = clamp(tonumber(read()) or cfg.kp, 0, 1); cfg.kd = clamp(tonumber(read()) or cfg.kd, 0, 1); saveConfig()
      elseif key == "5" then cfg.abort_angle = clamp(tonumber(read()) or cfg.abort_angle, 5, 90); saveConfig()
      elseif key == "6" then cfg.test_seconds = clamp(tonumber(read()) or cfg.test_seconds, 1, 30); saveConfig()
      elseif key == "7" then cfg.invert = not cfg.invert; saveConfig() end
    end
  end
end

local function runTestFlight()
  detect()
  if not P.gimbal then
    notice("TESTE DE VOO", {"Gimbal nao encontrado.", "O teste nao foi iniciado."}, COLORS.danger)
    return
  end
  if not cfg.thrust_enabled then
    notice("TESTE DE VOO", {"Modo simulacao: empuxo real esta desativado.", "A rotina vai apenas ler o sensor e calcular comandos."}, COLORS.info)
  elseif not confirm("TESTE DE VOO", "Iniciar teste com empuxo real?") then
    return
  end
  allOff()
  local start = os.clock()
  local previousN, previousL = angles()
  previousN, previousL = previousN or 0, previousL or 0
  local previousT = os.clock()
  local cycles = 0
  runtime.max_angle = 0
  runtime.reason = "Tempo concluido"
  while os.clock() - start < cfg.test_seconds do
    local n, l = angles()
    if not n then runtime.reason = "Sensor sem leitura"; break end
    local rateN, rateL, now = updateRates(n, l, previousN, previousL, previousT)
    previousN, previousL, previousT = n, l, now
    local angle = math.max(math.abs(n), math.abs(l))
    runtime.max_angle = math.max(runtime.max_angle, angle)
    if angle > cfg.abort_angle then runtime.reason = "Abortado por inclinacao"; break end
    local tx = ({n, l})[cfg.axis_x] * cfg.sign_x
    local ty = ({n, l})[cfg.axis_y] * cfg.sign_y
    local gx = ({rateN, rateL})[cfg.axis_x] * cfg.sign_x
    local gy = ({rateN, rateL})[cfg.axis_y] * cfg.sign_y
    local inv = cfg.invert and -1 or 1
    local cx = clamp(-inv * (cfg.kp * tx + cfg.kd * gx), -1, 1)
    local cy = clamp(-inv * (cfg.kp * ty + cfg.kd * gy), -1, 1)
    if cfg.thrust_enabled then setAllVectors(cx, cy, cfg.vector_power) end
    runtime.last_angle_n, runtime.last_angle_l = n, l
    runtime.last_rate_n, runtime.last_rate_l = rateN, rateL
    cycles = cycles + 1
    runtime.loop_hz = cycles / math.max(os.clock() - start, 0.001)
    header("TESTE DE VOO")
    line(3, "Modo: " .. (cfg.thrust_enabled and "EMPuxo REAL" or "SIMULACAO"), cfg.thrust_enabled and COLORS.warn or COLORS.info)
    line(5, string.format("Norte %7.2f   Leste %7.2f", n, l), COLORS.text)
    line(6, string.format("Taxa  %7.2f   %7.2f", rateN, rateL), COLORS.text)
    line(7, string.format("Comando X %6.2f  Y %6.2f", cx, cy), COLORS.accent)
    line(8, string.format("Maximo %7.2f / limite %.2f", runtime.max_angle, cfg.abort_angle), COLORS.text)
    line(10, "X ou BACKSPACE aborta imediatamente", COLORS.warn)
    footer(string.format("T+%.1fs  %.1f Hz", os.clock() - start, runtime.loop_hz))
    local timer = os.startTimer(LOOP_DT)
    while true do
      local event, value = os.pullEvent()
      if event == "timer" and value == timer then break end
      if event == "key" and (value == keys.x or value == keys.backspace) then runtime.reason = "Abortado pelo operador"; start = -math.huge; break end
    end
    if runtime.reason == "Abortado pelo operador" then break end
  end
  allOff()
  notice("TESTE ENCERRADO", {runtime.reason, string.format("Angulo maximo: %.2f", runtime.max_angle), "Todos os atuadores foram zerados."}, COLORS.ok)
end

local function home()
  while true do
    detect()
    header("INICIO")
    line(3, statusLine(), COLORS.info)
    line(5, "1 Diagnostico de peripherals", COLORS.text)
    line(6, "2 Listar metodos das APIs", COLORS.text)
    line(7, "3 Calibrar sensor", COLORS.text)
    line(8, "4 Testar atuadores", COLORS.text)
    line(9, "5 Teste de voo / simulacao", COLORS.text)
    line(10, "6 Configuracao", COLORS.text)
    line(11, "7 Sair", COLORS.text)
    line(13, "Mensagem: " .. runtime.message, COLORS.muted)
    footer("Digite uma opcao; empuxo permanece OFF por padrao")
    local event, value = os.pullEvent()
    if event == "char" then
      if value == "1" then diagnostic()
      elseif value == "2" then methodsPage()
      elseif value == "3" then calibrate()
      elseif value == "4" then actuatorTest()
      elseif value == "5" then runTestFlight()
      elseif value == "6" then settings()
      elseif value == "7" then return end
    end
  end
end

local function main()
  loadConfig()
  detect()
  if args[1] == "diagnostico" then diagnostic()
  elseif args[1] == "teste" then runTestFlight()
  else home() end
  allOff()
  clear()
  print("Controlador encerrado. Atuadores zerados.")
end

local ok, err = pcall(main)
allOff()
if not ok and err ~= "Terminated" then
  clear()
  print("Erro: " .. tostring(err))
end
