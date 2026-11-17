-- Um fornecedor por linha (CNPJ ou CPF): quanto recebeu, de quantas cotas, e o cadastro na
-- Receita. Calcula os sinais que olham o fornecedor inteiro:
--   1. empresa aberta pouco antes do primeiro pagamento;
--   3. fornecedor que vive de uma cota só.
-- Sinal nulo = não dá para avaliar (CPF, CNPJ ainda não consultado ou sem data de abertura),
-- que é diferente de falso.

with despesas as (
    select
        documento_fornecedor,
        tipo_fornecedor,
        nome_fornecedor,
        cota_id,
        subcota_id,
        coalesce(data_emissao, competencia) as data_referencia,
        valor_liquido
    from {{ ref('stg_camara__despesas') }}
),

por_cota as (
    select documento_fornecedor, cota_id, sum(valor_liquido) as valor_cota
    from despesas
    group by all
),

maior_cota as (
    select documento_fornecedor, cota_id as cota_principal_id, valor_cota as valor_cota_principal
    from por_cota
    qualify row_number() over (partition by documento_fornecedor order by valor_cota desc, cota_id) = 1
),

por_subcota as (
    select documento_fornecedor, subcota_id as subcota_principal_id
    from despesas
    group by documento_fornecedor, subcota_id
    qualify row_number() over (partition by documento_fornecedor order by sum(valor_liquido) desc, subcota_id) = 1
),

fornecedores as (
    select
        documento_fornecedor,
        any_value(tipo_fornecedor) as tipo_fornecedor,
        -- O nome vem digitado em cada nota; fica o do maior valor.
        arg_max(nome_fornecedor, valor_liquido) as nome_fornecedor,
        min(data_referencia) as primeira_nota,
        max(data_referencia) as ultima_nota,
        count(*) as notas,
        count(distinct cota_id) as cotas,
        sum(valor_liquido) as valor_total
    from despesas
    group by 1
),

receita as (
    select * from {{ ref('stg_brasilapi__cnpj') }}
),

perfil as (
    select
        f.documento_fornecedor,
        f.tipo_fornecedor,
        f.nome_fornecedor,
        f.primeira_nota,
        f.ultima_nota,
        f.notas,
        f.cotas,
        f.valor_total,
        m.cota_principal_id,
        m.valor_cota_principal / nullif(f.valor_total, 0) as parte_cota_principal,
        s.subcota_principal_id,

        r.cnpj is not null as consultado_na_receita,
        r.encontrado_na_receita,
        r.razao_social,
        r.cnae_principal_id,
        r.cnae_principal,
        r.situacao_cadastral,
        r.data_abertura,
        f.primeira_nota - r.data_abertura as dias_abertura_ate_primeira_nota
    from fornecedores as f
    inner join maior_cota as m using (documento_fornecedor)
    inner join por_subcota as s using (documento_fornecedor)
    left join receita as r on r.cnpj = f.documento_fornecedor
)

select
    *,

    -- Sinal 1. Notas anteriores a 2023 não estão carregadas, mas só poderiam encurtar o
    -- prazo; então quem é marcado aqui seria marcado com o histórico inteiro também.
    case
        when data_abertura is null then null
        else dias_abertura_ate_primeira_nota <= {{ var('sinal_empresa_recente_dias') }}
    end as sinal_empresa_recente,

    -- Sinal 3. Escritório fica de fora: aluguel e contas do escritório pertencem a um
    -- deputado só por natureza.
    case
        when subcota_principal_id = 1 then null
        else parte_cota_principal >= {{ var('sinal_exclusivo_parte_minima') }}
            and valor_total >= {{ var('sinal_exclusivo_valor_minimo') }}
    end as sinal_fornecedor_exclusivo
from perfil
