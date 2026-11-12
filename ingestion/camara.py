"""Fontes dlt da Câmara dos Deputados.

- `camara_api`: deputados da legislatura e o histórico de cada um (partido, situação,
  nome). O histórico vira SCD2 no dbt. A API pagina pelo header `Link` e responde 429
  com `Retry-After`; o cliente HTTP do dlt respeita os dois.
- `camara_cota`: despesas da cota parlamentar (CEAP), do arquivo anual oficial.
  O endpoint de despesas da API diverge do arquivo (sinal invertido, estornos soltos,
  notas a mais) — ver docs/decisoes/001-despesas-do-arquivo-anual.md.

Tudo chega cru, como texto: tipagem, fuso e limpeza ficam no staging do dbt.
"""

from __future__ import annotations

import io
import tempfile
import zipfile
from collections.abc import Iterable, Iterator
from typing import Any

import dlt
import duckdb
import pyarrow as pa
from dlt.sources.helpers import requests
from dlt.sources.helpers.rest_client import RESTClient
from dlt.sources.helpers.rest_client.paginators import HeaderLinkPaginator

API_URL = "https://dadosabertos.camara.leg.br/api/v2"
COTA_URL = "https://www.camara.leg.br/cotas/Ano-{ano}.csv.zip"

# Datas sem fuso (horário de Brasília) ficam como texto no raw; o dlt as gravaria como UTC.
_TEXTO = {"data_type": "text"}


@dlt.source(name="camara_api")
def camara_api_source(legislatura: int = dlt.config.value, deputado_ids: list[int] | None = None) -> Iterable[Any]:
    """`deputado_ids` restringe a carga (útil para testar com poucos deputados)."""
    client = RESTClient(
        base_url=API_URL,
        headers={"Accept": "application/json"},
        paginator=HeaderLinkPaginator(),
        data_selector="dados",
    )

    @dlt.resource(name="deputados", primary_key="id", write_disposition="replace")
    def deputados() -> Iterator[list[dict[str, Any]]]:
        # Quem trocou de partido aparece uma vez por partido; o partido vem do histórico,
        # então aqui fica uma linha por deputado.
        vistos: set[int] = set()
        for pagina in client.paginate(
            "/deputados", params={"idLegislatura": legislatura, "itens": 100, "ordem": "ASC", "ordenarPor": "id"}
        ):
            unicos = [d for d in pagina if d["id"] not in vistos and (not deputado_ids or d["id"] in deputado_ids)]
            vistos.update(d["id"] for d in unicos)
            if unicos:
                yield unicos

    @dlt.transformer(
        data_from=deputados,
        name="deputados_historico",
        write_disposition="replace",
        parallelized=True,
        columns={"data_hora": _TEXTO},
    )
    def deputados_historico(pagina: list[dict[str, Any]]) -> Iterator[list[dict[str, Any]]]:
        for dep in pagina:
            yield from client.paginate(f"/deputados/{dep['id']}/historico")

    return deputados, deputados_historico


@dlt.source(name="camara_cota")
def camara_cota_source(anos: list[int] = dlt.config.value) -> Iterable[Any]:
    @dlt.resource(
        name="despesas",
        # Recarregar um ano apaga e regrava só aquele ano: pega as correções que a Câmara
        # faz depois, inclusive notas removidas, sem duplicar nada.
        write_disposition={"disposition": "merge", "strategy": "delete-insert"},
        merge_key="num_ano",
    )
    def despesas() -> Iterator[pa.Table]:
        for ano in anos:
            resp = requests.get(COTA_URL.format(ano=ano), timeout=300)
            with tempfile.TemporaryDirectory() as tmp:
                with zipfile.ZipFile(io.BytesIO(resp.content)) as zf:
                    csv_path = zf.extract(f"Ano-{ano}.csv", tmp)
                with duckdb.connect() as con:
                    tabela = con.execute(
                        "select * from read_csv(?, delim=';', header=true, all_varchar=true)", [csv_path]
                    ).fetch_arrow_table()
            yield tabela.rename_columns([_snake(c) for c in tabela.column_names])

    return despesas


def _snake(nome: str) -> str:
    """`txNomeParlamentar` -> `tx_nome_parlamentar`, `txtCNPJCPF` -> `txt_cnpjcpf`."""
    saida = []
    for i, ch in enumerate(nome):
        if ch.isupper() and i and not nome[i - 1].isupper():
            saida.append("_")
        saida.append(ch.lower())
    return "".join(saida)
