-- Um deputado por linha: quem exerceu mandato na legislatura configurada na ingestão.
-- Sem partido: a listagem traz uma linha por partido de quem trocou, e a ingestão fica com
-- a primeira, que nem sempre é a atual. Partido vem do histórico (int_deputados_partido_periodos).

with origem as (
    select * from {{ source('camara', 'deputados') }}
)

select
    id::integer as deputado_id,
    trim(nome) as nome,
    sigla_uf as uf,
    id_legislatura::integer as legislatura,
    url_foto,
    to_timestamp(_dlt_load_id::double) as carregado_em
from origem
