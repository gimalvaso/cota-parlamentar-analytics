# CLAUDE.md

Projeto de portfólio de analytics engineering: **"Para onde vai o dinheiro da cota parlamentar?"** — ingestão → modelagem → painel no Power BI, sobre as despesas da CEAP (cota parlamentar) dos deputados federais. Visão geral e arquitetura no [README](README.md).

## Problema de negócio

Apontar **quem gasta fora do padrão e com quais fornecedores**. Sinais a modelar:

1. Empresa aberta poucos dias antes do primeiro pagamento (data de abertura do CNPJ × data da nota).
2. CNAE do fornecedor incompatível com o tipo de despesa (ex.: posto de gasolina emitindo "consultoria").
3. Fornecedor concentrado num único deputado.
4. Gasto em fim de semana ou feriado; nota repetida.
5. Deputado acima dos pares da mesma UF (o teto da cota varia por UF).

Sinal não é acusação: o painel aponta onde olhar.

## Stack

- Python 3.12 via **uv** (`uv sync`, `uv run ...`). O python do sistema é 3.14 e não tem suporte do dbt; sempre use `uv run`.
- **dlt** para ingestão → **DuckDB** em `data/cota.duckdb` (fora do git).
- **dbt-core + dbt-duckdb**, `profiles.yml` na raiz (rodar com `uv run dbt ... --profiles-dir .`).
- **Power BI** no consumo (Windows; o projeto roda no WSL). Decidir como o Power BI lê o mart: Parquet exportado ou driver ODBC do DuckDB.
- **GitHub Actions** para agendamento e CI (a fazer).

## Fontes e o que já se sabe delas

| Fonte | Uso | Armadilhas conhecidas |
|---|---|---|
| Arquivo anual `camara.leg.br/cotas/Ano-{ano}.csv.zip` | despesas (raw_camara.despesas) | CNPJ com máscara errada (`085.324.290/0013-1`), lideranças partidárias sem `ide_cadastro`, `dat_emissao` sem fuso (horário de Brasília) |
| API `dadosabertos.camara.leg.br/api/v2` | deputados + histórico de partido | `/deputados` repete o deputado que trocou de partido (deduplicado na ingestão); histórico inclui legislaturas anteriores; `data_hora` sem fuso |
| BrasilAPI `/cnpj/v1` e `/feriados/v1` | cadastro do fornecedor, feriados | limite de requisições; cache incremental (`--limite-cnpj`, maiores fornecedores primeiro) |

O endpoint de despesas da API **não** é usado: diverge do arquivo oficial (sinal invertido, estornos soltos, notas a mais). Evidência em `docs/decisoes/001-despesas-do-arquivo-anual.md`.

Datas sem fuso ficam como **texto** no raw (o dlt gravaria como UTC e deslocaria 3h); a tipagem é no staging.

## Status

- [x] Fase 1 — Ingestão (`ingestion/`), testada com 2025: R$ 214 mi, igual ao oficial.
- [ ] Fase 2 — Staging (sources já declarados em `models/staging/*/_*__sources.yml`)
- [ ] Fase 3 — Intermediate: SCD2 de partido a partir do histórico, cruzamento com a Receita, regras de cada sinal
- [ ] Fase 4 — Marts: OBT de despesas + agregados por deputado e fornecedor, exposures
- [ ] Fase 5 — Painel no Power BI (3 páginas: visão geral, ranking de anomalias, raio-x do fornecedor)
- [ ] Fase 6 — Vitrine: README final, dicionário de métricas, achados, Actions

## Convenções

- Tudo em **português**: código comentado, docs, commits, PRs.
- Camadas stg → int → mart. Staging só tipa, renomeia e limpa; regra de negócio no intermediate. Mart enxuto: preferir **OBT** a várias fatos; nada de modelo sem consumidor.
- Testes com severidade padrão `warn`; só vira `error` o teste cuja falha prova dado errado que ninguém perceberia a jusante.
- Decisão não óbvia vira registro em `docs/decisoes/NNN-*.md`, com evidência.
- Validar no banco de verdade antes de cada commit: linhas, totais contra o oficial, efeito a jusante.
- Commits pequenos, um por camada ou assunto (conventional commits em português).
- Nada de dado, código ou nome de empresa empregadora neste repositório.
