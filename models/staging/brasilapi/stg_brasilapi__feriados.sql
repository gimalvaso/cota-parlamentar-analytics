-- Feriados nacionais, um por data.

with origem as (
    select * from {{ source('brasilapi', 'feriados') }}
)

select
    date::date as data,
    name as nome,
    type as tipo
from origem
