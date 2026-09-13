# BlockForge Militar — Controlador standalone

Controlador Lua para Minecraft 1.21.1 com CC:Tweaked, Create Aeronautics e Create Propulsion: Simulated. O projeto usa como implementação principal o código BlockForge Militar fornecido pelo usuário, versão 2.0.

## Instalação no computador do veículo

No terminal do computador CC:Tweaked, execute:

```text
wget run https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/installer.lua missil
```

O instalador baixa `missil.lua` e `startup.lua`. Depois, execute:

```text
reboot
```

Para iniciar manualmente sem reiniciar:

```text
missil
```

O controlador também aceita o modo direto de lançamento previsto no código:

```text
missil lancar
```

## Instalação da estação

A estação continua sendo instalada pelo fluxo existente:

```text
wget run https://raw.githubusercontent.com/marcelin1555/MISSEL-FALAE/main/scripts/installer.lua estacao
```

## Arquivos principais

```text
scripts/
├── installer.lua
├── missile/
│   ├── missil.lua       # implementação principal BlockForge v2.0
│   ├── startup.lua      # inicializador
│   ├── teste.lua        # bateria de testes existente
│   ├── calibrar.lua
│   └── calibrar_gimbal.lua
└── estacao/
    ├── startup.lua
    └── estacao.lua
```

A implementação anterior da interface v3 foi removida do conjunto ativo conforme solicitado. O controlador utilizado agora é somente o código anexado que já está funcionando.

## Recursos do controlador

O código principal contém menu de terminal, diagnóstico de componentes, calibração do gimbal, calibração do bocal, ajustes de voo, presets, painel de status, controle manual do bocal e rotina de voo com controle PD. Ele detecta gimbal, vector thrusters, motores sólidos, motores líquidos, motores iônicos, motores criativos e drive de disquete pelos tipos de peripheral esperados pelo código.

Antes de executar testes com empuxo, monte o veículo em uma área controlada e confirme os peripherals encontrados pelo painel de status. A bateria `teste` deve ser usada para diagnóstico inicial dos motores e vetores.

## Mods esperados

| Modificação | Função |
|---|---|
| CC:Tweaked | Computador, Lua e peripherals |
| Create | Contraptions e componentes mecânicos |
| Create Aeronautics | Física e componentes aéreos |
| Create Propulsion: Simulated | Propulsão e vetorização conforme a instalação |
| Sable | Física dos subníveis |
| Create Simulated Additions | Physics Assembler e integração do projeto |

## Fonte do código

A implementação principal é o conteúdo fornecido no arquivo anexado pelo usuário e está versionada em `scripts/missile/missil.lua`.
