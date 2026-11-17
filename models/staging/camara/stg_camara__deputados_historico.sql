-- Um evento do mandato por linha (posse, licença, troca de partido, mudança de nome), em todas
-- as legislaturas do deputado. Base do SCD2 de partido no intermediate.

with origem as (
    select * from {{ source('camara', 'deputados_historico') }}
)

select
    -- A API repete o evento "início da legislatura" na mesma data para mais de uma
    -- legislatura; por isso a legislatura entra na chave.
    {{ dbt_utils.generate_surrogate_key([
        'id', 'id_legislatura', 'data_hora', 'descricao_status', 'sigla_partido', 'situacao', 'condicao_eleitoral',
    ]) }} as evento_id,
    id::integer as deputado_id,
    -- Horário de Brasília, sem fuso, com minuto: fica timestamp sem fuso.
    -- A API data o evento "Nome no início da legislatura" de TODAS as legislaturas do deputado
    -- com o início da legislatura atual (2023-02-01), cada um com o partido da sua época. A
    -- data certa é 1º de fevereiro do primeiro ano da legislatura N, que é 1795 + 4N.
    case
        when descricao_status like 'Nome no início da legislatura%'
            then make_timestamp(1795 + 4 * id_legislatura, 2, 1, 0, 0, 0)
        else strptime(data_hora, '%Y-%m-%dT%H:%M')
    end as ocorrido_em,
    id_legislatura::integer as legislatura,
    sigla_partido as partido,
    sigla_uf as uf,
    trim(nome) as nome,
    trim(nome_eleitoral) as nome_eleitoral,
    situacao,
    condicao_eleitoral,
    descricao_status,
    to_timestamp(_dlt_load_id::double) as carregado_em
from origem
-- O mesmo defeito traz o início de legislaturas que ainda não começaram (a 58 é em 2027).
where 1795 + 4 * id_legislatura <= year(current_date)
