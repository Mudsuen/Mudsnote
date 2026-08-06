#!/usr/bin/env node

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

async function loadArtifactTool() {
  try {
    return await import("@oai/artifact-tool");
  } catch (packageError) {
    const candidates = [
      process.env.CODEX_ARTIFACT_TOOL_PATH,
      path.join(
        os.homedir(),
        ".cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs",
      ),
    ].filter(Boolean);
    for (const candidate of candidates) {
      try {
        return await import(pathToFileURL(candidate).href);
      } catch {
        // Try the next configured/local Codex runtime.
      }
    }
    throw new Error(
      `无法加载 @oai/artifact-tool。可通过 CODEX_ARTIFACT_TOOL_PATH 指向 artifact_tool.mjs。\n${packageError.message}`,
    );
  }
}

const { FileBlob, SpreadsheetFile } = await loadArtifactTool();

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
  "skc标签", "发货地", "下单逻辑", "商品是否违规", "品质分", "是否暂时无法备货",
]);

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

export async function buildSalesWorkbook({
  payload,
  templatePath,
  outputPath,
  previewPath,
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

  const values = rows.map((source) => TARGET_HEADERS.map((target) => {
    const sourceHeader = DIRECT_FIELDS.get(target);
    if (!sourceHeader) return "";
    const value = source[sourceHeader] ?? "";
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
    [`=IF(OR(H${firstDataRow}="",I${firstDataRow}=""),"",IF(H${firstDataRow}>I${firstDataRow}/7*2,"是","否"))`],
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
  sheet.getRange(`H${firstDataRow}:J${lastDataRow}`).format.numberFormat = "#,##0";
  sheet.getRange(`K${firstDataRow}:L${lastDataRow}`).format.numberFormat = "0.0";
  sheet.getRange(`M${firstDataRow}:P${lastDataRow}`).format.numberFormat = "#,##0";
  sheet.getRange(`Q${firstDataRow}:Q${lastDataRow}`).format.numberFormat = "#,##0";
  sheet.getRange(`R${firstDataRow}:Z${lastDataRow}`).format.numberFormat = "@";
  sheet.getRange(`A${firstDataRow}:A${lastDataRow}`).format.columnWidth = 20;
  sheet.getRange(`B${firstDataRow}:B${lastDataRow}`).format.columnWidth = 22;
  sheet.getRange(`C${firstDataRow}:C${lastDataRow}`).format.columnWidth = 20;
  sheet.getRange(`D${firstDataRow}:G${lastDataRow}`).format.columnWidth = 16;
  sheet.getRange(`H${firstDataRow}:Z${lastDataRow}`).format.columnWidth = 13;
  sheet.getRange(`A2:Z2`).format.wrapText = true;
  sheet.getRange(`A2:Z2`).format.rowHeight = 34;
  sheet.freezePanes.freezeRows(2);
  sheet.freezePanes.freezeColumns(2);

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
    derivedFieldCount: 1,
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
    throw new Error("用法：node scripts/oms_sales_to_xlsx.mjs --input 原生导出.json|tsv --template 跟单表头.xlsx --output 跟单.xlsx [--preview 预览.png]");
  }
  const inputText = await fs.readFile(args.input, "utf8");
  const payload = args.input.toLowerCase().endsWith(".json") ? JSON.parse(inputText) : inputText;
  const result = await buildSalesWorkbook({
    payload,
    templatePath: args.template,
    outputPath: args.output,
    previewPath: args.preview,
  });
  console.log(JSON.stringify(result, null, 2));
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  main().catch((error) => {
    console.error(error.stack || String(error));
    process.exitCode = 1;
  });
}
