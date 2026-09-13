# 🚀 Míssil Teleguiado - CC:Tweaked + Create Propulsion + Aeronautics

Sistema de míssil teleguiado para **Minecraft 1.21.1** com NeoForge, usando computadores CC:Tweaked para controle de voo e comunicação wireless.

---

## ⚡ Instalação Rápida no jogo (CC:Tweaked)

Você pode instalar o sistema diretamente no computador dentro do Minecraft executando os comandos abaixo no terminal do CC:Tweaked (é necessário que a API HTTP esteja ativada no mod).

### 🚀 1. No Computador do Míssil

Abra o terminal do computador que ficará no míssil e digite:

```bash
wget run https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/installer.lua missil
```

*(Ou via comandos manuais se preferir:)*
```bash
wget https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/config.lua config.lua
wget https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/missile/startup.lua startup.lua
wget https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/missile/missile.lua missile.lua
reboot
```

---

### 🕹️ 2. No Computador da Estação de Controle

Abra o terminal do computador/monitor que controlará o míssil e digite:

```bash
wget run https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/installer.lua estacao
```

*(Ou via comandos manuais se preferir:)*
```bash
wget https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/config.lua config.lua
wget https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/estacao/startup.lua startup.lua
wget https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/estacao/estacao.lua estacao.lua
reboot
```

---

### 📂 3. Instalação Offline / Manual (Pasta do Save)

Se você não tiver acesso à internet no computador do mod, copie os arquivos baixados deste repositório diretamente para a pasta do mundo:
`saves/<seu-mundo>/computercraft/computer/<ID_DO_COMPUTADOR>/`

- **Computador do Míssil:** `config.lua`, `scripts/missile/startup.lua` (renomeado para `startup.lua`), `scripts/missile/missile.lua`
- **Computador da Estação:** `config.lua`, `scripts/estacao/startup.lua` (renomeado para `startup.lua`), `scripts/estacao/estacao.lua`

---

## 📋 Mods Necessários

- **CC:Tweaked** - Computadores e programação Lua
- **Create** - Base mecânica
- **Create Propulsion** - Thrusters vetoriais e tilt adapters
- **Create Aeronautics** - Propellers e aerodinâmica
- **Sable** - Motor de física para sub-levels
- **Create Simulated Additions** - Physics Assembler

---

## 📁 Estrutura do Repositório

```
missil-teleguiado/
├── scripts/
│   ├── config.lua              # Configurações compartilhadas
│   ├── installer.lua           # Instalador automático via GitHub
│   ├── missile/
│   │   ├── startup.lua         # Auto-start do míssil
│   │   └── missile.lua         # Lógica de voo e controle
│   └── estacao/
│       ├── startup.lua         # Auto-start da estação
│       └── estacao.lua         # Interface HUD e controles
└── guia-montagem/
    └── README.md               # Guia passo-a-passo de construção
```

---

## 🎮 Controles da Estação

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

---

## 🎯 Modos de Guiamento

- **Manual (WASD)** — Pilote o míssil em tempo real através da estação de controle.
- **GPS** — Informe as coordenadas X, Y, Z alvo e o míssil navegará automaticamente.

---

## ⚙️ Configuração (`config.lua`)

Edite o arquivo `config.lua` para ajustar:
- Canais de comunicação wireless (`CANAL_ENVIO` e `CANAL_RECEBER`)
- Ângulos máximos dos tilt adapters (`TILT_MAX_ANGLE`)
- Lados de redstone para thrusters e detonador
- Teclas de controle e cores da interface HUD

---

## 📖 Guia de Montagem

Para instruções detalhadas de como construir a estrutura física do míssil e da estação no Minecraft, acesse o [Guia de Montagem](guia-montagem/README.md).
