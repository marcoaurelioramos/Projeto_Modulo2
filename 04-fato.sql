-- =====================================================================================
-- ARQUIVO 04: A TABELA FATO (fato_pedido)
-- Case: Pata Amiga - rede de petshops de SC | PostgreSQL 16
-- =====================================================================================
-- Rode depois de: 03-dimensoes.sql
-- =====================================================================================

INSERT INTO fato_pedido (
    numero_pedido,
    sk_tempo_pedido,
    sk_tempo_entrega,
    sk_loja,
    sk_categoria,
    houve_desconto,
    canal_pedido,
    dt_pedido,
    qt_itens,
    vl_liquido,
    dias_integracao_separacao,
    dias_separacao_nota,
    dias_nota_despacho,
    dias_despacho_entrega,
    dias_total_ate_entrega
)
SELECT
    -- Dimensão degenerada: número do pedido diretamente na fato
    stpe."NumeroPedido" AS numero_pedido,
    
    -- 1. FK Tempo Pedido: Converte MM/DD/YYYY HH12:MI AM para o número inteiro AAAAMMDD
    TO_CHAR(TO_TIMESTAMP(stpe."DtHoraPedido", 'MM/DD/YYYY HH12:MI AM'), 'YYYYMMDD')::INT AS sk_tempo_pedido,
    
    -- 2. FK Tempo Entrega: Se a entrega não ocorreu, aponta para a linha -1 (Role-playing dimension)
    COALESCE(
        CASE WHEN stpe."DtEntregaCliente" IS NOT NULL AND TRIM(stpe."DtEntregaCliente") <> ''
             THEN TO_CHAR(stpe."DtEntregaCliente"::DATE, 'YYYYMMDD')::INT
        END, -1
    ) AS sk_tempo_entrega,
    
    -- 3. FK Loja: Lookup após padronização do nome. Se não encontrar (3 pedidos sem loja), aponta para -1
    COALESCE(dmlo.sk_loja, -1) AS sk_loja,
    
    -- 4. FK Categoria: Lookup direto pela grafia crua da origem (categoria_origem)
    COALESCE(dmca.sk_categoria, -1) AS sk_categoria,
    
    -- 5. Normalização da coluna HouveDesconto (17 variações agrupadas em 3 domínios)
    CASE 
        WHEN UPPER(TRIM(stpe."HouveDesconto")) IN ('S', 'SIM', '1', 'X', 'TRUE', 'V') THEN 'Sim'
        WHEN UPPER(TRIM(stpe."HouveDesconto")) IN ('N', 'NAO', '0', 'FALSE', 'F') THEN 'Nao'
        ELSE 'Nao Informado'
    END AS houve_desconto,
    
    -- 6. Normalização do Canal do Pedido (A ORDEM IMPORTA: WHATS testado antes de APP)
    CASE 
        WHEN UPPER(TRANSLATE(stpe."CanalPedido", 'ÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÄËÏÖÜÇáéíóúàèìòùâêîôûãõäëïöüç', 'AEIOUAEIOUAEIOUAEIOUECaeiouaeiouaeiouaeiouec')) LIKE '%WHATS%' THEN 'WhatsApp'
        WHEN UPPER(TRANSLATE(stpe."CanalPedido", 'ÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÄËÏÖÜÇáéíóúàèìòùâêîôûãõäëïöüç', 'AEIOUAEIOUAEIOUAEIOUECaeiouaeiouaeiouaeiouec')) LIKE '%APP%' THEN 'App'
        WHEN UPPER(TRANSLATE(stpe."CanalPedido", 'ÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÄËÏÖÜÇáéíóúàèìòùâêîôûãõäëïöüç', 'AEIOUAEIOUAEIOUAEIOUECaeiouaeiouaeiouaeiouec')) LIKE '%SITE%' THEN 'Site'
        WHEN UPPER(TRANSLATE(stpe."CanalPedido", 'ÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÄËÏÖÜÇáéíóúàèìòùâêîôûãõäëïöüç', 'AEIOUAEIOUAEIOUAEIOUECaeiouaeiouaeiouaeiouec')) LIKE '%LOJA%' THEN 'Loja Fisica'
        WHEN UPPER(TRANSLATE(stpe."CanalPedido", 'ÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÄËÏÖÜÇáéíóúàèìòùâêîôûãõäëïöüç', 'AEIOUAEIOUAEIOUAEIOUECaeiouaeiouaeiouaeiouec')) LIKE '%TEL%' THEN 'Telefone'
        ELSE 'Nao Informado'
    END AS canal_pedido,
    
    -- Timestamp completo do pedido
    TO_TIMESTAMP(stpe."DtHoraPedido", 'MM/DD/YYYY HH12:MI AM') AS dt_pedido,
    
    -- Tratamento da Quantidade de itens (trata '-', valores vazios e textos não numéricos)
    CASE 
        WHEN TRIM(stpe."QTD.Itens") IN ('', '-', 'N/I', 'n/d') OR stpe."QTD.Itens" IS NULL THEN NULL
        ELSE CAST(TRIM(stpe."QTD.Itens") AS INTEGER)
    END AS qt_itens,
    
    -- Regra de limpeza dos valores financeiros (vl_liquido)
    CASE 
        WHEN TRIM(REPLACE(stpe."ValorLiquidoPedido(R$)", 'R$', '')) IN ('', '-') THEN NULL
        WHEN stpe."ValorLiquidoPedido(R$)" LIKE '%,%' 
            THEN CAST(REPLACE(REPLACE(REPLACE(REPLACE(stpe."ValorLiquidoPedido(R$)", 'R$', ''), ' ', ''), '.', ''), ',', '.') AS DECIMAL(15,2))
        ELSE CAST(REPLACE(REPLACE(stpe."ValorLiquidoPedido(R$)", 'R$', ''), ' ', '') AS DECIMAL(15,2))
    END AS vl_liquido,
    
    -- 7. Prazos em Dias: Grave NULL se o marco final não aconteceu (Processo em aberto)
    CASE WHEN stpe."Dt Separacao Estoque" IS NOT NULL AND TRIM(stpe."Dt Separacao Estoque") <> '' 
         THEN stpe."Dt Separacao Estoque"::DATE - TO_TIMESTAMP(stpe."DtHoraIntegracaoERP", 'MM/DD/YYYY HH12:MI AM')::DATE 
    END AS dias_integracao_separacao,

    CASE WHEN stpe."Dt Separacao Estoque" IS NOT NULL AND TRIM(stpe."Dt Separacao Estoque") <> '' AND stpe."DtNotaFiscal" IS NOT NULL AND TRIM(stpe."DtNotaFiscal") <> ''
         THEN stpe."DtNotaFiscal"::DATE - stpe."Dt Separacao Estoque"::DATE 
    END AS dias_separacao_nota,

    CASE WHEN stpe."DtNotaFiscal" IS NOT NULL AND TRIM(stpe."DtNotaFiscal") <> '' AND stpe."Dt_Despacho_Transportadora" IS NOT NULL AND TRIM(stpe."Dt_Despacho_Transportadora") <> ''
         THEN stpe."Dt_Despacho_Transportadora"::DATE - stpe."DtNotaFiscal"::DATE 
    END AS dias_nota_despacho,

    CASE WHEN stpe."Dt_Despacho_Transportadora" IS NOT NULL AND TRIM(stpe."Dt_Despacho_Transportadora") <> '' AND stpe."DtEntregaCliente" IS NOT NULL AND TRIM(stpe."DtEntregaCliente") <> ''
         THEN stpe."DtEntregaCliente"::DATE - stpe."Dt_Despacho_Transportadora"::DATE 
    END AS dias_despacho_entrega,

    -- Intervalo Total: Resposta principal da P1
    CASE WHEN stpe."DtEntregaCliente" IS NOT NULL AND TRIM(stpe."DtEntregaCliente") <> ''
         THEN stpe."DtEntregaCliente"::DATE - TO_TIMESTAMP(stpe."DtHoraIntegracaoERP", 'MM/DD/YYYY HH12:MI AM')::DATE 
    END AS dias_total_ate_entrega

FROM stg_pedido stpe

-- Lookup de Categoria pela grafia crua
LEFT JOIN dim_categoria dmca ON stpe."CategoriaProduto" = dmca.categoria_origem

-- Lookup de Loja padronizando o nome da origem antes da comparação com dim_loja.chave_loja
LEFT JOIN dim_loja dmlo ON UPPER(TRANSLATE(
    CASE 
        WHEN UPPER(REPLACE(REPLACE(stpe."Loja-Nome", '/SC', ''), '  ', ' ')) LIKE '%BLUMENAL%' 
            THEN 'PATA AMIGA BLUMENAU CENTRO'
        WHEN UPPER(REPLACE(REPLACE(stpe."Loja-Nome", '/SC', ''), '  ', ' ')) LIKE '%FLORIPA%' 
            THEN 'PATA AMIGA FLORIANOPOLIS NORTE'
        WHEN UPPER(REPLACE(REPLACE(stpe."Loja-Nome", '/SC', ''), '  ', ' ')) LIKE '%JGUA DO SUL%' 
            THEN 'PATA AMIGA JARAGUA DO SUL'
        ELSE TRIM(REPLACE(REPLACE(stpe."Loja-Nome", '/SC', ''), '  ', ' '))
    END, 
    'ÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÄËÏÖÜÇáéíóúàèìòùâêîôûãõäëïöüç', 
    'AEIOUAEIOUAEIOUAEIOUECaeiouaeiouaeiouaeiouec'
)) = dmlo.chave_loja;