-- Atividades secundárias de cada CNPJ, uma linha por par CNPJ × CNAE. O dlt grava a lista
-- numa tabela filha; o join com a mãe só traz o CNPJ de volta.

with cnaes as (
    select * from {{ source('brasilapi', 'cnpj__cnaes_secundarios') }}
),

cnpj as (
    select _dlt_id, cnpj from {{ source('brasilapi', 'cnpj') }}
)

select
    cnpj.cnpj,
    cnaes.codigo::integer as cnae_id,
    cnaes.descricao as cnae
from cnaes
inner join cnpj on cnaes._dlt_parent_id = cnpj._dlt_id
-- Na base da Receita, CNPJ sem atividade secundária aparece com o código 0 ("Não informada").
where cnaes.codigo <> 0
