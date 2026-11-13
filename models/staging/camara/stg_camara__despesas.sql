-- Uma linha por nota (ou parcela) da cota parlamentar, tipada e limpa.
-- Não existe chave natural: ide_documento repete (e vale 0 em ~30 mil notas); a chave é um
-- hash das colunas que identificam a nota, sem nenhuma linha repetida no arquivo.

with origem as (
    select * from {{ source('camara', 'despesas') }}
),

limpo as (
    select
        {{ dbt_utils.generate_surrogate_key([
            'ide_documento', 'num_parcela', 'nu_deputado_id', 'txt_numero', 'num_ano', 'num_mes',
            'num_sub_cota', 'num_especificacao_sub_cota', 'vlr_documento', 'vlr_liquido',
            'dat_emissao', 'txt_cnpjcpf', 'txt_passageiro', 'txt_trecho', 'num_lote', 'num_ressarcimento',
        ]) }} as despesa_id,
        nullif(ide_documento, '0')::bigint as documento_camara_id,

        -- Quem gastou. Lideranças partidárias usam a cota sem ser deputado: sem ide_cadastro
        -- e com UF 'NA'. nu_deputado_id é o id da cota e existe para os dois.
        ide_cadastro::integer as deputado_id,
        nu_deputado_id::integer as cota_id,
        ide_cadastro is null as eh_lideranca,
        trim(tx_nome_parlamentar) as nome_parlamentar,
        nullif(sg_uf, 'NA') as uf,
        sg_partido as partido,
        cod_legislatura::integer as legislatura,

        -- O que foi gasto
        num_sub_cota::integer as subcota_id,
        rtrim(trim(txt_descricao), '.') as subcota,
        nullif(num_especificacao_sub_cota, '0')::integer as especificacao_id,
        nullif(trim(txt_descricao_especificacao), '') as especificacao,

        -- Com quem. O documento chega com máscara às vezes errada (085.324.290/0013-1);
        -- só os dígitos importam: 14 = CNPJ, 11 = CPF.
        regexp_replace(txt_cnpjcpf, '[^0-9]', '', 'g') as documento_fornecedor,
        case length(regexp_replace(txt_cnpjcpf, '[^0-9]', '', 'g'))
            when 14 then 'PJ'
            when 11 then 'PF'
        end as tipo_fornecedor,
        trim(txt_fornecedor) as nome_fornecedor,

        -- A nota. O código 3 e o 4 não estão no dicionário da Câmara; o 4 é quase todo
        -- combustível com hora de emissão, consistente com nota fiscal eletrônica.
        nullif(trim(txt_numero), '') as numero_nota,
        ind_tipo_documento::integer as tipo_documento_id,
        case ind_tipo_documento
            when '0' then 'Nota fiscal'
            when '1' then 'Recibo'
            when '2' then 'Despesa no exterior'
            when '4' then 'Nota fiscal eletrônica'
            else 'Não documentado'
        end as tipo_documento,
        num_parcela::integer as parcela,
        nullif(trim(txt_passageiro), '') as passageiro,
        nullif(trim(txt_trecho), '') as trecho,
        num_lote::bigint as lote_id,
        nullif(num_ressarcimento, '')::bigint as ressarcimento_id,
        url_documento,

        -- Datas. Horário de Brasília, sem fuso: fica timestamp sem fuso, de propósito.
        -- Só combustível traz hora; telefonia vem sem data (a competência cobre).
        strptime(dat_emissao, '%Y-%m-%dT%H:%M:%S') as emitida_em,
        strptime(dat_emissao, '%Y-%m-%dT%H:%M:%S')::date as data_emissao,
        num_ano::integer as ano,
        num_mes::integer as mes,
        make_date(num_ano::integer, num_mes::integer, 1) as competencia,

        -- Valores com ponto decimal. O líquido é o que a Câmara pagou, e é o que se soma.
        -- Nota paga em partes vira várias linhas que repetem o valor_documento inteiro
        -- (772 notas de 2023 a 2026): somar valor_documento conta essas notas duas vezes.
        -- vlr_restituicao e dat_pagamento_restituicao vêm vazios em todas as notas e ficam de fora.
        vlr_documento::decimal(14, 2) as valor_documento,
        vlr_glosa::decimal(14, 2) as valor_glosa,
        vlr_liquido::decimal(14, 2) as valor_liquido,

        to_timestamp(_dlt_load_id::double) as carregado_em
    from origem
)

select * from limpo
