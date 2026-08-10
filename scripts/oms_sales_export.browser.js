/**
 * OMS 销售管理（全托）原生导出脚本。
 *
 * 在已登录的销售管理页面 DevTools Console 中粘贴执行。脚本复用页面原生链路：
 * 查询 -> 当前页全选 -> 自定义复制所需字段（Excel用）-> 一键复制。
 *
 * 可在执行前覆盖配置：
 * window.__OMS_SALES_EXPORT_CONFIG__ = {
 *   applyFilters: true,
 *   pageSize: 300,
 *   maxPages: Infinity,
 *   maxRecords: 100000,
 *   download: true,
 * };
 */
(async () => {
  "use strict";

  const config = {
    applyFilters: true,
    pageSize: 300,
    maxPages: Number.POSITIVE_INFINITY,
    maxRecords: 100000,
    download: true,
    ...(window.__OMS_SALES_EXPORT_CONFIG__ || {}),
  };

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const normalize = (value) => String(value || "").replace(/\s+/g, "").trim();
  const visible = (element) => {
    if (!element) return false;
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.display !== "none" && style.visibility !== "hidden";
  };
  const textOf = (element) => normalize(element?.innerText || element?.textContent);

  async function waitFor(predicate, message, timeoutMs = 15000) {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      const value = await predicate();
      if (value) return value;
      await sleep(150);
    }
    throw new Error(message);
  }

  function click(element) {
    if (!element) throw new Error("找不到要点击的元素");
    element.scrollIntoView({ block: "center", inline: "center" });
    for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
      element.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
    }
  }

  function setInputValue(input, value) {
    const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value");
    descriptor.set.call(input, String(value));
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
    input.dispatchEvent(new Event("blur", { bubbles: true }));
  }

  function rowByLabel(label) {
    return [...document.querySelectorAll("div")].find((element) => {
      if (!visible(element) || textOf(element) !== normalize(label)) return false;
      const row = element.closest("div[class*='row___']");
      return row && visible(row);
    })?.closest("div[class*='row___']");
  }

  async function chooseOption(label, optionText) {
    const row = rowByLabel(label);
    if (!row) throw new Error(`找不到筛选项：${label}`);
    if (textOf(row).includes(normalize(optionText))) return;
    const trigger = [...row.querySelectorAll("input,[role='combobox']")].find(visible);
    if (!trigger) throw new Error(`找不到筛选框：${label}`);
    click(trigger);
    const option = await waitFor(
      () => [...document.querySelectorAll("[role='option'],li,div")].find(
        (element) => visible(element) && textOf(element) === normalize(optionText),
      ),
      `找不到选项：${label} = ${optionText}`,
    );
    click(option);
    await sleep(200);
  }

  function setRangeUpper(label, upper) {
    const row = rowByLabel(label);
    if (!row) throw new Error(`找不到范围筛选项：${label}`);
    const inputs = [...row.querySelectorAll("input")].filter(visible);
    if (inputs.length < 2) throw new Error(`范围筛选项输入框不足：${label}`);
    setInputValue(inputs[0], "");
    setInputValue(inputs[1], upper);
  }

  function setNamedSwitch(label, enabled) {
    const labelNode = [...document.querySelectorAll("span,div,label")].find(
      (element) => visible(element) && textOf(element) === normalize(label),
    );
    const container = labelNode?.parentElement;
    const control = container?.querySelector("[role='switch'],[data-testid='beast-core-switch'],input[type='checkbox']")
      || labelNode?.closest("label")?.querySelector("input[type='checkbox']");
    if (!control) throw new Error(`找不到开关：${label}`);
    const checked = control.matches?.(":checked")
      || control.getAttribute("aria-checked") === "true"
      || /checked|active/i.test(control.className);
    if (checked !== enabled) click(control);
  }

  async function waitForLoadingToFinish() {
    await sleep(300);
    await waitFor(
      () => ![...document.querySelectorAll("[class*='loading'],[class*='spin']")].some(visible),
      "页面查询等待超时",
      30000,
    );
  }

  function parseTotal() {
    const match = document.body.innerText.match(/SKC数[：:]\s*([\d,]+)/);
    return match ? Number(match[1].replace(/,/g, "")) : NaN;
  }

  async function applyRequestedFilters() {
    setRangeUpper("SKU库存可售天数", 7);
    await chooseOption("选品状态", "已加入站点");
    await chooseOption("是否定制商品", "非定制品");
    await chooseOption("是否JIT商品", "否");
    await chooseOption("SKU标签", "爆旺款SKU");
    setNamedSwitch("仅展示命中SKU", true);
    const queryButton = [...document.querySelectorAll("button")].find(
      (element) => visible(element) && textOf(element) === "查询",
    );
    click(queryButton);
    await waitForLoadingToFinish();
  }

  async function setPageSize(pageSize) {
    const pagination = [...document.querySelectorAll("[class*='pagination'],[class*='Pagination']")]
      .filter(visible)
      .at(-1);
    if (!pagination) throw new Error("找不到分页器");
    const trigger = [...pagination.querySelectorAll("input,[role='combobox'],button")].find(
      (element) => /条页|page/i.test(element.getAttribute("aria-label") || element.value || textOf(element)),
    ) || [...pagination.querySelectorAll("input,[role='combobox']")].find(visible);
    if (!trigger) throw new Error("找不到每页条数选择器");
    click(trigger);
    const option = await waitFor(
      () => [...document.querySelectorAll("[role='option'],li")].find(
        (element) => visible(element) && new RegExp(`^${pageSize}(条/页)?$`).test(textOf(element)),
      ),
      `页面不支持每页 ${pageSize} 条`,
    );
    click(option);
    await waitForLoadingToFinish();
  }

  function headerCheckbox() {
    return [...document.querySelectorAll("thead input[type='checkbox'],thead [role='checkbox']")]
      .find(visible)
      || [...document.querySelectorAll("thead [data-testid*='checkbox']")].find(visible);
  }

  function ensureCurrentPageSelected() {
    const checkbox = headerCheckbox();
    if (!checkbox) throw new Error("找不到表头全选框");
    const checked = checkbox.matches?.(":checked")
      || checkbox.getAttribute("aria-checked") === "true"
      || checkbox.closest("[aria-checked='true']");
    if (!checked) click(checkbox);
  }

  async function openNativeCopyDialog() {
    const input = [...document.querySelectorAll("input")].find(
      (element) => visible(element) && /一键复制所选ID/.test(element.value || element.placeholder || ""),
    );
    if (!input) throw new Error("找不到页面原生“一键复制所选ID”入口");
    click(input);
    const option = await waitFor(
      () => [...document.querySelectorAll("li[role='option'],[role='option']")].find(
        (element) => visible(element) && /自定义复制所需(字段|内容)/.test(textOf(element)),
      ),
      "找不到“自定义复制所需字段/内容”",
    );
    click(option);
    await waitFor(
      () => document.querySelector(".body-module__modal___31SJ0")
        || [...document.querySelectorAll("[role='dialog'],div[class*='modal'],div[class*='Modal']")]
          .find((element) => visible(element) && /一键复制/.test(textOf(element))),
      "自定义字段弹窗未打开",
    );
  }

  function selectAllNativeFields() {
    const dialog = document.querySelector(".body-module__modal___31SJ0")
      || [...document.querySelectorAll("[role='dialog'],div[class*='modal'],div[class*='Modal']")]
      .filter(visible)
      .at(-1) || document.body;
    const labels = [...dialog.querySelectorAll("label[data-testid='beast-core-checkbox']")].filter(visible);
    for (const label of labels) {
      if (label.getAttribute("data-checked") === "false") {
        click(label.querySelector("[data-testid='beast-core-checkbox-checkIcon']") || label);
      }
    }
  }

  async function captureNativeCopy() {
    let captured = "";
    const originalWriteText = navigator.clipboard?.writeText?.bind(navigator.clipboard);
    const originalExecCommand = document.execCommand.bind(document);
    const onCopy = (event) => {
      captured = event.clipboardData?.getData("text/plain") || captured;
    };
    document.addEventListener("copy", onCopy, true);
    if (navigator.clipboard) {
      navigator.clipboard.writeText = async (text) => {
        captured = String(text);
      };
    }
    document.execCommand = (command, ...args) => {
      if (String(command).toLowerCase() === "copy") {
        const selection = String(getSelection() || "");
        if (selection) captured = selection;
        return true;
      }
      return originalExecCommand(command, ...args);
    };

    try {
      const dialog = document.querySelector(".body-module__modal___31SJ0") || document.body;
      const copyButton = [...dialog.querySelectorAll("button")].find(
        (element) => visible(element) && /一键复制/.test(textOf(element)),
      );
      click(copyButton);
      return await waitFor(() => captured, "未捕获到页面原生复制数据");
    } finally {
      document.removeEventListener("copy", onCopy, true);
      document.execCommand = originalExecCommand;
      if (navigator.clipboard && originalWriteText) navigator.clipboard.writeText = originalWriteText;
    }
  }

  function nextPageButton() {
    return [...document.querySelectorAll("button")].find((element) => {
      if (!visible(element) || element.disabled) return false;
      const label = element.getAttribute("aria-label") || element.title || textOf(element);
      return /next|下一页|right/i.test(label);
    });
  }

  async function closeCopyDialog() {
    const close = [...document.querySelectorAll("button,[aria-label]")].find((element) => {
      if (!visible(element)) return false;
      const label = element.getAttribute("aria-label") || element.title || textOf(element);
      return /取消|关闭|close/i.test(label);
    });
    if (close) click(close);
    await sleep(150);
  }

  function downloadJson(payload) {
    const blob = new Blob([JSON.stringify(payload)], { type: "application/json;charset=utf-8" });
    const anchor = document.createElement("a");
    anchor.href = URL.createObjectURL(blob);
    anchor.download = `oms-sales-native-copy-${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(anchor.href), 1000);
  }

  if (!location.pathname.includes("/app/stock/fully-mgt/manage/skc")) {
    throw new Error("请先打开 OMS 销售管理（全托）页面");
  }
  if (config.applyFilters) await applyRequestedFilters();

  const totalRecords = parseTotal();
  if (!Number.isFinite(totalRecords)) throw new Error("无法读取 SKC 总数");
  if (totalRecords > config.maxRecords) {
    throw new Error(`命中 ${totalRecords} 条，超过安全上限 ${config.maxRecords}，请缩小筛选范围`);
  }

  await setPageSize(config.pageSize);
  const totalPages = Math.ceil(totalRecords / config.pageSize);
  const pagesToExport = Math.min(totalPages, config.maxPages);
  const pages = [];
  for (let page = 1; page <= pagesToExport; page += 1) {
    ensureCurrentPageSelected();
    await openNativeCopyDialog();
    selectAllNativeFields();
    const tsv = await captureNativeCopy();
    pages.push({ page, tsv });
    await closeCopyDialog();
    if (page < pagesToExport) {
      const next = nextPageButton();
      if (!next) throw new Error(`第 ${page} 页后找不到下一页`);
      click(next);
      await waitForLoadingToFinish();
    }
  }

  const result = {
    source: "OMS 销售管理（全托）/ 页面原生一键复制",
    url: location.href,
    exportedAt: new Date().toISOString(),
    filters: config.applyFilters ? {
      "SKU库存可售天数": "<= 7",
      "选品状态": "已加入站点",
      "是否定制商品": "非定制品",
      "是否JIT商品": "否",
      "SKU标签": "爆旺款SKU",
      "仅展示命中SKU": true,
    } : null,
    totalRecords,
    pageSize: config.pageSize,
    exportedPages: pages.length,
    pages,
  };
  if (config.download) downloadJson(result);
  console.info("OMS 销售管理原生导出完成", {
    totalRecords,
    exportedPages: pages.length,
    pageSize: config.pageSize,
  });
  return result;
})();
