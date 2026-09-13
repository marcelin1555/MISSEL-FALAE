# Controlador v3

O `missile.lua` foi refeito com uma interface de terminal modular para o veículo teleguiado. A versão começa com o empuxo desativado e não contém rotina de carga ou detonação.

## Menu

1. **Diagnóstico de peripherals**: lista os nomes e tipos detectados pelo CC:Tweaked.
2. **Listar métodos**: mostra os métodos expostos por cada peripheral, sem executar comandos de atuação.
3. **Calibrar sensor**: registra a média do `getAngles()` na posição inicial.
4. **Testar atuadores**: executa apenas pulsos curtos depois de confirmação e ativação explícita do empuxo.
5. **Teste de voo / simulação**: calcula comandos PD e monitora ângulos. Com empuxo desligado, funciona somente como simulação.
6. **Configuração**: ajusta potência, ganhos PD, limite de inclinação, duração do teste e inversão.
7. **Sair**: zera os atuadores e encerra.

## Segurança

A configuração inicial usa `thrust_enabled = false`. Qualquer encerramento, erro, abortar pelo operador ou limite de inclinação chama `allOff()`. O controlador deve ser testado sem TNT, shell ou carga ativa. A ativação do empuxo real só deve ocorrer depois de conferir o diagnóstico e os métodos reais dos peripherals.

## Comandos

- `missile.lua`: abre o menu.
- `missile.lua diagnostico`: abre diretamente o diagnóstico.
- `missile.lua teste`: inicia diretamente o teste de voo/simulação.

O arquivo `missile.local-backup.lua` preserva o controlador anterior. O arquivo `missile.blockforge-base.lua` preserva a base completa recebida do Pastebin.
