-- ============================================
-- MISSIL TELEGUIADO - CONFIGURAÇÕES
-- CC:Tweaked + Create Propulsion + Aeronautics
-- ============================================

local config = {}

-- === COMUNICAÇÃO ===
config.CANAL_ENVIO    = 42    -- canal para enviar comandos
config.CANAL_RECEBER  = 43    -- canal para receber telemetria
config.PROTOCOLO      = "MISSIL_TG"
config.INTERVALO_TELEMETRIA = 0.25 -- segundos entre pacotes de telemetria

-- === PERIFÉRICOS & PROPULSÃO ===
config.MODEM_SIDE     = nil  -- nil = auto-detectar

-- Os motores sólidos e o vector thruster são detectados automaticamente
config.DETONACAO_SIDE   = "top"  -- Lado que ativa a detonação (TNT/Ogiva)

-- === ESTABILIZAÇÃO & GIMBAL (Aeronautics / Gyroscope / IMU) ===
config.USAR_GIMBAL      = true  -- Auto-detectar Gimbal do Aeronautics para estabilização PID
config.PID_KP           = 0.04  -- Ganho Proporcional (força da correção, refinado)
config.PID_KI           = 0.00  -- Ganho Integral (elimina erro acumulado, desativado no script base)
config.PID_KD           = 0.015 -- Ganho Derivativo (suaviza oscilações, refinado)
config.INVERTER_BOCAL   = false -- Altere para true se a correção empurrar pro lado errado no voo
config.ESTABILIZAR_ROLL = false -- Roll lock desativado por padrão (difícil com 1 vetor)

-- === CONTROLE DE VOO ===
config.THROTTLE_MIN     = 0    -- nível mínimo de redstone (0-15)
config.THROTTLE_MAX     = 15   -- nível máximo de redstone
config.THROTTLE_INICIAL = 0    -- throttle ao lançar
config.TILT_MAX_ANGLE   = 45   -- ângulo/fator máximo de vetorização (graus ou %)
config.TILT_STEP        = 5    -- incremento de ângulo por comando
config.THROTTLE_STEP    = 1    -- incremento de throttle por comando

-- === MODOS DE GUIAMENTO ===
config.MODO_MANUAL      = "manual"  -- controle WASD
config.MODO_GPS         = "gps"     -- vai até coordenadas automático
config.MODO_PADRAO      = "manual"  -- modo inicial

-- === GPS (para modo automático) ===
config.GPS_PRECISAO     = 3    -- distância em blocos para considerar "chegou no alvo"
config.GPS_CORRECAO_RATE= 0.1  -- taxa de correção de rumo (0-1)

-- === DETONAÇÃO ===
config.ARMAR_DELAY      = 3    -- segundos após lançamento para armar
config.TIPO_DETONACAO   = "redstone" -- "redstone" ou "impacto"

-- === ESTAÇÃO DE CONTROLE ===
config.MONITOR_SCALE    = 0.5  -- escala do texto do monitor
config.COR_FUNDO        = colors.black
config.COR_TEXTO        = colors.white
config.COR_TITULO       = colors.yellow
config.COR_ALERTA       = colors.red
config.COR_OK           = colors.lime
config.COR_INFO         = colors.cyan
config.COR_BARRA        = colors.orange

-- === TECLAS DE CONTROLE (estação) ===
config.TECLA_CIMA       = keys.w      -- pitch para cima
config.TECLA_BAIXO      = keys.s      -- pitch para baixo
config.TECLA_ESQUERDA   = keys.a      -- yaw esquerda
config.TECLA_DIREITA    = keys.d      -- yaw direita
config.TECLA_THROTTLE_UP= keys.space  -- aumentar throttle
config.TECLA_THROTTLE_DOWN= keys.leftShift -- diminuir throttle
config.TECLA_LANCAR     = keys.enter  -- lançar míssil
config.TECLA_ARMAR      = keys.f      -- armar ogiva
config.TECLA_DETONAR    = keys.x      -- detonar
config.TECLA_EMERGENCIA = keys.backspace -- autodestruição
config.TECLA_MODO       = keys.m      -- alternar modo manual/GPS
config.TECLA_SAIR       = keys.q      -- sair do programa

return config
