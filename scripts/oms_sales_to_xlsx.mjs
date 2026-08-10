#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const TARGET_HEADERS = [
  "卖家ID", "卖家名称", "Goods SPU ID", "货品SKC ID", "货品SKU ID", "叶子类目ID", "SKU属性",
  "今日销量", "近7日销量", "近30日销量", "库存可售天数", "仓内库存可售天数", "销售库存",
  "仓内可用库存", "已发货库存", "已下单待发货库存", "近7日售罄销量损失", "skc标签", "发货地",
  "是否销量突增", "售罄天数", "下单逻辑", "商品是否违规", "品质分", "限流站点数", "是否暂时无法备货",
];

const DIRECT_FIELDS = new Map([
  ["卖家ID", "卖家ID"],
  ["卖家名称", "卖家名称"],
  ["Goods SPU ID", "Goods SPU ID"],
  ["货品SKC ID", "货品SKC ID"],
  ["货品SKU ID", "货品SKU ID"],
  ["今日销量", "今日销量"],
  ["近7日销量", "近7日销量"],
  ["近30日销量", "近30日销量"],
  ["库存可售天数", "库存可售天数"],
  ["仓内库存可售天数", "仓内库存可售天数"],
  ["销售库存", "销售库存"],
  ["仓内可用库存", "仓内可用库存"],
  ["已发货库存", "已发货库存"],
  ["已下单待发货库存", "已下单待发货库存"],
]);

const TEXT_COLUMNS = new Set([
  "卖家ID", "卖家名称", "Goods SPU ID", "货品SKC ID", "货品SKU ID", "叶子类目ID", "SKU属性",
  "skc标签", "发货地", "是否销量突增", "下单逻辑", "商品是否违规", "品质分", "是否暂时无法备货",
]);

const SKC_LABEL_PRIORITY = ["大爆款", "爆款", "旺款", "平常款", "滞销款"];

function splitTsv(tsvText) {
  const lines = String(tsvText || "")
    .replace(/^\uFEFF/, "")
    .split(/\r?\n/)
    .filter((line) => line.trim() !== "");
  if (lines.length < 2) throw new Error("TSV 至少需要表头和一行数据");
  const headers = lines[0].split("\t").map((value) => value.trim());
  const rows = lines.slice(1).map((line) => {
    const values = line.split("\t");
    return Object.fromEntries(headers.map((header, index) => [header, values[index] ?? ""]));
  });
  return { headers, rows };
}

function numericOrBlank(value) {
  const normalized = String(value ?? "").replace(/,/g, "").trim();
  if (normalized === "" || normalized === "-") return "";
  const number = Number(normalized);
  return Number.isFinite(number) ? number : normalized;
}

function mergeNativePages(payload) {
  if (typeof payload === "string") return payload;
  if (!Array.isArray(payload?.pages) || payload.pages.length === 0) {
    throw new Error("原生导出 JSON 中没有 pages");
  }
  let header = "";
  const body = [];
  for (const page of payload.pages) {
    const lines = String(page.tsv || "").replace(/^\uFEFF/, "").split(/\r?\n/).filter(Boolean);
    if (lines.length === 0) continue;
    if (!header) header = lines[0];
    if (lines[0] !== header) throw new Error(`第 ${page.page ?? "?"} 页字段表头与前页不一致`);
    body.push(...lines.slice(1));
  }
  return [header, ...body].join("\n");
}

function arrayAt(value, candidates) {
  for (const candidate of candidates) {
    const parts = candidate.split(".");
    let cursor = value;
    for (const part of parts) cursor = cursor?.[part];
    if (Array.isArray(cursor)) return cursor;
  }
  return [];
}

function normalizeId(value) {
  return String(value ?? "").trim();
}

function salesApiByProductSku(payload) {
  const rows = arrayAt(payload, ["result.subOrderList", "subOrderList"]);
  const result = new Map();
  for (const order of rows) {
    for (const sku of order?.skuQuantityDetailList || []) {
      result.set(normalizeId(sku.productSkuId), { order, sku });
    }
  }
  return result;
}

function rowsById(payload, candidates, idFields) {
  const rows = arrayAt(payload, candidates);
  const result = new Map();
  for (const row of rows) {
    const id = idFields.map((field) => row?.[field]).find((value) => value !== undefined && value !== null);
    if (id !== undefined) result.set(normalizeId(id), row);
  }
  return result;
}

function leafCategoryByGoods(payload) {
  const rows = arrayAt(payload, ["rows", "result.rows"]);
  return new Map(rows.map((row) => [
    normalizeId(row.goodsId ?? row["Goods ID"] ?? row.productId),
    row.leafCategoryId ?? row["叶子类目ID"] ?? row.catId ?? "",
  ]));
}

function flowLimitByProductSku(payloads) {
  const sitesBySku = new Map();
  const explicitCountBySku = new Map();
  for (const payload of payloads) {
    for (const row of arrayAt(payload, ["rows", "result.rows"])) {
      const id = normalizeId(row.productSkuId ?? row["货品SKU ID"]);
      if (!id) continue;
      const sites = Array.isArray(row.sites) ? row.sites.filter(Boolean) : [];
      if (!sitesBySku.has(id)) sitesBySku.set(id, new Set());
      for (const site of sites) sitesBySku.get(id).add(String(site));
      if (!sites.length) {
        explicitCountBySku.set(id, (explicitCountBySku.get(id) || 0) + Number(row.limitedSiteCount || 0));
      }
    }
  }
  return new Map([...new Set([...sitesBySku.keys(), ...explicitCountBySku.keys()])].map((id) => [
    id,
    (sitesBySku.get(id)?.size || 0) + (explicitCountBySku.get(id) || 0),
  ]));
}

function preferredSkcLabel(labels) {
  const values = Array.isArray(labels) ? labels : [];
  return SKC_LABEL_PRIORITY.find((label) => values.includes(label)) || "";
}

function enrichedValue(target, source, enrichment) {
  const sellerId = normalizeId(source["卖家ID"]);
  const goodsId = normalizeId(source["Goods SPU ID"]);
  const productSkuId = normalizeId(source["货品SKU ID"]);
  const api = enrichment.salesApi.get(productSkuId);
  const soldOut = enrichment.soldOut.get(productSkuId);
  const shipping = enrichment.shipping.get(sellerId);
  const quality = enrichment.quality.get(goodsId);

  switch (target) {
    case "叶子类目ID": return enrichment.leafCategory.get(goodsId) ?? "";
    case "SKU属性": return api?.sku?.className ?? "";
    case "近7日售罄销量损失": return soldOut?.sellOutLossNum ?? "";
    case "skc标签": return preferredSkcLabel(api?.order?.skcLabels);
    case "发货地": return shipping?.province ?? shipping?.["发货地-省"] ?? "";
    case "售罄天数": return soldOut?.sellOutDays ?? "";
    case "下单逻辑": return api?.sku?.purchaseConfig ?? "";
    case "商品是否违规": return api ? (api.order?.inBlackList ? "是" : "否") : "";
    case "品质分": return quality?.score ?? quality?.qualityScore ?? quality?.["品质分"] ?? api?.order?.asfScoreLevelDesc ?? "";
    case "限流站点数": return enrichment.flowLimit.get(productSkuId) ?? "";
    case "是否暂时无法备货": return api ? (Number(api.order?.supplyStatus) === 1 ? "是" : "否") : "";
    default: return "";
  }
}

function sourceRows(enrichment) {
  return [
    ["卖家ID、卖家名称、Goods SPU/货品 SKC/货品 SKU", "销售管理（全托）", "当前页全选 → 自定义复制（Excel 用）", enrichment.nativeRows, "主键与卖家信息"],
    ["今日/7日/30日销量、库存字段", "销售管理（全托）", "当前页全选 → 自定义复制（Excel 用）", enrichment.nativeRows, "页面原生字段"],
    ["叶子类目ID", "全托货品列表", "Goods ID 批量查询 → 页面原生自定义导出", enrichment.leafCategory.size, "按 Goods SPU ID 关联"],
    ["SKU属性、SKC标签、下单逻辑、违规、暂时无法备货", "销售管理（全托）", "销售列表响应补充", enrichment.salesApiCoverage, "按货品 SKU ID 关联"],
    ["近7日售罄销量损失、售罄天数", "销售管理 → 售罄看板 → 已售罄", "全选 → 页面原生一键导出 Excel；响应用于结构化合并", enrichment.soldOut.size, "未售罄 SKU 保持空白"],
    ["发货地", "店铺查发货地", "批量查询 → 页面原生导出 Excel", enrichment.shipping.size, "按卖家 ID 关联，取省"],
    ["是否销量突增", "工作簿公式", "今日销量 > 近7日日均销量 × 2", enrichment.nativeRows, "由 H/I 列计算"],
    ["品质分", "全托品质分", "页面查询", enrichment.qualityAvailable ? enrichment.qualityCoverage : 0, enrichment.qualityAvailable ? "页面可用" : "页面报错；回退销售列表的等级描述，当前样本为“暂无”"],
    ["限流站点数", "Global / EU / UDP 限流监控", "货品 SKU 批量查询；按区域与站点去重汇总", enrichment.flowLimitCoverage, "Global、EU、UDP 三域"],
  ];
}

export async function buildSalesWorkbook({
  payload,
  templatePath,
  outputPath,
  previewPath,
  enrichments = {},
}) {
  const tsvText = mergeNativePages(payload);
  const { headers, rows } = splitTsv(tsvText);
  const missing = [...DIRECT_FIELDS.values()].filter((header) => !headers.includes(header));
  if (missing.length) throw new Error(`原生导出缺少必要字段：${missing.join("、")}`);

  const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(templatePath));
  const sheet = workbook.worksheets.getItem("Sheet1");
  const existingHeaders = (await workbook.inspect({
    kind: "table",
    sheetId: "Sheet1",
    range: "A2:Z2",
    include: "values",
    tableMaxRows: 2,
    tableMaxCols: 26,
    maxChars: 6000,
  })).ndjson;
  for (const header of TARGET_HEADERS) {
    if (!existingHeaders.includes(header)) throw new Error(`模板缺少目标字段：${header}`);
  }

  const productSkuIds = new Set(rows.map((row) => normalizeId(row["货品SKU ID"])));
  const goodsIds = new Set(rows.map((row) => normalizeId(row["Goods SPU ID"])));
  const qualityRows = rowsById(enrichments.quality || {}, ["rows", "result.rows"], ["goodsId", "Goods ID", "Goods SPU ID"]);
  const enrichment = {
    nativeRows: rows.length,
    salesApi: salesApiByProductSku(enrichments.salesApi || {}),
    leafCategory: leafCategoryByGoods(enrichments.leafCategory || {}),
    soldOut: rowsById(enrichments.soldOut || {}, ["result.soldOutDetailList", "soldOutDetailList", "rows"], ["productSkuId", "货品SKU ID"]),
    shipping: rowsById(enrichments.shipping || {}, ["rows", "result.rows"], ["sellerId", "店铺ID", "卖家ID"]),
    flowLimit: flowLimitByProductSku(enrichments.flowLimit || []),
    quality: qualityRows,
    qualityAvailable: enrichments.quality?.status !== "unavailable" && qualityRows.size > 0,
  };
  enrichment.salesApiCoverage = [...productSkuIds].filter((id) => enrichment.salesApi.has(id)).length;
  enrichment.flowLimitCoverage = [...productSkuIds].filter((id) => enrichment.flowLimit.has(id)).length;
  enrichment.qualityCoverage = [...goodsIds].filter((id) => enrichment.quality.has(id)).length;

  const values = rows.map((source) => TARGET_HEADERS.map((target) => {
    const sourceHeader = DIRECT_FIELDS.get(target);
    const value = sourceHeader ? source[sourceHeader] ?? "" : enrichedValue(target, source, enrichment);
    return TEXT_COLUMNS.has(target) ? String(value) : numericOrBlank(value);
  }));

  const firstDataRow = 3;
  const lastDataRow = firstDataRow + values.length - 1;
  // Set text formats before values so long OMS identifiers are never coerced to
  // floating-point/scientific notation during workbook import/export.
  sheet.getRange(`A${firstDataRow}:G${lastDataRow}`).format.numberFormat = "@";
  sheet.getRange(`R${firstDataRow}:Z${lastDataRow}`).format.numberFormat = "@";
  sheet.getRange(`A${firstDataRow}:Z${lastDataRow}`).values = values;
  for (const [column, sourceHeader] of [["A", "卖家ID"], ["C", "Goods SPU ID"], ["D", "货品SKC ID"], ["E", "货品SKU ID"]]) {
    sheet.getRange(`${column}${firstDataRow}:${column}${lastDataRow}`).formulas = rows.map((source) => {
      const identifier = String(source[sourceHeader] ?? "").replace(/"/g, "\"\"");
      return [identifier ? `="${identifier}"` : ""];
    });
  }
  sheet.getRange(`T${firstDataRow}`).formulas = [
    [`=IF(COUNT(H${firstDataRow}:I${firstDataRow})<2,"",IF(H${firstDataRow}>I${firstDataRow}/7*2,"是","否"))`],
  ];
  if (values.length > 1) sheet.getRange(`T${firstDataRow}:T${lastDataRow}`).fillDown();

  const body = sheet.getRange(`A${firstDataRow}:Z${lastDataRow}`);
  body.format = {
    font: { name: "微软雅黑", size: 10 },
    verticalAlignment: "center",
    borders: {
      top: { style: "continuous", color: "#D9E1F2" },
      bottom: { style: "continuous", color: "#D9E1F2" },
      left: { style: "continuous", color: "#D9E1F2" },
      right: { style: "continuous", color: "#D9E1F2" },
    },
  };
  sheet.getRange(`A${firstDataRow}:G${lastDataRow}`).format.numberFormat = "@";
  for (const column of ["A", "C", "D", "E", "F"]) {
    sheet.getRange(`${column}${firstDataRow}:${column}${lastDataRow}`).format.numberFormat = "0";
  }
  sheet.getRange(`H${firstDataRow}:J${lastDataRow}`).format.numberFormat = "#,##0";
  sheet.getRange(`K${firstDataRow}:L${lastDataRow}`).format.numberFormat = "0.0";
  sheet.getRange(`M${firstDataRow}:P${lastDataRow}`).format.numberFormat = "#,##0";
  sheet.getRange(`Q${firstDataRow}:Q${lastDataRow}`).format.numberFormat = "#,##0";
  sheet.getRange(`R${firstDataRow}:Z${lastDataRow}`).format.numberFormat = "@";
  sheet.getRange(`A${firstDataRow}:A${lastDataRow}`).format.columnWidth = 24;
  sheet.getRange(`B${firstDataRow}:B${lastDataRow}`).format.columnWidth = 22;
  sheet.getRange(`C${firstDataRow}:C${lastDataRow}`).format.columnWidth = 24;
  sheet.getRange(`D${firstDataRow}:G${lastDataRow}`).format.columnWidth = 16;
  sheet.getRange(`H${firstDataRow}:Z${lastDataRow}`).format.columnWidth = 13;
  sheet.getRange(`A2:Z2`).format.wrapText = true;
  sheet.getRange(`A2:Z2`).format.rowHeight = 34;
  sheet.freezePanes.freezeRows(2);
  sheet.freezePanes.freezeColumns(2);

  let sourceSheet;
  try {
    sourceSheet = workbook.worksheets.getItem("字段来源");
  } catch {
    sourceSheet = workbook.worksheets.add("字段来源");
  }
  const provenance = sourceRows(enrichment);
  sourceSheet.getRange("A1:E1").values = [["字段", "来源页面", "取数方式", "命中/覆盖", "说明"]];
  sourceSheet.getRange(`A2:E${provenance.length + 1}`).values = provenance;
  sourceSheet.getRange("A1:E1").format = {
    fill: "#1F4E78",
    font: { name: "微软雅黑", size: 11, bold: true, color: "#FFFFFF" },
    verticalAlignment: "center",
  };
  sourceSheet.getRange(`A2:E${provenance.length + 1}`).format = {
    font: { name: "微软雅黑", size: 10 },
    verticalAlignment: "center",
    wrapText: true,
    borders: {
      top: { style: "continuous", color: "#D9E1F2" },
      bottom: { style: "continuous", color: "#D9E1F2" },
      left: { style: "continuous", color: "#D9E1F2" },
      right: { style: "continuous", color: "#D9E1F2" },
    },
  };
  sourceSheet.getRange(`A1:A${provenance.length + 1}`).format.columnWidth = 36;
  sourceSheet.getRange(`B1:B${provenance.length + 1}`).format.columnWidth = 30;
  sourceSheet.getRange(`C1:C${provenance.length + 1}`).format.columnWidth = 48;
  sourceSheet.getRange(`D1:D${provenance.length + 1}`).format.columnWidth = 14;
  sourceSheet.getRange(`E1:E${provenance.length + 1}`).format.columnWidth = 56;
  sourceSheet.freezePanes.freezeRows(1);

  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  const output = await SpreadsheetFile.exportXlsx(workbook);
  await output.save(outputPath);

  if (previewPath) {
    await fs.mkdir(path.dirname(previewPath), { recursive: true });
    const preview = await workbook.render({
      sheetName: "Sheet1",
      range: `A1:Z${Math.min(lastDataRow, 24)}`,
      scale: 1,
      format: "png",
    });
    await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));
  }
  const sourcePreviewPath = previewPath
    ? path.join(path.dirname(previewPath), `${path.basename(previewPath, path.extname(previewPath))}-字段来源.png`)
    : "";
  if (sourcePreviewPath) {
    const sourcePreview = await workbook.render({
      sheetName: "字段来源",
      range: `A1:E${provenance.length + 1}`,
      scale: 1,
      format: "png",
    });
    await fs.writeFile(sourcePreviewPath, new Uint8Array(await sourcePreview.arrayBuffer()));
  }

  const keyRange = await workbook.inspect({
    kind: "table",
    sheetId: "Sheet1",
    range: `A1:Z${Math.min(lastDataRow, 12)}`,
    include: "values,formulas",
    tableMaxRows: 12,
    tableMaxCols: 26,
    maxChars: 16000,
  });
  const formulaErrors = await workbook.inspect({
    kind: "match",
    searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
    options: { useRegex: true, maxResults: 50 },
    summary: "公式错误扫描",
  });
  return {
    outputPath,
    previewPath,
    rowCount: values.length,
    directFieldCount: DIRECT_FIELDS.size,
    enrichedFieldCount: TARGET_HEADERS.length - DIRECT_FIELDS.size - 1,
    derivedFieldCount: 1,
    sourcePreviewPath,
    keyRange: keyRange.ndjson,
    formulaErrors: formulaErrors.ndjson,
  };
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (!key.startsWith("--")) continue;
    args[key.slice(2)] = argv[index + 1];
    index += 1;
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.input || !args.template || !args.output) {
    throw new Error("用法：node scripts/oms_sales_to_xlsx.mjs --input 原生导出.json|tsv --template 跟单表头.xlsx --output 跟单.xlsx [--enrichment 补充源清单.json] [--preview 预览.png]");
  }
  const inputText = await fs.readFile(args.input, "utf8");
  const payload = args.input.toLowerCase().endsWith(".json") ? JSON.parse(inputText) : inputText;
  let enrichments = {};
  if (args.enrichment) {
    const manifest = JSON.parse(await fs.readFile(args.enrichment, "utf8"));
    const base = path.dirname(args.enrichment);
    const readJson = async (relativePath) => relativePath
      ? JSON.parse(await fs.readFile(path.resolve(base, relativePath), "utf8"))
      : undefined;
    enrichments = {
      salesApi: await readJson(manifest.salesApi),
      leafCategory: await readJson(manifest.leafCategory),
      soldOut: await readJson(manifest.soldOut),
      shipping: await readJson(manifest.shipping),
      quality: await readJson(manifest.quality),
      flowLimit: await Promise.all((manifest.flowLimit || []).map(readJson)),
    };
  }
  const result = await buildSalesWorkbook({
    payload,
    templatePath: args.template,
    outputPath: args.output,
    previewPath: args.preview,
    enrichments,
  });
  console.log(JSON.stringify(result, null, 2));
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  main().catch((error) => {
    console.error(error.stack || String(error));
    process.exitCode = 1;
  });
}
