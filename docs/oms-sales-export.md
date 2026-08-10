# OMS 跟单表完整导出

以销售管理（全托）为主数据源，优先复用页面原生的“当前页全选 → 自定义复制所需字段（Excel 用）→ 一键复制/导出 Excel”链路。补充页面仅按销售结果中的 Goods、货品 SKU、卖家 ID 查询，不改变 OMS 筛选、不执行生产写操作。

## 1. 导出销售主表

1. 在已登录的销售管理页面打开浏览器 DevTools Console。
2. 可先设置 `window.__OMS_SALES_EXPORT_CONFIG__`，再粘贴执行 `scripts/oms_sales_export.browser.js`。
3. 浏览器会下载 `oms-sales-native-copy-*.json`。默认筛选与参考页面一致：

   - SKU 库存可售天数不超过 7 天
   - 选品状态为“已加入站点”
   - 非定制品
   - 非 JIT 商品
   - SKU 标签为“爆旺款SKU”
   - 仅展示命中 SKU

默认每页 300 条并逐页调用页面原生复制。超过 100,000 条会停止，避免误导出过大范围；可通过配置显式调整。

## 2. 补充页面

补充数据保存为 JSON，并通过主键关联：

| 清单键 | 页面/来源 | 关联键 | 页面原生链路 |
| --- | --- | --- | --- |
| `salesApi` | 销售管理列表响应 | 货品 SKU ID | 原生销售查询后补充同一批列表字段 |
| `leafCategory` | 全托货品列表 | Goods SPU ID | 批量查询 Goods ID → 自定义导出叶子类目 ID |
| `soldOut` | 销售管理 → 售罄看板 → 已售罄 | 货品 SKU ID | 全选 → 一键导出 Excel |
| `shipping` | 店铺查发货地 | 卖家 ID | 批量查询 → 导出 Excel |
| `quality` | 全托品质分 | Goods SPU ID | 页面查询；页面不可用时记录 `status: unavailable` |
| `flowLimit` | Global、EU、UDP 限流监控 | 货品 SKU ID | 选择“货品 SKU ID”批量查询，按区域和站点去重 |

补充源清单示例：

```json
{
  "salesApi": "sales-list.json",
  "leafCategory": "leaf-category.json",
  "soldOut": "sold-out.json",
  "shipping": "shipping-address.json",
  "quality": "quality.json",
  "flowLimit": [
    "flow-limit-global.json",
    "flow-limit-eu.json",
    "flow-limit-udp.json"
  ]
}
```

路径相对于清单文件本身解析。缺少某个补充源时，对应字段保持空白，不用 `0` 或“否”冒充未查询结果。

## 3. 生成工作簿

运行环境需要可解析稳定版 `@oai/artifact-tool`：

```bash
node scripts/oms_sales_to_xlsx.mjs \
  --input /path/to/oms-sales-native-copy.json \
  --enrichment /path/to/full-chain-sources.json \
  --template "/path/to/跟单表头.xlsx" \
  --output /path/to/跟单.xlsx \
  --preview /path/to/跟单-preview.png
```

输出保留模板的 26 列，并新增“字段来源”工作表，记录页面、取数方式、命中数量和不可用来源。卖家/Goods/货品 ID 使用精确整数显示格式，避免科学计数法。

## 字段规则

销售管理页面原生导出直接提供 14 个跟单字段：卖家 ID/名称、Goods SPU ID、货品 SKC/SKU ID、今日/近 7 日/近 30 日销量、库存与仓内库存可售天数、销售库存、仓内可用库存、已发货库存、已下单待发货库存。

- “是否销量突增”：今日销量大于近 7 日日均销量的 2 倍。
- `skc标签` 优先级：大爆款、爆款、旺款、平常款、滞销款；“新款”不覆盖该经营标签。
- 未出现在“已售罄”结果中的 SKU，售罄损失和售罄天数保持空白。
- 限流站点数对 Global、EU、UDP 的站点名称去重后汇总。
- 品质分页面不可用时仅记录失败状态；允许回退销售列表的品质等级描述，但不得编造数值分。
