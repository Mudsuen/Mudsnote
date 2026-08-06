# OMS 销售管理跟单表导出

首阶段复用 OMS 销售管理（全托）页面原生的“当前页全选 → 自定义复制所需字段（Excel用）→ 一键复制”能力，不绕过页面权限，也不直接仿造后台接口。

## 运行

1. 在已登录的销售管理页面打开浏览器 DevTools Console。
2. 可先设置 `window.__OMS_SALES_EXPORT_CONFIG__`，再粘贴执行 `scripts/oms_sales_export.browser.js`。
3. 浏览器下载 `oms-sales-native-copy-*.json` 后运行：

```bash
node scripts/oms_sales_to_xlsx.mjs \
  --input /path/to/oms-sales-native-copy.json \
  --template "/path/to/跟单表头.xlsx" \
  --output /path/to/跟单.xlsx \
  --preview /path/to/跟单-preview.png
```

脚本会优先使用项目依赖中的 `@oai/artifact-tool`，未安装时自动使用本机 Codex 随附的稳定运行时；也可通过 `CODEX_ARTIFACT_TOOL_PATH` 显式指定 `artifact_tool.mjs`。

默认筛选与参考页面一致：

- SKU 库存可售天数不超过 7 天
- 选品状态为“已加入站点”
- 非定制品
- 非 JIT 商品
- SKU 标签为“爆旺款SKU”
- 仅展示命中 SKU

默认每页 300 条并逐页调用页面原生复制。超过 100,000 条会停止，避免误导出过大范围；可通过配置显式调整。

## 首阶段字段覆盖

销售管理页面原生导出直接提供 14 个跟单字段：卖家 ID/名称、Goods SPU ID、货品 SKC/SKU ID、今日/近 7 日/近 30 日销量、库存与仓内库存可售天数、销售库存、仓内可用库存、已发货库存、已下单待发货库存。

“是否销量突增”由公式计算：今日销量大于近 7 日日均销量的 2 倍。叶子类目、售罄损失、发货地、品质分、限流站点数等字段留空，后续从对应 OMS 页面补充。
