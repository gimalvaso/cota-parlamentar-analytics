-- Uma nota por linha, com o partido do deputado na data da nota e os sinais que olham a nota:
--   2.  CNAE do fornecedor incompatível com o tipo de despesa;
--   4a. nota emitida em fim de semana ou feriado nacional;
--   4b. número de nota reembolsado acima do valor da própria nota.
-- Sinal nulo = não dá para avaliar; é diferente de falso.

with despesas as (
    select
        *,
        coalesce(emitida_em, competencia::timestamp) as referencia_em,
        -- Número da nota só com dígitos e sem zeros à esquerda; "S/N", "SN", "00" viram nulo.
        nullif(ltrim(regexp_replace(numero_nota, '[^0-9]', '', 'g'), '0'), '') as numero_nota_normalizado
    from {{ ref('stg_camara__despesas') }}
),

periodos as (
    select * from {{ ref('int_deputados_partido_periodos') }}
),

feriados as (
    select data from {{ ref('stg_brasilapi__feriados') }}
),

-- Sinal 2: compatível quando o CNAE principal ou algum secundário começa com um prefixo
-- aceito para a subcota (seeds/cnae_compativel_por_subcota.csv).
cnaes_do_cnpj as (
    select cnpj, lpad(cnae_principal_id::varchar, 7, '0') as cnae
    from {{ ref('stg_brasilapi__cnpj') }}
    where cnae_principal_id is not null
    union all
    select cnpj, lpad(cnae_id::varchar, 7, '0')
    from {{ ref('stg_brasilapi__cnaes_secundarios') }}
),

compatibilidade as (
    select
        d.documento_fornecedor,
        d.subcota_id,
        bool_or(starts_with(c.cnae, m.cnae_prefixo)) as compativel
    from (select distinct documento_fornecedor, subcota_id from despesas) as d
    inner join cnaes_do_cnpj as c on c.cnpj = d.documento_fornecedor
    inner join {{ ref('cnae_compativel_por_subcota') }} as m on m.subcota_id = d.subcota_id
    group by all
),

-- Sinal 4b: nota dividida em partes repete o valor_documento e soma no máximo esse valor.
-- Quando a soma reembolsada passa do valor da nota, o mesmo número foi usado mais de uma vez.
-- Telefonia e táxi/pedágio ficam de fora: o "número" ali é conta ou bilhete, que se repete.
numeros_repetidos as (
    select documento_fornecedor, numero_nota_normalizado
    from despesas
    where numero_nota_normalizado is not null
      and subcota_id not in (10, 122)
    group by all
    having count(*) > 1
       and sum(valor_liquido) > max(valor_documento) + 0.01
)

select
    d.despesa_id,
    d.deputado_id,
    d.cota_id,
    d.eh_lideranca,
    d.uf,
    -- Partido na data da nota pelo histórico; sem período (lideranças, deputados só da
    -- legislatura anterior), fica o partido que o arquivo traz.
    coalesce(p.partido, d.partido) as partido,
    case when p.partido is not null then 'historico' else 'arquivo' end as origem_partido,
    d.subcota_id,
    d.documento_fornecedor,
    d.numero_nota_normalizado,
    d.referencia_em,
    d.valor_liquido,

    case
        when c.compativel is null then null
        else not c.compativel
    end as sinal_cnae_incompativel,

    -- Só nos serviços contratados: em combustível, hospedagem, alimentação e transporte o
    -- fim de semana é rotina de viagem.
    case
        when d.data_emissao is null or d.subcota_id not in (1, 4, 5, 8, 12, 137) then null
        else dayofweek(d.data_emissao) in (0, 6) or f.data is not null
    end as sinal_fim_de_semana_ou_feriado,

    case
        when d.numero_nota_normalizado is null or d.subcota_id in (10, 122) then null
        else r.numero_nota_normalizado is not null
    end as sinal_nota_repetida
from despesas as d
left join periodos as p
    on p.deputado_id = d.deputado_id
   and d.referencia_em >= p.valido_de
   and (p.valido_ate is null or d.referencia_em < p.valido_ate)
left join compatibilidade as c
    on c.documento_fornecedor = d.documento_fornecedor
   and c.subcota_id = d.subcota_id
left join feriados as f on f.data = d.data_emissao
left join numeros_repetidos as r
    on r.documento_fornecedor = d.documento_fornecedor
   and r.numero_nota_normalizado = d.numero_nota_normalizado
