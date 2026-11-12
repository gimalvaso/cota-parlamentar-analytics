"""Fonte dlt da BrasilAPI: cadastro de CNPJ (Receita Federal) e feriados nacionais.

O endpoint de CNPJ tem limite de requisições agressivo e é lento. Por isso:
- só busca CNPJs que ainda não estão no banco (o cadastro muda pouco);
- limita quantos CNPJs busca por execução, e as execuções seguintes continuam de onde parou;
- CNPJ não encontrado (404) fica registrado, para não ser tentado de novo toda vez.
"""

from __future__ import annotations

import time
from collections.abc import Iterable, Iterator
from typing import Any

import dlt
from dlt.sources.helpers.requests import Client

BASE_URL = "https://brasilapi.com.br/api"

# Repete em 429/5xx com backoff, mas deixa 404 passar: CNPJ inexistente é um resultado.
_http = Client(raise_for_status=False, request_timeout=60).session


@dlt.source(name="brasilapi")
def brasilapi_source(cnpjs: list[str], anos: list[int], pausa_segundos: float = 0.5) -> Iterable[Any]:
    @dlt.resource(name="cnpj", primary_key="cnpj", write_disposition="merge")
    def cnpj() -> Iterator[dict[str, Any]]:
        for numero in cnpjs:
            resp = _http.get(f"{BASE_URL}/cnpj/v1/{numero}")
            if resp.status_code == 200:
                yield {**resp.json(), "cnpj": numero, "status_consulta": "encontrado"}
            elif resp.status_code in (400, 404):
                yield {"cnpj": numero, "status_consulta": "nao_encontrado"}
            else:
                resp.raise_for_status()
            time.sleep(pausa_segundos)

    @dlt.resource(name="feriados", primary_key=["date", "name"], write_disposition="replace")
    def feriados() -> Iterator[list[dict[str, Any]]]:
        for ano in anos:
            resp = _http.get(f"{BASE_URL}/feriados/v1/{ano}")
            resp.raise_for_status()
            yield resp.json()

    return cnpj, feriados
