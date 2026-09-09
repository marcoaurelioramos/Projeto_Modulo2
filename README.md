# Documentação Técnica e Guia de Execução - Projeto Pata Amiga

Este repositório contém a solução completa de Engenharia e Análise de Dados para a rede de petshops **Pata Amiga**, contemplando a carga da área de staging, a construção do modelo dimensional (Star Schema) e as consultas de Business Intelligence (BI) para tomada de decisão executiva.



## 1. Soluções e Arquitetura do Projeto

A solução foi desenvolvida para **PostgreSQL 16**, adotando a metodologia de Modelagem Dimensional de Ralph Kimball:

* **Modelagem Star Schema:**
  * **Tabela Fato:** `fato_pedido` mantendo o grão exato de **4.044 linhas** (1 linha por pedido).
  * **Dimensões:** `dim_tempo`, `dim_loja`, `dim_categoria`, `dim_praca` e a tabela ponte `bridge_loja_praca`.
* **Tratamento da Linha Sentinela (`-1`):** 
  * Para evitar valores `NULL` nas chaves estrangeiras (FKs) da fato, dados ausentes/órfãos são mapeados para a linha `-1 = "Nao Informado"`. Exemplo: os 3 pedidos sem identificação de loja foram associados à `sk_loja = -1`.
* **Tratamento de Dados Financeiros e Numéricos:**
  * Formatações de moeda brasileiras e americanas e colunas com textos em branco ou hífens (`"-"`) foram convertidas de forma limpa para `NULL` (nunca zero), preservando a precisão matemática nos cálculos de médias do banco.
* **Métricas Operacionais de Prazos:**
  * Prazos em dias calculados individualmente para cada uma das 5 etapas logísticas. Pedidos em aberto gravam `NULL` no encerramento da esteira para não poluir o cálculo da média ponderada via `AVG()`.
* **Rateio de Faturamento N:N:**
  * Uso da `bridge_loja_praca` com o atributo `fator_publico` para ratear o faturamento das lojas físicas entre as praças de atendimento proporcionalmente ao público-alvo de cada região.



## 2. Guia de Execução para o Avaliador

Para rodar o projeto e validar os resultados finais, siga a sequência exata de execução dos scripts SQL listada abaixo:

 **1º**  `01-staging.sql` | Criação das tabelas de staging e carga dos arquivos CSV brutos. |
 **2º**  `02-dimensoes-prontas.sql` | DDL das tabelas de dimensão prontas (`dim_tempo`, `dim_loja`) e da `fato_pedido`. |
 **3º**  `03-dimensoes.sql` | Povoamento das dimensões (`dim_categoria`, `dim_praca`, `bridge_loja_praca`) e criação da linha sentinela `-1`. |
 **4º**  `04-fato.sql` | Execução do **único `INSERT ... SELECT`** para povoar a `fato_pedido` (retorna `INSERT 0 4044`). |
 **5º**  `05-perguntas.sql` | Execução das consultas analíticas oficiais para responder às 5 questões de negócio. |



## Tarefa 1: Diagnóstico da Origem

Após a execução da carga da staging (`01-carga-staging.sql`), foi realizada uma análise detalhada dos dados brutos nas três tabelas recebidas (`stg_pedido`, `stg_loja`, `stg_loja_praca`). Identificaram-se os seguintes pontos de atenção e inconsistências:

1. **Grafias e Identificação de Loja:**
   * **Há 128 de variações de grafias** para nomes de lojas com inconsistências (ex: *PATA AMIGA BLUMENAL CENTRO*, *FLORIPA*, *JGUA DO SUL*, sufixos `/SC`).
	SELECT DISTINCT("Loja-Nome") FROM STG_PEDIDO;

   * **1.575 pedidos** vieram com o campo `Cod Loja` em branco na tabela `stg_pedido`.
	COUNT("Cod Loja") FROM stg_pedido WHERE "Cod Loja" IS NULL OR TRIM("Cod Loja") = '';

   * **3 pedidos** não possuem nenhuma identificação de loja (sem código e sem nome).
	SELECT COUNT("Cod Loja")  FROM stg_pedido WHERE ("Cod Loja" IS NULL OR TRIM("Cod Loja") = '')   AND ("Loja-Nome" IS NULL OR TRIM("Loja-Nome") = '');


2. **Grafias de Categoria:**
   * Foram encontradas **37 grafias distintas** para categorias de produtos na coluna `CategoriaProduto`, contendo erros de acentuação, maiúsculas/minúsculas e abreviações (ex: *Racao*, *RACAO*, *Rac.*, *Ração Medicamentosa*). 

SELECT DISTINCT("CategoriaProduto") FROM STG_PEDIDO;

3. **Grafias de Houve Desconto:**
   * Na coluna `HouveDesconto` exitem **17 grafias distintas**, contendo, maiúsculas/minúsculas, abreviações e vazios (ex: *SITE*, *site*, *APP*, *tel.*). 

SELECT DISTINCT("HouveDesconto") FROM STG_PEDIDO;

4. **Grafias de Canal Pedido:**
   * A coluna `CanalPedido` tem **20 grafias distintas**, contendo, maiúsculas/minúsculas, numeros, abreviações e vazios (ex: *SIM*, *sim*, *1*, *false*). 

SELECT DISTINCT("CanalPedido") FROM STG_PEDIDO;

5. **Marcos de Processo em Branco (Processos em Aberto):**
   * **1.077** pedidos sem data de separação (`Dt Separacao Estoque`).
	SELECT COUNT("Dt Separacao Estoque") FROM STG_PEDIDO WHERE "Dt Separacao Estoque" IS NULL OR TRIM("Dt Separacao Estoque") = '';

   * **1.338** pedidos sem data de nota fiscal (`DtNotaFiscal`).
	SELECT COUNT("DtNotaFiscal") FROM STG_PEDIDO WHERE "DtNotaFiscal" IS NULL OR TRIM("DtNotaFiscal") = '';

   * **1.665** pedidos sem data de despacho (`Dt_Despacho_Transportadora`).
	SELECT COUNT("Dt_Despacho_Transportadora") FROM STG_PEDIDO WHERE "Dt_Despacho_Transportadora" IS NULL OR TRIM("Dt_Despacho_Transportadora") = '';
	
   * **1.953** pedidos sem data de entrega (`DtEntregaCliente`), representando processos de entrega ainda não concluídos.
	SELECT COUNT("DtEntregaCliente") FROM STG_PEDIDO WHERE "DtEntregaCliente" IS NULL OR TRIM("DtEntregaCliente") = '';



## Tarefa 2 : Tratamento

Os tratamentos foram implementados diretamente na carga do modelo dimensional, divididos entre os arquivos `03-dimensoes.sql` e `04-fato.sql`.

# Mapeamento dos Tratamentos do Item 2 (Desafio) nos Scripts SQL

Os tratamentos solicitados na **Seção 2 (DESAFIO)** e detalhados na **Seção 4 (REQUISITOS DAS TAREFAS)** do documento foram implementados diretamente durante a carga do modelo dimensional, divididos entre os arquivos `03-dimensoes.sql` e `04-fato.sql`.

### 1. Para as Datas:

* **Como foi feito:**
  * Para a data do pedido (`DtHoraPedido` e `DtHoraIntegracaoERP`), usou-se:
        TO_TIMESTAMP(sp."DtHoraPedido", 'MM/DD/YYYY HH12:MI AM')
  
  * Para a chave da dimensão de tempo (`sk_tempo_pedido`), foi extraído o inteiro no formato `AAAAMMDD`:
        TO_CHAR(..., 'YYYYMMDD')::INT
   
  * Para os marcos de processo (*Separação, Nota Fiscal, Despacho e Entrega*), aplicou-se a conversão direta para data via 
        `::DATE`.


### 2. Limpeza e Conversão de Valores Financeiros e Quantidades
* **Como foi feito:**
  * **Valor em Reais (`vl_liquido`):** Foi aplicada a expressão `CASE WHEN` com `REPLACE` e `CAST` para remover `"R$"`, pontos de milhar, converter vírgulas em pontos e mapear campos vazios ou `"-"` para `NULL` :
    CASE 
        WHEN TRIM(REPLACE(sp."ValorLiquidoPedido(R$)", 'R$', '')) IN ('', '-') THEN NULL
        WHEN sp."ValorLiquidoPedido(R$)" LIKE '%,%' 
            THEN CAST(REPLACE(REPLACE(REPLACE(REPLACE(sp."ValorLiquidoPedido(R$)", 'R$', ''), ' ', ''), '.', ''), ',', '.') AS DECIMAL(15,2))
        ELSE CAST(REPLACE(REPLACE(sp."ValorLiquidoPedido(R$)", 'R$', ''), ' ', '') AS DECIMAL(15,2))
    END AS vl_liquido
    
    
  * **Quantidade de Itens (`qt_itens`):** Convertida via `CAST(sp."QTD.Itens" AS INTEGER)`.



### 3. Para Padronização das Grafias de Categoria (De-Para das 37 Grafias para 7 Oficiais)
* **Como foi feito:**
  * Foi aplicado um `CASE WHEN` sobre a coluna `CategoriaProduto`, usando `UPPER(TRANSLATE(...))` para ignorar acentos e maiúsculas/minúsculas.
  * **Respeito à precedência lógica:** A regra do termo `'MED'` foi testada em **1º lugar** no `CASE` para garantir que *"Ração Medicamentosa"* fosse classificada corretamente como **Medicamento** e não como Ração.
  * A grafia crua original foi guardada em `categoria_origem` para permitir o `JOIN` posterior com a fato.



### 4. Para Padronização do Nome da Loja (Apelidos, Erros de Digitação e Abreviaturas)
* **Como foi feito:**
  * Foi utilizado um `CASE WHEN` manual combinado com `REPLACE` para corrigir as 3 exceções conhecidas antes do cruzamento com a `dim_loja`:
    * `"BLUMENAL"` $\rightarrow$ `PATA AMIGA BLUMENAU CENTRO`
    * `"FLORIPA"` $\rightarrow$ `PATA AMIGA FLORIANOPOLIS NORTE`
    * `"JGUA DO SUL"` $\rightarrow$ `PATA AMIGA JARAGUA DO SUL`
  * Removeu-se o sufixo `"/SC"` e aplicou-se `UPPER(TRANSLATE(...))` para comparar byte a byte com a coluna `chave_loja` da `dim_loja`.



### 5. Para Padronização de "Houve Desconto" e "Canal do Pedido"
* **Como foi feito:**
  * **Houve Desconto:** Agrupou as 17 variações (`S`, `SIM`, `1`, `X`, `TRUE`, `V` / `N`, `NAO`, `0`, `FALSE`, `F`) nos domínios `'Sim'`, `'Nao'` ou `'Nao Informado'`.
  * **Canal do Pedido:** Mapeou as variantes utilizando `CASE WHEN` e testando `'WHATS'` **antes** de `'APP'` para evitar que pedidos de WhatsApp fossem erroneamente atribuídos ao App.



### 6. Para Tratamento de Marcos em Branco e Pedidos sem Loja (Processos em Aberto / Integridade Referencial)
* **Como foi feito:**
  * **Entregas não concluídas:** Atribuiu-se `sk_tempo_entrega = -1` (apontando para a linha `-1` de `dim_tempo`) e gravou-se `NULL` nas colunas de prazos em dias (garantindo que o `AVG` ignore processos não concluídos em vez de calcular com zero).
  * **Pedidos sem loja identificada (3 pedidos):** Utilizou-se `COALESCE(dl.sk_loja, -1)` para vincular à linha `-1` (*"Nao Informado"*) de `dim_loja`, mantendo a integridade sem chaves estrangeiras nulas.


  # Respostas às Perguntas de Negócio (P1 a P5)

As análises abaixo foram consolidadas a partir da execução dos scripts SQL no modelo dimensional (`fato_pedido`, dimensões e tabela bridge), permitindo responder às perguntas estratégicas da diretoria da Pata Amiga.



### **P1: Onde está o gargalo da entrega?**

* **Tempo Médio Total:** O tempo médio geral entre a entrada do pedido no ERP e a entrega ao cliente é de **9,00 dias**.
* **O Gargalo:** O processo mais lento é a etapa de **Nota Fiscal -> Despacho**, que consome em média **4,11 dias** (representando **45,67%** de todo o tempo do ciclo).
* **Análise por Porte:**
  * **Lojas Grandes:** Média total de **7,92 dias** (Nota -> Despacho: **3,30 dias**).
  * **Lojas Médias:** Média total de **7,94 dias** (Nota -> Despacho: **3,34 dias**).
  * **Lojas Pequenas:** Média total de **15,04 dias** (Nota -> Despacho: **8,41 dias** — principal ponto crítico operacional).



### **P2: Qual categoria concentra o faturamento?**

Do faturamento total faturado pela rede (**R$ 3.586.617,02**), a distribuição por categoria padronizada ocorre da seguinte forma:

1. **Racao:** R$ 2.152.405,10 (**60,01%**) — *Campeã absoluta, representando mais da metade da receita da rede*
2. **Medicamento:** R$ 611.808,06 (**17,06%**)
3. **Petisco:** R$ 257.180,32 (**7,17%**)
4. **Servico:** R$ 188.002,74 (**5,24%**)
5. **Higiene:** R$ 184.628,90 (**5,15%**)
6. **Acessorio:** R$ 129.322,78 (**3,61%**)
7. **Brinquedo:** R$ 63.269,12 (**1,76%**)

* **Análise de Negócio:** A categoria **Ração** é o pilar financeiro da Pata Amiga, concentrando sozinho 60% de todas as vendas da rede, seguida por **Medicamentos** (17%). Juntas, as duas categorias representam mais de 77% de todo o faturamento da empresa.



### **P3: O desconto funciona igual em todo canal?**

* **Distribuição do Faturamento por Canal:**
  1. **App:** R$ 1.104.268,86 (**30,79%**) — *Principal canal de vendas da rede*
  2. **Site:** R$ 901.138,74 (**25,13%**)
  3. **Loja Fisica:** R$ 721.354,44 (**20,11%**)
  4. **WhatsApp:** R$ 377.357,26 (**10,52%**)
  5. **Telefone:** R$ 246.838,58 (**6,88%**)
  6. **Nao Informado:** R$ 235.659,14 (**6,57%**)

* **Comportamento do Ticket Médio (COM vs. SEM Desconto):**
  * O desconto **funciona como um forte alavancador de valor em todos os canais de venda** sem exceção.
  * Em média, pedidos aplicados com desconto possuem um ticket médio mais de **2,5 a 3 vezes superior** aos pedidos sem desconto. Por exemplo, no **App**, o ticket médio sobe de **R$ 170,48** (sem desconto) para **R$ 488,04** (com desconto).
  * **Conclusão de Negócio:** As promoções e cupons da Pata Amiga são altamente eficazes para aumentar o volume de compras, pois estimulam os clientes a adicionarem mais itens para atingirem as condições do desconto.

### **P4: Qual praça de atendimento concentra o faturamento?**

Aplicando o fator de público da tabela ponte (`bridge_loja_praca`) sobre o faturamento das lojas, a soma rateada atribui a receita das praças de acordo com os seguintes valores reais apurados:

1. **Grande Florianopolis:** R$ 448.899,86 — *132.000 domicílios com pet* (Líder em faturamento total)
2. **Norte Industrial:** R$ 296.748,73 — *96.000 domicílios com pet*
3. **Litoral Sul:** R$ 229.964,89 — *58.000 domicílios com pet*
4. **Litoral Norte:** R$ 228.869,41 — *61.000 domicílios com pet*
5. **Extremo Oeste:** R$ 142.795,07 — *63.000 domicílios com pet*
6. **Serra Catarinense:** R$ 142.289,95 — *44.000 domicílios com pet*
7. **Carbonifera:** R$ 129.556,77 — *67.000 domicílios com pet*
8. **Meio-Oeste:** R$ 86.728,03 — *51.000 domicílios com pet*
9. **Foz do Itajaí:** R$ 77.997,32 — *74.000 domicílios com pet*
10. **Planalto Serrano:** R$ 47.463,58 — *29.000 domicílios com pet*
11. **Planalto Norte:** R$ 41.977,53 — *33.000 domicílios com pet*

* **Destaque da Análise:** A praça da **Grande Florianópolis** é a principal centralizadora de receita da rede, seguida pela praça do **Norte Industrial**. Praças como o **Litoral Sul** apresentam um faturamento por domicílio com pet bastante expressivo quando comparadas a praças de porte similar como o Extremo Oeste.


### **P5: Onde abrir a próxima loja, e o que os dados NÃO permitem afirmar?**

#### **1. Recomendação de Expansão (Ranking de Itens por 1.000 Habitantes):**
Analisando os dados reais apurados por loja/cidade, o ranking de penetração de vendas relativas revela o seguinte cenário:

1. **Rio dos Cedros:** **83,73** itens / 1.000 hab — *Média de entrega: 14,24 dias*
2. **Ibirama:** **64,15** itens / 1.000 hab  — *Média de entrega: 15,39 dias*
3. **Santo Amaro da Imperatriz:** **47,41** itens / 1.000 hab  — *Média de entrega: 15,88 dias*
4. **Presidente Getúlio:** **44,13** itens / 1.000 hab  — *Média de entrega: 13,74 dias*
5. **Itapoá:** **37,60** itens / 1.000 hab  — *Média de entrega: 14,85 dias*

* **Decisão Estratégica:** A abertura da próxima loja física/hub logístico deve focar no Alto/Médio Vale (região de **Ibirama / Rio dos Cedros**). O volume de vendas proporcional por habitante é o maior de toda a rede (mais de 60 a 80 itens por 1.000 hab), porém temos gargalos logísticos severos (prazos de entrega superiores a 14-15 dias). Instalar um ponto presencial na região resolverá o gargalo operacional e capturará a alta demanda reprimida.



#### **2. O que os dados NÃO permitem afirmar (Limitações do Histórico):**
* **Sobrescrevimento do Histórico de Franquias:** A tabela de lojas (`stg_loja`) apresenta a **foto atual** do enquadramento de franquia (Bronze, Prata, Ouro, Diamante). Como o cadastro não guarda a data em que a loja mudou de faixa, **não é possível afirmar se uma venda realizada há 1 ano veio de uma loja que já possuía a faixa atual**.
* **Faixas de Franquia Sobrescritas:** Agrupar faturamento por `faixa_franquia` aplica a classificação do presente sobre pedidos do passado, mascarando a evolução histórica do programa de franquias.



#### **3. Métricas do que Ficou de Fora (Limites da Carga):**
* **3 pedidos** não possuíam identificação de loja de origem na staging (alocados em `sk_loja = -1`).
* **1.953 pedidos** ainda não concluíram o ciclo de entrega (marcos em aberto gravados como `NULL` nos dias para não poluir as médias).
* **Ausência de Valores Financeiros/Quantidades:** Registros com `"-"` ou em branco foram convertidos para `NULL` (preservando o cálculo correto de médias sem transformar ausência de dado em R$ 0,00 ou 0 itens).


## Arquivos complementares

### **Diagrama do Modelo Demensional**
* O Diagrama do Modelo Dimensional está no arquivo com mesmo nome em formato PNG(diagrama_modelo_dimensional.png) juntamente com os demais arquivos do projeto.

### **Video**
* O Video explicativo do projeto está no GoogleDrive e pode ser acessado através do link:
   
