# Ponto

App de barra de menus pro Mac que não deixa você esquecer de bater o ponto. Na hora de cada marcação ele trava a tela (ou mostra um aviso no canto, você escolhe) e só libera quando você decide: bater agora ou adiar.

## Instalar

1. Baixe o [Ponto.pkg](https://github.com/fellipesalazar/ponto/releases/latest/download/Ponto.pkg).
2. Dê dois cliques nele.
3. Na primeira vez, o macOS avisa que não conseguiu verificar o arquivo, porque o Ponto não é assinado pela Apple. Feche o aviso, abra **Ajustes do Sistema > Privacidade e Segurança**, role até **Segurança** e clique em **Abrir Mesmo Assim**.
4. Siga o instalador. No fim, o Ponto abre sozinho na barra de menus.

Funciona no macOS 13 ou mais novo.

## Atualizar

Não precisa fazer nada. O Ponto procura versão nova sozinho e pergunta se você quer atualizar. Também dá pra procurar na hora pelo menu do ícone, em **Procurar atualização**.

## Como funciona

- **Entrada:** cobra no horário padrão (9h, se você não mudar).
- **Almoço:** cobra no início da janela. Você adia até sair de verdade.
- **Volta:** cobra quando o almoço completa a duração configurada.
- **Saída:** cobra quando a jornada fecha, pela hora real da entrada e do almoço.

**Bater agora** abre a página do ponto e espera você confirmar. Se você não confirmar em 2 minutos, o alerta volta. O Ponto não bate o ponto por você: ele registra o que você confirma.

Em chamada (microfone em uso), a trava vira um aviso discreto no canto e só volta quando a chamada acaba.

Fora do padrão (entrou mais cedo, voltou antes, saiu mais cedo), use o menu do ícone ou o atalho ⌃⌥P.

## Atalhos

Em qualquer lugar:

| Atalho | O que faz |
| --- | --- |
| ⌃⌥P | Bate a próxima marcação, ou confirma que bateu |
| ⌃⌥M | Abre o painel do Ponto |

Dá pra trocar os dois em Ajustes > Atalhos.

Com a tela travada:

| Tecla | O que faz |
| --- | --- |
| ↩ | Bater agora |
| J | Já bati |
| 1, 2, 3, 4 | Lembrar em 5, 10, 15 ou 30 min |
| N | Hoje não trabalho, ou hoje sem almoço |
| ⌃⌥⌘Q | Fecha o Ponto (emergência) |

## Seus dados

Tudo fica no seu Mac. Os ajustes e o link do ponto ficam nas preferências do app, e o histórico em `~/Library/Application Support/Ponto/historico.json`. O Ponto só usa a internet pra procurar versão nova aqui no GitHub.

## Remover

Saia do Ponto pelo menu, apague o Ponto de Aplicativos e, se quiser limpar tudo:

```
defaults delete br.com.ponto.lembrete
rm -rf ~/Library/Application\ Support/Ponto
```

## Pra quem for mexer no código

O código fica em `Sources/Ponto`, em Swift, sem dependências. A cada mudança na `main`, o GitHub compila num Mac e publica a versão que está no `Info.plist`. Pra compilar no seu Mac:

```
bash tools/build.sh
```
