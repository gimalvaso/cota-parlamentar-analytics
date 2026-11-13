-- Um deputado por linha: quem exerceu mandato na legislatura configurada na ingestão.
-- O partido daqui é o atual; o histórico de partido vem de stg_camara__deputados_historico.

with origem as (
    select * from {{ source('camara', 'deputados') }}
)

select
    id::integer as deputado_id,
    trim(nome) as nome,
    sigla_partido as partido_atual,
    sigla_uf as uf,
    id_legislatura::integer as legislatura,
    url_foto,
    to_timestamp(_dlt_load_id::double) as carregado_em
from origem
