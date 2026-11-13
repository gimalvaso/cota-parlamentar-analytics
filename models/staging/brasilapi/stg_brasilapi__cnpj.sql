-- Cadastro na Receita de cada fornecedor PJ já consultado, uma linha por CNPJ.
-- Fica só o que os sinais usam (abertura, atividade, situação, porte); endereço, telefone e
-- sócios ficam no raw.

with origem as (
    select * from {{ source('brasilapi', 'cnpj') }}
)

select
    cnpj,
    status_consulta = 'encontrado' as encontrado_na_receita,
    trim(razao_social) as razao_social,
    nullif(trim(nome_fantasia), '') as nome_fantasia,
    cnae_fiscal::integer as cnae_principal_id,
    cnae_fiscal_descricao as cnae_principal,
    try_cast(data_inicio_atividade as date) as data_abertura,
    descricao_situacao_cadastral as situacao_cadastral,
    try_cast(data_situacao_cadastral as date) as data_situacao_cadastral,
    descricao_identificador_matriz_filial as matriz_filial,
    natureza_juridica,
    porte,
    capital_social::decimal(18, 2) as capital_social,
    opcao_pelo_mei as optante_mei,
    opcao_pelo_simples as optante_simples,
    municipio,
    uf,
    to_timestamp(_dlt_load_id::double) as consultado_em
from origem
