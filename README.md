# 🚀 Míssil Teleguiado - CC:Tweaked + Create Propulsion + Aeronautics

Sistema de míssil teleguiado para **Minecraft 1.21.1** com NeoForge, usando computadores CC:Tweaked para controle de voo e comunicação wireless.

## 📋 Mods Necessários

- **CC:Tweaked** - Computadores e programação Lua
- **Create** - Base mecânica
- **Create Propulsion** - Thrusters vetoriais e tilt adapters
- **Create Aeronautics** - Propellers e aerodinâmica
- **Sable** - Motor de física para sub-levels
- **Create Simulated Additions** - Physics Assembler

## 📁 Estrutura de Arquivos

```
missil-teleguiado/
├── scripts/
│   ├── config.lua              # Configurações compartilhadas
│   ├── installer.lua           # Instalador automático
│   ├── missile/
│   │   ├── startup.lua         # Auto-start do míssil
│   │   └── missile.lua         # Lógica de voo e controle
│   └── estacao/
│       ├── startup.lua         # Auto-start da estação
│       └── estacao.lua         # Interface HUD e controles
└── guia-montagem/
    └── README.md               # Guia passo-a-passo
```

## 🎮 Como Usar

### Instalação Rápida

1. **Copie os arquivos** para a pasta do mundo:
   ```
   saves/<seu-mundo>/computercraft/computer/<ID>/
   ```

2. **Para o computador do MÍSSIL**, copie:
   - `config.lua`
   - `missile/startup.lua` → renomeie para `startup.lua`
   - `missile/missile.lua`

3. **Para o computador da ESTAÇÃO**, copie:
   - `config.lua`
   - `estacao/startup.lua` → renomeie para `startup.lua`
   - `estacao/estacao.lua`

### Controles da Estação

| Tecla | Ação |
|-------|------|
| **W** | Pitch para cima |
| **S** | Pitch para baixo |
| **A** | Yaw para esquerda |
| **D** | Yaw para direita |
| **Espaço** | Aumentar throttle |
| **Shift** | Diminuir throttle |
| **Enter** | Lançar míssil |
| **F** | Armar ogiva |
| **X** | Detonar |
| **M** | Alternar modo (Manual/GPS) |
| **Backspace** | Autodestruição (emergência) |
| **Q** | Sair |

### Modos de Guiamento

- **Manual (WASD)** — Você pilota o míssil em tempo real
- **GPS** — Informe coordenadas X, Y, Z e o míssil navega automaticamente

## ⚙️ Configuração

Edite o arquivo `config.lua` para ajustar:

- Canais de comunicação wireless
- Ângulos máximos dos tilt adapters
- Lados de redstone para thrusters
- Teclas de controle
- Cores da interface

## ⚠️ Notas Importantes

- Os computadores precisam de **Wireless Modems** (preferencialmente Ender Modems para alcance infinito)
- O computador do míssil precisa estar **adjacente** aos tilt adapters ou conectado via **Wired Modem + Cabos**
- O míssil precisa ser montado como sub-level via **Physics Assembler** do Create Simulated
- O sistema GPS do CC:Tweaked requer pelo menos **4 computadores GPS** no mundo para funcionar

## 📖 Guia de Montagem

Consulte o [Guia de Montagem](guia-montagem/README.md) para instruções detalhadas de como construir o míssil e a estação de controle no jogo.
