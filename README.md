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
   * **Há variações de grafias** para nomes de lojas com inconsistências (ex: *PATA AMIGA BLUMENAL CENTRO*, *FLORIPA*, *JGUA DO SUL*, sufixos `/SC`).
   * **1.575 pedidos** vieram com o campo `Cod Loja` em branco na tabela `stg_pedido`.
   * **3 pedidos** não possuem nenhuma identificação de loja (sem código e sem nome).

2. **Grafias de Categoria:**
   * Foram encontradas **37 grafias distintas** para categorias de produtos na coluna `CategoriaProduto`, contendo erros de acentuação, maiúsculas/minúsculas e abreviações (ex: *Racao*, *RACAO*, *Rac.*, *Ração Medicamentosa*). 

3. **Grafias de Houve Desconto:**
   * Na coluna `HouveDesconto` existem **17 grafias distintas**, contendo maiúsculas/minúsculas, abreviações e vazios (ex: *SIM*, *sim*, *1*, *false*). 

4. **Grafias de Canal Pedido:**
   * A coluna `CanalPedido` tem **20 grafias distintas**, contendo maiúsculas/minúsculas, números, abreviações e vazios (ex: *SITE*, *site*, *APP*, *tel.*). 

5. **Marcos de Processo em Branco (Processos em Aberto):**
   * **1.077** pedidos sem data de separação (`Dt Separacao Estoque`).
   * **1.338** pedidos sem data de nota fiscal (`DtNotaFiscal`).
   * **1.665** pedidos sem data de despacho (`Dt_Despacho_Transportadora`).
   * **1.953** pedidos sem data de entrega (`DtEntregaCliente`), representando processos de entrega ainda não concluídos.



## Tarefa 2: Tratamento

Os tratamentos foram implementados diretamente durante a carga do modelo dimensional, divididos entre os arquivos `03-dimensoes.sql` e `04-fato.sql`.

### 1. Para as Datas:
* Para a data do pedido (`DtHoraPedido` e `DtHoraIntegracaoERP`), usou-se: `TO_TIMESTAMP(sp."DtHoraPedido", 'MM/DD/YYYY HH12:MI AM')`.
* Para a chave da dimensão de tempo (`sk_tempo_pedido`), extraiu-se o inteiro no formato `AAAAMMDD`: `TO_CHAR(..., 'YYYYMMDD')::INT`.
* Para os marcos de processo (*Separação, Nota Fiscal, Despacho e Entrega*), aplicou-se a conversão direta para data via `::DATE`.

### 2. Limpeza e Conversão de Valores Financeiros e Quantidades
* **Valor em Reais (`vl_liquido`):** Foi aplicada a expressão `CASE WHEN` com `REPLACE` e `CAST` para remover `"R$"`, pontos de milhar, converter vírgulas em pontos e mapear campos vazios ou `"-"` para `NULL`.
* **Quantidade de Itens (`qt_itens`):** Convertida via `CAST(sp."QTD.Itens" AS INTEGER)`.

### 3. Padronização das Grafias de Categoria
* Foi aplicado um `CASE WHEN` sobre a coluna `CategoriaProduto`, usando `UPPER(UNACCENT(...))` para ignorar acentos e maiúsculas/minúsculas.
* **Precedência lógica:** A regra do termo `'MED'` foi testada em 1º lugar para garantir que *"Ração Medicamentosa"* fosse classificada como **Medicamento** e não Ração.

### 4. Padronização do Nome da Loja
* Utilizou-se `CASE WHEN` combinado com `REPLACE` para tratar as exceções (`BLUMENAL`, `FLORIPA`, `JGUA DO SUL`) e limpeza de caracteres especiais (`REGEXP_REPLACE` + `UNACCENT`) para efetuar o join perfeito com `dim_loja`.

### 5. Padronização de "Houve Desconto" e "Canal do Pedido"
* **Houve Desconto:** Agrupou as variações nos domínios `'Sim'`, `'Nao'` ou `'Nao Informado'`.
* **Canal do Pedido:** Mapeou as variantes testando `'WHATS'` antes de `'APP'` para evitar sobreposição.

### 6. Tratamento de Marcos em Branco e Pedidos sem Loja
* **Entregas não concluídas:** Atribuiu-se `sk_tempo_entrega = -1` e gravou-se `NULL` nos prazos em dias.
* **Pedidos sem loja (3 pedidos):** Utilizou-se `COALESCE(dmlo.sk_loja, -1)` para vincular à linha `-1` (*"Nao Informado"*).



## Respostas às Perguntas de Negócio (P1 a P5)

As análises abaixo foram consolidadas a partir da execução exata das consultas SQL oficiais no modelo dimensional (`05-perguntas.sql`).



### **P1: Onde está o gargalo da entrega?**

* **Tempo Médio Total:** O tempo médio geral entre a entrada do pedido no ERP e a entrega ao cliente é de **9,00 dias**.
* **O Gargalo:** O processo mais lento é a etapa de **Nota Fiscal -> Despacho**, que consome em média **4,11 dias** (representando **45,64%** de todo o tempo do ciclo).
* **Análise por Porte:**
  * **Lojas Grandes:** Média total de **7,93 dias** (Nota -> Despacho: **3,32 dias** | **41,82%** do tempo).
  * **Lojas Médias:** Média total de **7,95 dias** (Nota -> Despacho: **3,34 dias** | **42,00%** do tempo).
  * **Lojas Pequenas:** Média total de **15,16 dias** (Nota -> Despacho: **8,53 dias** | **56,28%** do tempo — principal ponto crítico operacional).



### **P2: Qual categoria concentra o faturamento?**

Do faturamento total faturado pela rede (**R$ 1.793.308,51**), a distribuição por categoria padronizada ocorre da seguinte forma:

1. **Racao:** R$ 1.164.812,95 (**64,95%**) — *Campeã absoluta, representando quase dois terços da receita da rede*
2. **Medicamento:** R$ 217.293,63 (**12,12%**)
3. **Petisco:** R$ 128.590,16 (**7,17%**)
4. **Servico:** R$ 94.001,37 (**5,24%**)
5. **Higiene:** R$ 92.314,45 (**5,15%**)
6. **Acessorio:** R$ 64.661,39 (**3,61%**)
7. **Brinquedo:** R$ 31.634,56 (**1,76%**)

* **Análise de Negócio:** A categoria **Ração** é o pilar financeiro da Pata Amiga, concentrando sozinha 64,95% de todas as vendas da rede, seguida por **Medicamentos** (12,12%). Juntas, as duas categorias representam mais de 77% de todo o faturamento da empresa.



### **P3: O desconto funciona igual em todo canal?**

* **Distribuição do Faturamento por Canal:**
  1. **App:** R$ 552.134,43 (**30,79%**) — *Principal canal de vendas da rede*
  2. **Site:** R$ 450.569,37 (**25,13%**)
  3. **Loja Fisica:** R$ 360.677,22 (**20,11%**)
  4. **WhatsApp:** R$ 188.678,63 (**10,52%**)
  5. **Telefone:** R$ 123.419,29 (**6,88%**)
  6. **Nao Informado:** R$ 117.829,57 (**6,57%**)

* **Comportamento do Ticket Médio (COM vs. SEM Desconto):**
  * **App:** R$ 488,04 (com desconto) vs. R$ 170,48 (sem desconto)
  * **Site:** R$ 501,92 (com desconto) vs. R$ 189,48 (sem desconto)
  * **Loja Física:** R$ 494,04 (com desconto) vs. R$ 196,78 (sem desconto)
  * **WhatsApp:** R$ 514,33 (com desconto) vs. R$ 173,88 (sem desconto)
  * **Telefone:** R$ 514,02 (com desconto) vs. R$ 195,46 (sem desconto)
  * **Nao Informado:** R$ 561,59 (com desconto) vs. R$ 212,83 (sem desconto)
* **Conclusão de Negócio:** O desconto **funciona como um forte alavancador de valor em todos os canais de venda** sem exceção. Em média, pedidos com desconto possuem um ticket médio **2,5 a 3 vezes superior** aos pedidos sem desconto.



### **P4: Qual praça de atendimento concentra o faturamento?**

Aplicando o fator de público da tabela ponte (`bridge_loja_praca`) sobre o faturamento das lojas físicas, a soma rateada atribui a receita das praças de acordo com os seguintes valores reais apurados:

1. **Vale do Itajai:** R$ 633.746,09 — *148.000 domicílios com pet* (Líder isolada em faturamento rateado)
2. **Grande Florianopolis:** R$ 283.546,75 — *132.000 domicílios com pet*
3. **Norte Industrial:** R$ 175.431,90 — *96.000 domicílios com pet*
4. **Litoral Sul:** R$ 137.051,20 — *58.000 domicílios com pet*
5. **Litoral Norte:** R$ 128.872,75 — *61.000 domicílios com pet*
6. **Extremo Oeste:** R$ 98.359,18 — *63.000 domicílios com pet*
7. **Carbonifera:** R$ 88.707,42 — *67.000 domicílios com pet*
8. **Serra Catarinense:** R$ 80.477,64 — *44.000 domicílios com pet*
9. **Meio-Oeste:** R$ 58.955,63 — *51.000 domicílios com pet*
10. **Foz do Itajaí:** R$ 46.749,72 — *74.000 domicílios com pet*
11. **Planalto Norte:** R$ 31.100,84 — *33.000 domicílios com pet*
12. **Planalto Serrano:** R$ 29.323,10 — *29.000 domicílios com pet*

* **Destaque da Análise:** A praça do **Vale do Itajaí** é a principal centralizadora de receita rateada da rede, seguida pela praça da **Grande Florianópolis**. Praças como o **Litoral Sul** apresentam excelente eficiência de faturamento proporcional por domicílio com pet.



### **P5: Onde abrir a próxima loja, e o que os dados NÃO permitem afirmar?**

#### **1. Recomendação de Expansão (Ranking de Itens por 1.000 Habitantes):**
Analisando os dados reais apurados por loja/cidade, o ranking de penetração de vendas relativas revela os principais destaques:

1. **Rio dos Cedros:** **41,87** itens / 1.000 hab (474 itens) — *Média de entrega: 14,24 dias*
2. **Presidente Getúlio:** **34,84** itens / 1.000 hab (570 itens) — *Média de entrega: 14,16 dias*
3. **Ibirama:** **32,07** itens / 1.000 hab (597 itens) — *Média de entrega: 15,39 dias*
4. **Itapoá:** **25,94** itens / 1.000 hab (534 itens) — *Média de entrega: 15,39 dias*
5. **Santo Amaro da Imperatriz:** **23,71** itens / 1.000 hab (530 itens) — *Média de entrega: 15,88 dias*

* **Decisão Estratégica:** A abertura da próxima loja física/hub logístico deve focar no Vale do Itajaí / Médio Vale (região de **Rio dos Cedros / Presidente Getúlio / Ibirama**). O volume de vendas proporcional por habitante é o maior de toda a rede (entre 32 e 41 itens por 1.000 hab), porém há gargalos logísticos severos (prazos de entrega superiores a 14-15 dias). Instalar um ponto presencial na região resolverá o gargalo operacional e capturará a alta demanda reprimida.



#### **2. O que os dados NÃO permitem afirmar (Limitações do Histórico):**
* **Sobrescrevimento do Histórico de Franquias:** A tabela de lojas (`stg_loja`) apresenta a **foto atual** do enquadramento de franquia (Bronze: R$ 84.036,06, Prata: R$ 314.812,03, Ouro: R$ 1.011.264,38, Diamante: R$ 382.209,74). Como o cadastro não guarda a data em que a loja mudou de faixa, **não é possível afirmar se uma venda realizada no passado veio de uma loja que já possuía a faixa atual**.
* **Faixas de Franquia Sobrescritas:** Agrupar faturamento por `faixa_franquia` aplica a classificação do presente sobre pedidos do passado, mascarando a evolução histórica do programa de franquias.



#### **3. Métricas do que Ficou de Fora (Limites da Carga):**
* **3 pedidos** não possuíam identificação de loja de origem na staging (alocados em `sk_loja = -1`).
* **1.953 pedidos** ainda não concluíram o ciclo de entrega (marcos em aberto gravados como `NULL` nos dias para não poluir as médias).
* **121 pedidos** sem valor líquido (`vl_liquido IS NULL`).
* **257 pedidos** sem quantidade de itens (`qt_itens IS NULL`).


## Arquivos Complementares

### **Diagrama do Modelo Dimensional**
* O Diagrama do Modelo Dimensional está disponível no arquivo `diagrama_modelo_dimensional.png` na raiz do repositório.

### **Vídeo Explicativo**
* O vídeo explicativo do projeto (`Projeto-Modulo2.mp4`) está disponível no Google Drive e pode ser acessado através do link (https://drive.google.com/file/d/1kkiReYtmNh0TzlxMcbfHoUmLelTj1SaL/view?usp=sharing).