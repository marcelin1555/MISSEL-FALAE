-- ============================================
-- MISSIL TELEGUIADO - BATERIA DE TESTES
-- Arquitetura: Motores Sólidos (Propulsão) + 1 Vector Thruster (Direção)
-- ============================================

local config = require("config")

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("  🚀 TESTE DO MÍSSIL (Main + Vetor)")
print("========================================")
print()

local function log(msg)
    print(string.format("[%.1f] %s", os.clock(), msg))
end

-- 1. VERIFICAÇÃO DE PERIFÉRICOS
print("--- [1/3] TESTE DE PERIFÉRICOS ---")
local modems = { peripheral.find("modem") }
if #modems > 0 then
    print("  [OK] Modem Wireless encontrado")
else
    print("  [AVISO] Nenhum modem wireless encontrado!")
end

local gimbal = peripheral.find("gimbal_sensor")
if gimbal then
    print("  [OK] Gimbal/Giroscópio encontrado")
else
    print("  [AVISO] Gimbal físico não detectado")
end

local vetor = peripheral.find("vector_thruster") or peripheral.find("liquid_vector_thruster") or peripheral.find("creative_vector_thruster")
if vetor then
    print("  [OK] Vector Thruster encontrado")
else
    print("  [AVISO] Nenhum Vector Thruster encontrado!")
end

local solidos = {}
for _, nome in ipairs(peripheral.getNames()) do
    local tipo = peripheral.getType(nome) or ""
    if string.find(tipo, "thruster") and not string.find(tipo, "vector") then
        table.insert(solidos, { nome = nome, p = peripheral.wrap(nome) })
    end
end
print("  [INFO] Motores principais encontrados: " .. #solidos)
if config.THRUSTER_SIDE then
    print("  [INFO] Redstone (Main) ativo na face: " .. config.THRUSTER_SIDE)
end

print()
sleep(1.5)

-- 2. TESTE DOS MOTORES PRINCIPAIS
print("--- [2/3] TESTE DE EMPUXO (MAIN) ---")

local function setMotoresSolidos(pot)
    for _, m in ipairs(solidos) do
        pcall(function() 
            if m.p.setPowerNormalized then m.p.setPowerNormalized(pot) 
            elseif m.p.setThrustNormalized then m.p.setThrustNormalized(pot)
            elseif m.p.setThrust then m.p.setThrust(pot * 15)
            elseif m.p.setThrottle then m.p.setThrottle(pot * 15)
            end
        end)
    end
    if config.THRUSTER_SIDE then
        pcall(redstone.setAnalogOutput, config.THRUSTER_SIDE, math.floor(pot * 15))
    end
end

if #solidos > 0 or config.THRUSTER_SIDE then
    log("Acelerando Motores Principais...")
    for p = 0, 1.0, 0.2 do
        setMotoresSolidos(p)
        sleep(0.2)
    end
    sleep(0.5)
    setMotoresSolidos(0)
    print("  -> Teste de Motores Principais [OK]")
else
    print("  -> Pulando (Nenhum motor principal detectado)")
end
print()
sleep(1.5)


-- 3. TESTE DO VETOR
print("--- [3/3] TESTE DE VETORIZAÇÃO ---")

if vetor then
    log("Vetorização X Positivo...")
    vetor.setVector(0.5, 0)
    vetor.setThrustNormalized(0.1)
    sleep(1.0)

    log("Vetorização X Negativo...")
    vetor.setVector(-0.5, 0)
    sleep(1.0)

    log("Vetorização Y Positivo...")
    vetor.setVector(0, 0.5)
    sleep(1.0)

    log("Vetorização Y Negativo...")
    vetor.setVector(0, -0.5)
    sleep(1.0)

    vetor.setVector(0, 0)
    vetor.setThrustNormalized(0)
    print("  -> Teste de Vetorização [OK]")
else
    print("  -> Pulando (Nenhum Vector Thruster detectado)")
end

print()
print("========================================")
print("  ✅ BATERIA DE TESTES CONCLUÍDA!")
print("========================================")
