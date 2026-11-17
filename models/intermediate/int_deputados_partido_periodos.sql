-- SCD2 de partido: um período por deputado e partido, com início e fim.
-- O arquivo de despesas grava o partido ATUAL do deputado em todas as notas, inclusive as
-- de antes de uma troca; o partido na data da nota sai daqui.

-- Um evento por deputado e instante. Quando a posse e o "Nome no início da legislatura" caem
-- no mesmo instante com partidos diferentes, vale a posse: o outro traz a sigla renomeada
-- depois (PPB virou PP, PL virou PR). Só acontece em legislaturas antigas.
with eventos as (
    select deputado_id, ocorrido_em, partido, evento_id
    from {{ ref('stg_camara__deputados_historico') }}
    qualify row_number() over (
        partition by deputado_id, ocorrido_em
        order by descricao_status like 'Nome no início da legislatura%', evento_id
    ) = 1
),

-- Marca cada evento em que o partido muda em relação ao evento anterior do mesmo deputado.
-- evento_id só desempata eventos no mesmo minuto, para o resultado não variar entre execuções.
mudancas as (
    select
        *,
        partido is distinct from lag(partido) over (
            partition by deputado_id order by ocorrido_em, evento_id
        ) as inicia_periodo
    from eventos
),

inicios as (
    select deputado_id, partido, ocorrido_em as valido_de
    from mudancas
    where inicia_periodo
)

select
    {{ dbt_utils.generate_surrogate_key(['deputado_id', 'valido_de']) }} as periodo_id,
    deputado_id,
    partido,
    valido_de,
    -- Fim exclusivo: o período vale até o instante em que o próximo começa.
    lead(valido_de) over (partition by deputado_id order by valido_de) as valido_ate,
    lead(valido_de) over (partition by deputado_id order by valido_de) is null as eh_atual
from inicios
