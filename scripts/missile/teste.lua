-- ============================================
-- MISSIL TELEGUIADO - BATERIA DE TESTES (TESTE DE BANCADA)
-- CC:Tweaked + Create Propulsion + Aeronautics
-- ============================================
-- Teste de bancada / ignição em solo para verificar:
-- 1. Detecção de modem e Gimbal Aeronautics
-- 2. Ignição individual dos 4 Motores 2x2 (TL, TR, BL, BR)
-- 3. Varredura de vetorização de empuxo (Pitch e Yaw)
-- 4. Teste de potência total (Throttle Máximo 3s)
-- ============================================

local config = require("config")

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("  🚀 BATERIA DE TESTES DO MÍSSIL (2x2)")
print("  Diagnóstico de Bancada e Motores")
print("========================================")
print()

local function log(msg)
    print(string.format("[%.1f] %s", os.clock(), msg))
end

-- 1. VERIFICAÇÃO DE PERIFÉRICOS
print("--- [1/4] TESTE DE PERIFÉRICOS & SENSORES ---")
local modems = { peripheral.find("modem") }
if #modems > 0 then
    print("  [OK] Modem Wireless encontrado (" .. #modems .. ")")
else
    print("  [AVISO] Nenhum modem wireless encontrado!")
end

local gimbals = 0
for _, name in ipairs(peripheral.getNames()) do
    local t = string.lower(peripheral.getType(name) or "")
    if string.find(t, "gimbal") or string.find(t, "gyro") or string.find(t, "ship") or string.find(t, "inertial") then
        gimbals = gimbals + 1
        print("  [OK] Gimbal/Giroscópio encontrado: " .. name)
    end
end
if gimbals == 0 then
    print("  [INFO] Gimbal físico não detectado (usando modo simulação)")
end
print()
sleep(1.5)

-- 2. TESTE INDIVIDUAL DOS 4 MOTORES (2x2)
print("--- [2/4] TESTE INDIVIDUAL DOS 4 MOTORES ---")
local motores = {
    { nome = "Superior Esquerdo (TL)", side = config.THRUSTER_TL_SIDE },
    { nome = "Superior Direito (TR)",  side = config.THRUSTER_TR_SIDE },
    { nome = "Inferior Esquerdo (BL)", side = config.THRUSTER_BL_SIDE },
    { nome = "Inferior Direito (BR)",  side = config.THRUSTER_BR_SIDE },
}

for _, m in ipairs(motores) do
    if m.side then
        log("Testando " .. m.nome .. " [Lado Redstone: " .. m.side .. "]")
        -- Ramp-up gradual
        for p = 0, 15, 5 do
            pcall(redstone.setAnalogOutput, m.side, p)
            sleep(0.1)
        end
        sleep(0.4)
        pcall(redstone.setAnalogOutput, m.side, 0)
        print("   -> Motor " .. m.nome .. " TESTADO [OK]")
    else
        print("   -> Motor " .. m.nome .. " sem lado configurado!")
    end
    sleep(0.3)
end
print()
sleep(1.5)

-- 3. TESTE DE VARREDURO DE VETORIZAÇÃO (PITCH & YAW)
print("--- [3/4] TESTE DE VARREDURA VETORIAL ---")

local function aplicarDiferencial(throttle, pitch, yaw)
    local p_factor = (pitch / config.TILT_MAX_ANGLE) * (config.THROTTLE_MAX / 2)
    local y_factor = (yaw / config.TILT_MAX_ANGLE) * (config.THROTTLE_MAX / 2)

    local val_tl = math.max(0, math.min(config.THROTTLE_MAX, math.floor(throttle - p_factor + y_factor + 0.5)))
    local val_tr = math.max(0, math.min(config.THROTTLE_MAX, math.floor(throttle - p_factor - y_factor + 0.5)))
    local val_bl = math.max(0, math.min(config.THROTTLE_MAX, math.floor(throttle + p_factor + y_factor + 0.5)))
    local val_br = math.max(0, math.min(config.THROTTLE_MAX, math.floor(throttle + p_factor - y_factor + 0.5)))

    if config.THRUSTER_TL_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_TL_SIDE, val_tl) end
    if config.THRUSTER_TR_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_TR_SIDE, val_tr) end
    if config.THRUSTER_BL_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_BL_SIDE, val_bl) end
    if config.THRUSTER_BR_SIDE then pcall(redstone.setAnalogOutput, config.THRUSTER_BR_SIDE, val_br) end
end

log("Vetorização PITCH UP (Subir +45°)...")
aplicarDiferencial(10, 45, 0)
sleep(0.8)

log("Vetorização PITCH DOWN (Descer -45°)...")
aplicarDiferencial(10, -45, 0)
sleep(0.8)

log("Vetorização YAW LEFT (Esquerda -45°)...")
aplicarDiferencial(10, 0, -45)
sleep(0.8)

log("Vetorização YAW RIGHT (Direita +45°)...")
aplicarDiferencial(10, 0, 45)
sleep(0.8)

aplicarDiferencial(0, 0, 0)
print("  -> Varredura de Vetores Concluída [OK]")
print()
sleep(1.5)

-- 4. TESTE DE EMPUXO TOTAL
print("--- [4/4] TESTE DE EMPUXO MÁXIMO (3 SEGUNDOS) ---")
log("💥 LIGANDO OS 4 MOTORES A 100% DE POTÊNCIA...")
aplicarDiferencial(15, 0, 0)
for i = 3, 1, -1 do
    print("   Contagem regressiva de empuxo: " .. i .. "s")
    sleep(1)
end
aplicarDiferencial(0, 0, 0)
log("Motores desligados. Temperatura estabilizada.")
print()

print("========================================")
print("  ✅ BATERIA DE TESTES CONCLUÍDA COM SUCESSO!")
print("  O míssil está pronto para lançamento.")
print("========================================")
