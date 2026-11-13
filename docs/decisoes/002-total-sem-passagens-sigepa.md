# 002 — O total do projeto não inclui passagens aéreas emitidas pela Câmara (SIGEPA)

**Status:** aceita · **Data:** 2026-11-12

## Contexto

Ao validar 2023 a 2026 contra números publicados, o total do projeto ficou cerca de 10% abaixo:

| Ano | Soma de `vlr_liquido` no arquivo | Número publicado na imprensa |
|---|---|---|
| 2023 | R$ 201,16 mi | R$ 229,9 mi |
| 2024 | R$ 211,44 mi | R$ 234,8 mi a R$ 235,7 mi |

## O que a investigação mostrou

- **A ingestão é fiel ao arquivo.** O `Ano-2024.csv` baixado de novo tem 173.961 linhas, as mesmas 173.961 do raw, e o staging bate com o raw ao centavo nos quatro anos.
- **As categorias batem quando existem no arquivo.** Divulgação da atividade parlamentar em 2024: R$ 100,15 mi no projeto e R$ 100,1 mi na imprensa.
- **Falta a categoria "PASSAGEM AÉREA - SIGEPA".** O arquivo de 2024 só tem `PASSAGEM AÉREA - REEMBOLSO` (305 notas, R$ 1,08 mi) e `PASSAGEM AÉREA - RPA` (98 notas, R$ 0,13 mi). A imprensa fala em R$ 34,9 mi de passagens aéreas em 2024. As passagens que a própria Câmara emite (SIGEPA) não estão no arquivo anual.
- A diferença restante entre as fontes de imprensa (R$ 219 mi a R$ 236 mi para 2024) vem de data de corte e metodologia, que elas não detalham.

## Decisão

- O projeto mede o que está no arquivo oficial de despesas: o total é a soma de `valor_liquido`, sem as passagens emitidas via SIGEPA.
- A validação "contra o oficial" passa a ser: linhas do raw = linhas do arquivo, e staging = raw ao centavo.
- O painel informa, na visão geral, que passagens aéreas emitidas pela Câmara não entram.

## Consequências

- Passagem aérea aparece subdimensionada no ranking de categorias; nenhum sinal depende dela.
- Se a Câmara voltar a publicar o SIGEPA no arquivo, a categoria entra sozinha na próxima carga.

## Fontes

- [Diário do Poder, 2024](https://diariodopoder.com.br/coluna-claudio-humberto/deputados-embolsaram-mais-de-r234-milhoes-para-ressarcir-despesas-so-em-2024)
- [Correio Braziliense, 20/01/2025](https://edicao.correiobraziliense.com.br/correiobraziliense/2025/01/20/13588b/pdf/A03-POL-2001-DIG.pdf)
- [Itatiaia, divulgação do mandato por ano](https://www.itatiaia.com.br/politica/deputados-gastam-centenas-de-milhoes-com-divulgacao-do-mandato-veja-valores-por-estado/)
