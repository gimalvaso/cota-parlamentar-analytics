# 001 — Despesas vêm do arquivo anual, não do endpoint da API

**Status:** aceita · **Data:** 2026-11-12

## Contexto

A Câmara publica as despesas da cota parlamentar de dois jeitos:

1. Endpoint `GET /api/v2/deputados/{id}/despesas` da API de Dados Abertos, paginado, um deputado por vez.
2. Arquivo anual `https://www.camara.leg.br/cotas/Ano-{ano}.csv.zip`, com todas as notas do ano (o mesmo dado que o site da cota mostra).

O plano inicial era usar a API para tudo.

## O que o teste mostrou

Carregamos 2025 para dois deputados (ids 204379 e 220714) pelos dois caminhos e comparamos:

| | API | Arquivo anual |
|---|---|---|
| Notas | 695 | 517 |
| Notas com `valorLiquido` negativo | 537 | 0 |
| Soma do valor líquido | −R$ 0,99 mi (em módulo, R$ 1,23 mi) | R$ 0,91 mi |

Na API aparecem pares que se anulam (`+3121,60` e `−3121,60` no mesmo documento), lançamentos com lote `0` e o sinal do valor líquido invertido na maioria das notas. No arquivo anual, das 170.589 notas de 2025, só 3 têm valor negativo (devoluções legítimas).

## Decisão

- **Despesas:** arquivo anual. É o dado oficial, consistente e chega com uma requisição por ano em vez de cerca de 10 mil.
- **Deputados e histórico de partido:** API. Esses endpoints estão corretos e não existem no arquivo.
- **Recarga:** cada ano é apagado e regravado inteiro (`delete-insert` por `num_ano`). A Câmara corrige notas meses depois; assim as correções entram e notas removidas somem.

## Consequências

- Perdemos a granularidade de "buscar só o mês novo"; recarregar um ano inteiro leva segundos, então não faz falta.
- O arquivo traz armadilhas próprias, tratadas no staging: CNPJ com máscara errada (`085.324.290/0013-1` para `08532429000131`), despesas de lideranças partidárias sem id de deputado, data de emissão sem fuso.
