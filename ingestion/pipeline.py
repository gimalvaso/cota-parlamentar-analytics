"""Roda a ingestão: Câmara primeiro, depois enriquece os CNPJs novos na BrasilAPI.

Exemplos:
    uv run python -m ingestion.pipeline                       # carga completa (anos do config.toml)
    uv run python -m ingestion.pipeline --anos 2025 2026       # só reprocessa estes anos
    uv run python -m ingestion.pipeline --deputados 204379     # histórico de 1 deputado só (teste)
    uv run python -m ingestion.pipeline --limite-cnpj 2000     # busca mais CNPJs nesta execução
"""

from __future__ import annotations

import argparse
from pathlib import Path

import dlt
import duckdb

from ingestion.brasilapi import brasilapi_source
from ingestion.camara import camara_api_source, camara_cota_source

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "cota.duckdb"


def _pipeline(nome: str, dataset: str) -> dlt.Pipeline:
    DB_PATH.parent.mkdir(exist_ok=True)
    return dlt.pipeline(
        pipeline_name=nome,
        destination=dlt.destinations.duckdb(str(DB_PATH)),
        dataset_name=dataset,
        progress="log",
    )


def cnpjs_pendentes(limite: int) -> list[str]:
    """CNPJs de fornecedores que ainda não foram consultados, dos que mais receberam primeiro.

    Fornecedor pessoa física (CPF, 11 dígitos) não tem cadastro na Receita e fica de fora.
    """
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        tem_cnpj = con.execute(
            "select count(*) from information_schema.tables where table_schema = 'raw_brasilapi' and table_name = 'cnpj'"
        ).fetchone()[0]
        ja_consultados = "select cnpj from raw_brasilapi.cnpj" if tem_cnpj else "select null::varchar as cnpj where false"
        return [
            r[0]
            for r in con.execute(
                f"""
                with fornecedores as (
                    select regexp_replace(txt_cnpjcpf, '[^0-9]', '', 'g') as documento, try_cast(vlr_liquido as double) as valor
                    from raw_camara.despesas
                )
                select documento
                from fornecedores
                where length(documento) = 14
                  and documento not in ({ja_consultados})
                group by 1
                order by sum(valor) desc
                limit ?
                """,
                [limite],
            ).fetchall()
        ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--anos", type=int, nargs="+", help="anos de despesas a (re)carregar")
    parser.add_argument("--deputados", type=int, nargs="+", help="restringe a estes ids de deputado")
    parser.add_argument("--limite-cnpj", type=int, default=500, help="máximo de CNPJs novos consultados")
    parser.add_argument("--pular-cnpj", action="store_true", help="não consulta a BrasilAPI")
    args = parser.parse_args()

    cota = camara_cota_source(anos=args.anos) if args.anos else camara_cota_source()
    camara = _pipeline("camara", "raw_camara")
    print(camara.run(camara_api_source(deputado_ids=args.deputados)))
    print(camara.run(cota))

    if args.pular_cnpj:
        return
    anos = args.anos or dlt.config["sources.camara.anos"]
    pendentes = cnpjs_pendentes(args.limite_cnpj)
    print(f"{len(pendentes)} CNPJs novos para consultar")
    print(_pipeline("brasilapi", "raw_brasilapi").run(brasilapi_source(cnpjs=pendentes, anos=anos)))


if __name__ == "__main__":
    main()
