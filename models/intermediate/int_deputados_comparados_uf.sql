-- Um deputado por linha: gasto médio mensal e a posição dele entre os deputados da mesma UF.
-- Sinal 5: deputado acima dos pares. A comparação é dentro da UF porque o teto da cota
-- muda por UF (passagem para Brasília custa diferente de cada estado).
-- Média por mês com despesa: suplente que exerceu poucos meses não fica parecendo econômico.

with despesas as (
    select deputado_id, uf, competencia, valor_liquido
    from {{ ref('stg_camara__despesas') }}
    where not eh_lideranca
      and legislatura = 57
),

deputados as (
    select
        deputado_id,
        any_value(uf) as uf,
        count(distinct competencia) as meses_com_despesa,
        sum(valor_liquido) as valor_total,
        sum(valor_liquido) / count(distinct competencia) as gasto_medio_mensal
    from despesas
    group by 1
),

comparaveis as (
    select
        *,
        percent_rank() over (partition by uf order by gasto_medio_mensal) as percentil_na_uf,
        median(gasto_medio_mensal) over (partition by uf) as mediana_uf,
        count(*) over (partition by uf) as deputados_na_uf
    from deputados
    where meses_com_despesa >= {{ var('sinal_pares_uf_meses_minimos') }}
)

select
    d.deputado_id,
    d.uf,
    d.meses_com_despesa,
    d.valor_total,
    d.gasto_medio_mensal,
    c.deputados_na_uf,
    c.mediana_uf,
    d.gasto_medio_mensal / c.mediana_uf as razao_mediana_uf,
    c.percentil_na_uf,
    -- Nulo para quem teve poucos meses de despesa: fica fora da comparação.
    c.percentil_na_uf >= {{ var('sinal_pares_uf_percentil') }} as sinal_acima_pares_uf
from deputados as d
left join comparaveis as c using (deputado_id)
