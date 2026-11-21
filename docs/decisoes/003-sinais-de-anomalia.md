# 003 — Como cada sinal de anomalia é calculado

**Status:** aceita · **Data:** 2026-11-16

## Contexto

O projeto aponta onde olhar com cinco sinais (ver CLAUDE.md). Aplicados ao pé da letra, vários só fariam ruído: aluguel de escritório é exclusivo de um deputado por natureza, combustível em fim de semana é rotina de viagem, e conta de telefone repete o mesmo "número" todo mês. Os limites abaixo saíram da distribuição dos dados de 2023 a 2026 e ficam em `vars` do `dbt_project.yml`, para ajuste sem mexer no SQL.

Em todos os sinais, **nulo quer dizer "não dá para avaliar"** (CPF, CNPJ ainda não consultado, subcota fora do escopo), que é diferente de falso.

## Antes dos sinais: partido na data da nota

O arquivo anual grava o partido **atual** do deputado em todas as notas, inclusive as anteriores a uma troca: nenhum deputado tem mais de um partido no arquivo, e o partido dele é igual ao último evento do histórico em 645 de 646 deputados. O partido na data da nota vem de um SCD2 (`int_deputados_partido_periodos`) montado do histórico da API.

- Efeito: 134.335 notas (R$ 183,9 mi, 23,5% do total) mudam de partido. O PODE perde R$ 13,2 mi e o PDT ganha R$ 10,0 mi.
- A API data o evento "Nome no início da legislatura" de todas as legislaturas com o início da atual (2023-02-01). O staging corrige para 1º de fevereiro do ano 1795 + 4N (legislatura N) e descarta legislaturas futuras.
- Sem período no histórico (lideranças e 212 deputados só da legislatura 56), fica o partido do arquivo (`origem_partido = 'arquivo'`).

## Os sinais

| # | Sinal | Grão | Regra | Limite | Resultado |
|---|---|---|---|---|---|
| 1 | Empresa recente | fornecedor | dias entre a abertura do CNPJ e a primeira nota | ≤ 90 dias | 148 fornecedores, R$ 35,7 mi |
| 2 | CNAE incompatível | nota | nenhum CNAE (principal ou secundário) está na seed para a subcota | — | 1.992 notas, R$ 3,8 mi (+ R$ 66,0 mi só pelo secundário) |
| 3 | Fornecedor exclusivo | fornecedor | parte do faturamento vinda de uma só cota | ≥ 90% e ≥ R$ 100 mil | 879 fornecedores, R$ 217,8 mi |
| 4a | Fim de semana ou feriado | nota | emissão em sábado, domingo ou feriado nacional | — | 9.796 notas, R$ 23,6 mi |
| 4b | Nota repetida | nota | mesmo fornecedor e número de nota reembolsados acima do valor da nota | — | 10.820 notas, R$ 34,7 mi |
| 5 | Acima dos pares da UF | deputado | percentil do gasto médio mensal entre deputados da mesma UF | ≥ p90, com 6+ meses | 67 deputados |

### Por que cada escolha

1. **90 dias.** Dos 2.003 CNPJs com data de abertura, 80 abriram até 30 dias antes da primeira nota e outros 68 entre 31 e 90. Notas anteriores a 2023 não estão carregadas, mas só poderiam encurtar o prazo; quem é marcado continuaria marcado com o histórico inteiro.
2. **Mapa de CNAE por subcota** (`seeds/cnae_compativel_por_subcota.csv`), por divisão (2 dígitos) ou classe (4 dígitos) quando a divisão é larga demais: a divisão 47 mistura posto de combustível e papelaria, então combustível aceita só a classe 4731. O mapa partiu das atividades que mais recebem em cada subcota. Em escritório, o dono do imóvel alugado pode ser holding, incorporadora, construtora ou sindicato, e água e taxas são pagas a autarquia municipal; essas divisões entraram depois de aparecerem como falso positivo (R$ 2,7 mi a menos marcados).
   - **Validação do mapa, caso a caso.** Dos recusados, viraram aceitos os legítimos: associação e sindicato de taxistas e pedágio/estacionamento público em táxi (6.454 notas pequenas), fotocópia em divulgação, portaria em segurança, fundo de pensão dono de imóvel em escritório e loja de conveniência de posto em alimentação. Continuam marcados, por serem o que o sinal procura: combustível pago a imobiliária (1.443 notas), divulgação paga a consultório de psicologia, associação, revenda de carros e consultoria de gestão, escritório pago a escritório de advocacia, plantação de milho e fábrica de laminados.
   - **Três níveis de compatibilidade** (`compatibilidade_cnae`): `principal`, `secundario` e `nenhuma`. O sinal marca só `nenhuma`, mas R$ 66,0 mi passam apenas por um CNAE secundário (ex.: locação de veículos paga a empresa de limpeza predial, a construtora e a loja de armas). Essas empresas têm mediana de 11 atividades secundárias, contra 5 das que batem pelo principal. O nível `secundario` fica disponível para o ranking da fase 4 pesar como sinal fraco.
3. **Escritório fica de fora.** Aluguel e contas do escritório pertencem a um deputado só. Mesmo assim o sinal marca muito (589 fornecedores de divulgação): ele serve para combinar com os outros, não sozinho.
4. **4a só em serviços contratados** (escritório, consultoria, divulgação, segurança, publicações, cursos). Fim de semana é 20% das notas de combustível e 27% das de hospedagem, contra 3% em divulgação.
5. **4b compara a soma reembolsada com o valor da nota.** Nota paga em partes repete o número e o valor da nota e soma no máximo esse valor; quando a soma passa, o número foi usado mais de uma vez. Números como "S/N" e "00" são descartados; telefonia e táxi/pedágio ficam de fora (o número ali é conta ou bilhete). Exemplos achados: cupom de combustível reembolsado duas vezes no mesmo dia; nota de R$ 10 mil reembolsada 32 vezes em 3 anos.
6. **5 compara dentro da UF** porque o teto da cota varia por UF, e usa a média por mês com despesa para que um suplente que exerceu poucos meses não pareça econômico.

## Consequências

- Nenhum sinal é acusação. Sozinho, cada um tem falso positivo (ex.: empresa de transporte por aplicativo recém-aberta que atende 14 deputados); o ranking da fase 4 combina os sinais.
- A cobertura do sinal 1 e do 2 acompanha a da Receita: hoje 74,9% do valor pago a PJ.
- O mapa de CNAE é julgamento e deve ser revisto quando a cobertura da Receita crescer.
