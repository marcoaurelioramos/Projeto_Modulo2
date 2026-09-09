-- =====================================================================================
-- ARQUIVO 05: AS CINCO PERGUNTAS DE NEGOCIO
-- Case: Pata Amiga - rede de petshops de SC | PostgreSQL 16
-- =====================================================================================
-- Rode depois de: 04-fato.sql
-- =====================================================================================

-- =====================================================================================
-- P1: Onde está o gargalo da entrega?
-- =====================================================================================
SELECT 
    CASE 
        WHEN GROUPING(dl.porte) = 1 THEN '-- MÉDIA GERAL DA REDE --'
        ELSE COALESCE(dl.porte, 'Sem Loja Identificada')
    END AS porte_loja,
    ROUND(AVG(fato.dias_total_ate_entrega), 2) AS total_dias_entrega,
    ROUND(AVG(fato.dias_integracao_separacao), 2) AS integracao_ate_separacao,
    ROUND(AVG(fato.dias_separacao_nota), 2) AS separacao_ate_nota,
    ROUND(AVG(fato.dias_nota_despacho), 2) AS NOTA_ATE_DESPACHO_GARGALO,
    ROUND(AVG(fato.dias_despacho_entrega), 2) AS despacho_ate_entrega,
    ROUND((AVG(fato.dias_nota_despacho) / AVG(fato.dias_total_ate_entrega)) * 100, 2) || '%' AS pct_gargalo_no_total
FROM fato_pedido fato
LEFT JOIN dim_loja dl ON fato.sk_loja = dl.sk_loja
GROUP BY GROUPING SETS ((dl.porte), ())
ORDER BY GROUPING(dl.porte) DESC, porte_loja ASC;


-- =====================================================================================
-- P2: Qual categoria concentra o faturamento?
-- =====================================================================================
SELECT 
    dc.nome_categoria,
    SUM(fato.vl_liquido) AS faturamento_categoria,
    ROUND(100.0 * SUM(fato.vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS pct_faturamento_total
FROM fato_pedido fato
JOIN dim_categoria dc ON fato.sk_categoria = dc.sk_categoria
GROUP BY dc.nome_categoria
ORDER BY faturamento_categoria DESC;


-- =====================================================================================
-- P3: O desconto funciona igual em todo canal?
-- =====================================================================================
SELECT 
    fato.canal_pedido,
    SUM(fato.vl_liquido) AS faturamento_canal,
    ROUND(100.0 * SUM(fato.vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS pct_faturamento_canal,
    ROUND(AVG(CASE WHEN fato.houve_desconto = 'Sim' THEN fato.vl_liquido END), 2) AS ticket_medio_com_desconto,
    ROUND(AVG(CASE WHEN fato.houve_desconto = 'Nao' THEN fato.vl_liquido END), 2) AS ticket_medio_sem_desconto
FROM fato_pedido fato
GROUP BY fato.canal_pedido
ORDER BY faturamento_canal DESC;


-- =====================================================================================
-- P4: Qual praça de atendimento concentra o faturamento?
-- =====================================================================================
SELECT 
    dp.nome_praca,
    dp.domicilios_com_pet,
    ROUND(SUM(fato.vl_liquido * br.fator_publico), 2) AS faturamento_rateado
FROM fato_pedido fato
JOIN dim_loja dl ON fato.sk_loja = dl.sk_loja
JOIN bridge_loja_praca br ON dl.cod_loja = br.cod_loja
JOIN dim_praca dp ON br.sk_praca = dp.sk_praca
GROUP BY dp.nome_praca, dp.domicilios_com_pet
ORDER BY faturamento_rateado DESC;


-- =====================================================================================
-- P5: Onde abrir a próxima loja, e o que os dados NÃO permitem afirmar?
-- =====================================================================================
-- P5.1: Ranking de lojas por itens vendidos por mil habitantes
SELECT 
    dl.nome_loja,
    dl.cidade,
    dl.populacao_cidade,
    SUM(fato.qt_itens) AS total_itens_vendidos,
    ROUND((SUM(fato.qt_itens) * 1000.0) / dl.populacao_cidade, 2) AS itens_por_mil_hab,
    ROUND(AVG(fato.dias_total_ate_entrega), 2) AS media_dias_entrega
FROM fato_pedido fato
JOIN dim_loja dl ON fato.sk_loja = dl.sk_loja
WHERE dl.sk_loja <> -1
GROUP BY dl.nome_loja, dl.cidade, dl.populacao_cidade
ORDER BY itens_por_mil_hab DESC;

-- P5.2: Faturamento por Faixa Atual de Franquia
SELECT 
    COALESCE(dl.faixa_franquia, 'Sem Franquia/Sem Loja') AS faixa_franquia_atual,
    SUM(fato.vl_liquido) AS faturamento
FROM fato_pedido fato
LEFT JOIN dim_loja dl ON fato.sk_loja = dl.sk_loja
GROUP BY dl.faixa_franquia
ORDER BY faturamento DESC;

-- P5.3: Métricas de Limitação
SELECT 
    (SELECT COUNT(*) FROM fato_pedido WHERE sk_loja = -1) AS pedidos_sem_loja_identificada,
    (SELECT COUNT(*) FROM fato_pedido WHERE sk_tempo_entrega = -1) AS entregas_nao_concluidas,
    (SELECT COUNT(*) FROM fato_pedido WHERE vl_liquido IS NULL) AS pedidos_sem_valor_liquido,
    (SELECT COUNT(*) FROM fato_pedido WHERE qt_itens IS NULL) AS pedidos_sem_quantidade_itens;