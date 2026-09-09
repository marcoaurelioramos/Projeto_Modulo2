-- =====================================================================================
-- ARQUIVO 03: CONSTRUÇÃO DAS DIMENSÕES E TABELA PONTE
-- Case: Pata Amiga - rede de petshops de SC | PostgreSQL 16
-- =====================================================================================
-- Rode depois de: 02-dimensoes-prontas.sql
-- =====================================================================================

-- =====================================================================================
-- 1. POVOAMENTO DA DIMENSÃO CATEGORIA (dim_categoria)
-- =====================================================================================

-- Inserção da Linha Sentinela -1
INSERT INTO dim_categoria (sk_categoria, categoria_origem, nome_categoria, grupo_categoria)
SELECT -1, 'Nao Informado', 'Nao Informado', 'Nao Informado'
WHERE NOT EXISTS (
    SELECT 1 FROM dim_categoria WHERE sk_categoria = -1
);

-- Carga do De-Para de categorias a partir da stg_pedido (alias stpe)
INSERT INTO dim_categoria (categoria_origem, nome_categoria, grupo_categoria)
SELECT DISTINCT
    stpe."CategoriaProduto" AS categoria_origem,
    CASE 
        WHEN UPPER(TRIM(stpe."CategoriaProduto")) LIKE '%RACA%' THEN 'Racao'
        WHEN UPPER(TRIM(stpe."CategoriaProduto")) LIKE '%MEDIC%' THEN 'Medicamento'
        WHEN UPPER(TRIM(stpe."CategoriaProduto")) LIKE '%PETISC%' THEN 'Petisco'
        WHEN UPPER(TRIM(stpe."CategoriaProduto")) LIKE '%HIGIEN%' THEN 'Higiene'
        WHEN UPPER(TRIM(stpe."CategoriaProduto")) LIKE '%ACESSOR%' THEN 'Acessorio'
        WHEN UPPER(TRIM(stpe."CategoriaProduto")) LIKE '%BRINQ%' THEN 'Brinquedo'
        WHEN UPPER(TRIM(stpe."CategoriaProduto")) LIKE '%SERV%' THEN 'Servico'
        ELSE 'Nao Informado'
    END AS nome_categoria,
    'Geral' AS grupo_categoria
FROM stg_pedido stpe
WHERE stpe."CategoriaProduto" IS NOT NULL AND TRIM(stpe."CategoriaProduto") <> ''
  AND NOT EXISTS (
      SELECT 1 FROM dim_categoria dmca WHERE dmca.categoria_origem = stpe."CategoriaProduto"
  );


-- =====================================================================================
-- 2. POVOAMENTO DA DIMENSÃO PRAÇA (dim_praca)
-- =====================================================================================

-- Inserção da Linha Sentinela -1
INSERT INTO dim_praca (sk_praca, cod_praca, nome_praca, domicilios_com_pet)
SELECT -1, 'N/I', 'Nao Informado', 0
WHERE NOT EXISTS (
    SELECT 1 FROM dim_praca WHERE sk_praca = -1
);

-- Carga das praças a partir da stg_loja_praca (alias stlp)
INSERT INTO dim_praca (cod_praca, nome_praca, domicilios_com_pet)
SELECT DISTINCT
    stlp."CodPraca" AS cod_praca,
    COALESCE(stlp."NomePraca", 'Praça ' || stlp."CodPraca") AS nome_praca,
    CAST(REPLACE(REPLACE(CAST(stlp."DomiciliosComPet" AS VARCHAR), '.', ''), ' ', '') AS INTEGER) AS domicilios_com_pet
FROM stg_loja_praca stlp
WHERE stlp."CodPraca" IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dim_praca dmpr WHERE dmpr.cod_praca = stlp."CodPraca"
  );


-- =====================================================================================
-- 3. POVOAMENTO DA TABELA PONTE (bridge_loja_praca)
-- =====================================================================================

-- Carga da ponte a partir da stg_loja_praca (alias stlp)
-- Mapeia a coluna de fator de público independentemente da variação do nome na staging
INSERT INTO bridge_loja_praca (cod_loja, sk_praca, fator_publico)
SELECT 
    stlp."CodLoja" AS cod_loja,
    dmpr.sk_praca,
    CAST(REPLACE(CAST(stlp."PercentualPublico" AS VARCHAR), ',', '.') AS DECIMAL(6,4)) AS fator_publico
FROM stg_loja_praca stlp
JOIN dim_praca dmpr ON stlp."CodPraca" = dmpr.cod_praca
WHERE NOT EXISTS (
    SELECT 1 FROM bridge_loja_praca brpr 
    WHERE brpr.cod_loja = stlp."CodLoja" AND brpr.sk_praca = dmpr.sk_praca
);


-- =====================================================================================
-- 4. VALIDAÇÃO DAS DIMENSÕES CARREGADAS
-- =====================================================================================
SELECT 'dim_categoria' AS tabela, COUNT(*) AS total_linhas FROM dim_categoria
UNION ALL SELECT 'dim_praca', COUNT(*) FROM dim_praca
UNION ALL SELECT 'bridge_loja_praca', COUNT(*) FROM bridge_loja_praca;