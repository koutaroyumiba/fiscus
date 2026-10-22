"use strict";

const DEMO_JOURNAL = `# Sample journal for the Fiscus web viewer
meta version 1
meta journal "Everyday Ledger"

account asset:bank:harbour:everyday commodity AUD
account asset:bank:harbour:savings commodity AUD
account liability:credit-card:harbour commodity AUD
account equity:opening-balances commodity AUD
account income:employment:studio:salary commodity AUD
account income:freelance:design commodity AUD
account income:interest commodity AUD
account expense:housing:rent commodity AUD
account expense:food:groceries commodity AUD
account expense:food:dining commodity AUD
account expense:transport:public commodity AUD
account expense:utilities:energy commodity AUD
account expense:subscriptions:software commodity AUD
account expense:travel:weekend commodity AUD

txn 2025-09-01 "Opening balances" {
  + asset:bank:harbour:everyday 4280.00
  + asset:bank:harbour:savings 18400.00
  - liability:credit-card:harbour 620.00
  - equity:opening-balances 22060.00
}
txn 2025-09-05 "September salary" {
  id salary-2025-09
  tag income:salary
  + asset:bank:harbour:everyday 4850.00
  - income:employment:studio:salary 4850.00
}
txn 2025-09-07 "Sunday market" {
  tag food
  tag shared
  note "Fruit, vegetables and pantry staples"
  + expense:food:groceries 138.45
  - liability:credit-card:harbour 138.45
}
txn 2025-09-12 "Apartment rent" {
  tag housing
  + expense:housing:rent 2150.00
  - asset:bank:harbour:everyday 2150.00
}
txn 2025-09-18 "Train card" {
  tag transport
  + expense:transport:public 52.00
  - asset:bank:harbour:everyday 52.00
}
txn 2025-10-05 "October salary" {
  id salary-2025-10
  tag income:salary
  + asset:bank:harbour:everyday 4850.00
  - income:employment:studio:salary 4850.00
}
txn 2025-10-09 "Energy bill" {
  tag utilities
  + expense:utilities:energy 164.20
  - asset:bank:harbour:everyday 164.20
}
txn 2025-10-12 "Apartment rent" {
  tag housing
  + expense:housing:rent 2150.00
  - asset:bank:harbour:everyday 2150.00
}
txn 2025-10-19 "Dinner with Mae" {
  tag food
  tag social
  + expense:food:dining 96.80
  - liability:credit-card:harbour 96.80
}
txn 2025-10-24 "Freelance identity project" {
  id freelance-aurora
  tag income:freelance
  + asset:bank:harbour:everyday 1200.00
  - income:freelance:design 1200.00
}
txn 2025-11-05 "November salary" {
  tag income:salary
  + asset:bank:harbour:everyday 4850.00
  - income:employment:studio:salary 4850.00
}
txn 2025-11-08 "Groceries" {
  tag food
  + expense:food:groceries 172.36
  - liability:credit-card:harbour 172.36
}
txn 2025-11-12 "Apartment rent" {
  tag housing
  + expense:housing:rent 2150.00
  - asset:bank:harbour:everyday 2150.00
}
txn 2025-11-16 "Design software" {
  tag work
  tag subscriptions
  + expense:subscriptions:software 42.00
  - liability:credit-card:harbour 42.00
}
txn 2025-11-25 "Transfer to savings" {
  tag savings
  + asset:bank:harbour:savings 900.00
  - asset:bank:harbour:everyday 900.00
}
txn 2025-12-05 "December salary" {
  tag income:salary
  + asset:bank:harbour:everyday 4850.00
  - income:employment:studio:salary 4850.00
}
txn 2025-12-12 "Apartment rent" {
  tag housing
  + expense:housing:rent 2150.00
  - asset:bank:harbour:everyday 2150.00
}
txn 2025-12-19 "Coastal weekend" {
  tag travel
  tag shared
  + expense:travel:weekend 684.50
  - liability:credit-card:harbour 684.50
}
txn 2025-12-31 "Savings interest" {
  tag income:interest
  + asset:bank:harbour:savings 68.21
  - income:interest 68.21
}
txn 2026-01-05 "January salary" {
  tag income:salary
  + asset:bank:harbour:everyday 4950.00
  - income:employment:studio:salary 4950.00
}
txn 2026-01-09 "Groceries" {
  tag food
  tag shared
  + expense:food:groceries 147.92
  - liability:credit-card:harbour 147.92
}
txn 2026-01-12 "Apartment rent" {
  tag housing
  + expense:housing:rent 2150.00
  - asset:bank:harbour:everyday 2150.00
}
txn 2026-01-17 "Dinner at Alba" {
  tag food
  tag social
  note "Birthday dinner"
  + expense:food:dining 132.40
  - liability:credit-card:harbour 132.40
}
txn 2026-01-22 "Credit card payment" {
  + liability:credit-card:harbour 1100.00
  - asset:bank:harbour:everyday 1100.00
}
txn 2026-02-05 "February salary" {
  tag income:salary
  + asset:bank:harbour:everyday 4950.00
  - income:employment:studio:salary 4950.00
}
txn 2026-02-11 "February groceries" {
  tag food
  + expense:food:groceries 158.74
  - liability:credit-card:harbour 158.74
}
txn 2026-02-12 "Apartment rent" {
  tag housing
  + expense:housing:rent 2150.00
  - asset:bank:harbour:everyday 2150.00
}`;

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const state = { journal: null, view: "overview", account: "", tag: "", commodity: "", search: "" };
const colors = ["#2d7455", "#eb765d", "#e7c866", "#78aeb1", "#8a7355", "#9eb66c", "#c08b78"];

function tokenize(source, filename) {
  const tokens = [];
  let i = 0, line = 1;
  while (i < source.length) {
    const char = source[i];
    if (/\s/.test(char)) { if (char === "\n") line++; i++; continue; }
    if (char === "#") { while (i < source.length && source[i] !== "\n") i++; continue; }
    if (char === "{" || char === "}") { tokens.push({ value: char, type: "brace", line, filename }); i++; continue; }
    if (char === '"') {
      const startLine = line;
      i++;
      let value = "";
      while (i < source.length && source[i] !== '"') {
        if (source[i] === "\n" || source[i] === "\r") throw new Error(`${filename}:${startLine} — strings cannot contain newlines`);
        value += source[i++];
      }
      if (i >= source.length) throw new Error(`${filename}:${startLine} — unterminated string`);
      i++;
      tokens.push({ value, type: "string", line: startLine, filename });
      continue;
    }
    const start = i;
    while (i < source.length && !/[\s{}"#]/.test(source[i])) i++;
    tokens.push({ value: source.slice(start, i), type: "word", line, filename });
  }
  return tokens;
}

function parseDocument(source, filename = "journal.fiscus") {
  const tokens = tokenize(source, filename);
  let cursor = 0;
  const peek = () => tokens[cursor];
  const take = (expected, type) => {
    const token = tokens[cursor++];
    if (!token || (expected && token.value !== expected) || (type && token.type !== type)) {
      const found = token ? `“${token.value}”` : "end of file";
      const location = token ? `${filename}:${token.line}` : filename;
      throw new Error(`${location} — expected ${expected || type}, found ${found}`);
    }
    return token;
  };

  take("meta"); take("version");
  const version = take(null, "word").value;
  take("meta"); take("journal");
  const name = take(null, "string").value;
  if (version !== "1") throw new Error(`${filename} — unsupported Fiscus version ${version}`);

  const document = { name, version, accounts: [], commodities: [], transactions: [], sources: [], filename };
  while (peek()) {
    const keyword = peek().value;
    if (keyword === "source") {
      take("source");
      document.sources.push({ role: take(null, "word").value, path: take(null, "string").value });
    } else if (keyword === "commodity") {
      take("commodity");
      const commodity = { symbol: take(null, "word").value, kind: take(null, "word").value };
      take("scale"); commodity.scale = Number(take(null, "word").value);
      if (peek()?.type === "string") commodity.name = take(null, "string").value;
      document.commodities.push(commodity);
    } else if (keyword === "account") {
      take("account");
      const account = { name: take(null, "word").value, commodity: null };
      if (peek()?.value === "commodity") { take("commodity"); account.commodity = take(null, "word").value; }
      document.accounts.push(account);
    } else if (keyword === "txn" || keyword === "transaction") {
      const start = take().line;
      const transaction = { date: take(null, "word").value, narration: "Untitled transaction", id: null, note: "", tags: [], postings: [], filename, line: start };
      if (peek()?.type === "string") transaction.narration = take(null, "string").value;
      take("{");
      while (peek() && peek().value !== "}") {
        const token = peek().value;
        if (token === "id") { take("id"); transaction.id = take(null, "word").value; }
        else if (token === "note") { take("note"); transaction.note = take(null, "string").value; }
        else if (token === "tag") { take("tag"); transaction.tags.push(take(null, "word").value); }
        else if (["+", "-", "debit", "credit"].includes(token)) {
          const direction = ["+", "debit"].includes(take().value) ? "debit" : "credit";
          const account = take(null, "word").value;
          const amountToken = take(null, "word");
          const amount = Number(amountToken.value);
          if (!Number.isFinite(amount) || amount <= 0) throw new Error(`${filename}:${amountToken.line} — invalid posting amount “${amountToken.value}”`);
          let commodity = null, valuation = null;
          if (peek() && !["@@", "+", "-", "debit", "credit", "}"].includes(peek().value)) commodity = take(null, "word").value;
          if (peek()?.value === "@@") { take("@@"); valuation = { amount: Number(take(null, "word").value), commodity: take(null, "word").value }; }
          transaction.postings.push({ direction, account, amount, commodity, valuation });
        } else {
          throw new Error(`${filename}:${peek().line} — unexpected token “${peek().value}” in transaction`);
        }
      }
      take("}");
      if (transaction.postings.length < 2) throw new Error(`${filename}:${start} — a transaction needs at least two postings`);
      document.transactions.push(transaction);
    } else {
      throw new Error(`${filename}:${peek().line} — unexpected token “${peek().value}”`);
    }
  }
  return document;
}

function combineDocuments(documents) {
  if (!documents.length) throw new Error("No Fiscus files were selected.");
  const name = documents[0].name;
  if (documents.some(doc => doc.name !== name)) throw new Error("All files must use the same journal name.");
  const accounts = [...new Map(documents.flatMap(doc => doc.accounts).map(account => [account.name, account])).values()];
  const accountMap = new Map(accounts.map(account => [account.name, account]));
  const transactions = documents.flatMap(doc => doc.transactions);
  const warnings = [];
  if (documents.length === 1 && documents[0].sources.length) {
    warnings.push("This journal references source files; select those .fiscus files together to include their data");
  }
  transactions.forEach(transaction => transaction.postings.forEach(posting => {
    if (!accountMap.has(posting.account)) warnings.push(`Undeclared account: ${posting.account}`);
    posting.commodity ||= accountMap.get(posting.account)?.commodity;
    if (!posting.commodity) warnings.push(`Missing commodity for ${posting.account} (${transaction.date})`);
  }));
  const declared = documents.flatMap(doc => doc.commodities);
  const commoditySymbols = new Set(declared.map(item => item.symbol));
  transactions.forEach(transaction => transaction.postings.forEach(posting => { if (posting.commodity) commoditySymbols.add(posting.commodity); }));
  if (!commoditySymbols.size) commoditySymbols.add("AUD");
  return {
    name, accounts, transactions: transactions.sort((a, b) => b.date.localeCompare(a.date)),
    commodities: [...commoditySymbols].sort(), warnings: [...new Set(warnings)]
  };
}

async function filesFromEntry(entry) {
  if (!entry || entry.name.startsWith(".")) return [];
  if (entry.isFile) {
    const file = await new Promise((resolve, reject) => entry.file(resolve, reject));
    return [{ file, path: entry.fullPath.replace(/^\//, "") }];
  }
  if (!entry.isDirectory) return [];

  const reader = entry.createReader();
  const children = [];
  while (true) {
    const batch = await new Promise((resolve, reject) => reader.readEntries(resolve, reject));
    if (!batch.length) break;
    children.push(...batch);
  }
  return (await Promise.all(children.map(filesFromEntry))).flat();
}

async function filesFromDrop(dataTransfer) {
  const entries = [...(dataTransfer.items || [])]
    .map(item => item.webkitGetAsEntry?.())
    .filter(Boolean);
  if (entries.length) return (await Promise.all(entries.map(filesFromEntry))).flat();
  return [...dataTransfer.files].map(file => ({ file, path: file.name }));
}

async function openFiles(files) {
  const selected = [...files]
    .map(item => item.file ? item : { file: item, path: item.webkitRelativePath || item.name })
    .filter(item => item.file.name.toLowerCase().endsWith(".fiscus"))
    .sort((a, b) => a.path.localeCompare(b.path));
  if (!selected.length) return showToast("That folder does not contain any .fiscus files");
  try {
    const documents = await Promise.all(selected.map(async item => parseDocument(await item.file.text(), item.path)));
    loadJournal(combineDocuments(documents));
    showToast(`Opened ${selected.length} Fiscus file${selected.length === 1 ? "" : "s"}`);
  } catch (error) { showToast(error.message, 6500); }
}

function loadJournal(journal) {
  state.journal = journal;
  state.view = "overview"; state.account = ""; state.tag = ""; state.search = "";
  state.commodity = journal.commodities.includes("AUD") ? "AUD" : journal.commodities[0] || "AUD";
  $("#welcome").hidden = true; $("#dashboard").hidden = false;
  $("#journal-name").textContent = journal.name;
  $("#transaction-count").textContent = journal.transactions.length;
  $("#search-input").value = "";
  populateFilters();
  render();
  window.scrollTo(0, 0);
}

function populateFilters() {
  const accountNames = state.journal.accounts.map(item => item.name).sort();
  const declaredAccounts = new Set(accountNames);
  const prefixes = new Set();
  accountNames.forEach(name => {
    const parts = name.split(":");
    for (let length = 1; length <= parts.length; length++) prefixes.add(parts.slice(0, length).join(":"));
  });
  const accountOptions = [...prefixes].sort().map(prefix => {
    const depth = prefix.split(":").length - 1;
    const hasDescendants = accountNames.some(name => name.startsWith(`${prefix}:`));
    const kind = hasDescendants ? " (prefix)" : declaredAccounts.has(prefix) ? "" : " (group)";
    const indent = "&nbsp;&nbsp;".repeat(depth);
    return `<option value="${escapeHtml(prefix)}">${indent}${escapeHtml(prefix)}${kind}</option>`;
  }).join("");
  $("#account-filter").innerHTML = `<option value="">All accounts</option>${accountOptions}`;
  const tags = [...new Set(state.journal.transactions.flatMap(txn => txn.tags))].sort();
  $("#tag-chips").innerHTML = `<button class="tag-chip active" data-tag="" type="button">All</button>${tags.map(tag => `<button class="tag-chip" data-tag="${escapeHtml(tag)}" type="button">#${escapeHtml(tag)}</button>`).join("")}`;
  $("#commodity-filter").innerHTML = state.journal.commodities.map(symbol => `<option value="${escapeHtml(symbol)}">${escapeHtml(symbol)}</option>`).join("");
  $("#commodity-filter").value = state.commodity;
}

function accountMatchesFilter(account) {
  return !state.account || account === state.account || account.startsWith(`${state.account}:`);
}

function filteredTransactions() {
  const query = state.search.trim().toLowerCase();
  return state.journal.transactions.filter(txn => {
    const accountMatch = txn.postings.some(posting => accountMatchesFilter(posting.account));
    const tagMatch = !state.tag || txn.tags.includes(state.tag);
    const haystack = [txn.narration, txn.note, txn.id, txn.date, ...txn.tags, ...txn.postings.map(posting => posting.account)].filter(Boolean).join(" ").toLowerCase();
    return accountMatch && tagMatch && (!query || haystack.includes(query));
  });
}

function relevantPostings(transaction) {
  return transaction.postings.filter(posting => accountMatchesFilter(posting.account) && posting.commodity === state.commodity);
}

function accountType(account) { return account.split(":")[0]; }
function naturalAmount(posting) {
  const debitNatural = ["asset", "expense"].includes(accountType(posting.account));
  return posting.amount * ((posting.direction === "debit") === debitNatural ? 1 : -1);
}
function reportData(transactions = filteredTransactions()) {
  const totals = { asset: 0, liability: 0, equity: 0, income: 0, expense: 0 };
  const byAccount = new Map();
  transactions.forEach(txn => relevantPostings(txn).forEach(posting => {
    const amount = naturalAmount(posting);
    const type = accountType(posting.account);
    totals[type] = (totals[type] || 0) + amount;
    byAccount.set(posting.account, (byAccount.get(posting.account) || 0) + amount);
  }));
  return { totals, byAccount };
}
function formatMoney(amount, compact = false) {
  const commodity = state.commodity;
  const options = { minimumFractionDigits: compact ? 0 : 2, maximumFractionDigits: compact ? 1 : 2, ...(compact ? { notation: "compact" } : {}) };
  if (["AUD", "NZD", "USD", "JPY", "EUR", "GBP"].includes(commodity)) {
    return new Intl.NumberFormat("en", { style: "currency", currency: commodity, currencyDisplay: "narrowSymbol", ...options }).format(amount);
  }
  return `${new Intl.NumberFormat("en", options).format(amount)} ${commodity}`;
}
function escapeHtml(value = "") { return String(value).replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[char])); }
function friendlyAccount(name) { return name.split(":").slice(1).map(part => part.replace(/[-_]/g, " ")).join(" / "); }
function formatDate(date) { const parsed = new Date(`${date}T00:00:00`); return Number.isNaN(parsed.getTime()) ? date : parsed.toLocaleDateString("en-AU", { day: "2-digit", month: "short", year: "numeric" }); }

function render() {
  const titles = { overview: "Overview", transactions: "Transactions", accounts: "Accounts", reports: "Reports" };
  $("#view-title").textContent = titles[state.view];
  $$(".nav-item").forEach(button => button.classList.toggle("active", button.dataset.view === state.view));
  const notice = $("#notice");
  if (state.journal.warnings.length) { notice.hidden = false; notice.textContent = `${state.journal.warnings.length} parsing note${state.journal.warnings.length === 1 ? "" : "s"}: ${state.journal.warnings.slice(0, 2).join(" · ")}`; }
  else notice.hidden = true;
  if (state.view === "overview") renderOverview();
  if (state.view === "transactions") renderTransactions();
  if (state.view === "accounts") renderAccounts();
  if (state.view === "reports") renderReports();
}

function metricsHtml(data, transactionCount) {
  const net = data.totals.asset - data.totals.liability;
  const flow = data.totals.income - data.totals.expense;
  return `<div class="metric-grid">
    ${metric("Net position", net, "Assets less liabilities")}
    ${metric("Income", data.totals.income, "Filtered period", "#2d7455")}
    ${metric("Expenses", data.totals.expense, "Filtered period", "#eb765d")}
    ${metric("Net cash flow", flow, `${transactionCount} visible transactions`, "#e7c866")}
  </div>`;
}
function metric(label, value, foot, dot) {
  return `<article class="metric"><div class="metric-label"><span>${label}</span><i style="background:${dot || "#2d7455"}"></i></div><div class="metric-value ${value < 0 ? "negative" : ""}">${formatMoney(value)}</div><div class="metric-foot">${foot} · ${state.commodity}</div></article>`;
}

function renderOverview() {
  const transactions = filteredTransactions();
  const data = reportData(transactions);
  $("#content").innerHTML = `${metricsHtml(data, transactions.length)}
    <div class="dashboard-grid">
      <section class="card"><div class="card-head"><div><h3>Money in & out</h3><span>Monthly activity · ${state.commodity}</span></div><div class="chart-legend"><span><i style="background:#2d7455"></i>Income</span><span><i style="background:#eb765d"></i>Expenses</span></div></div><div class="chart-wrap">${lineChart(transactions)}</div></section>
      <section class="card"><div class="card-head"><div><h3>Expense map</h3><span>By category</span></div></div>${breakdownHtml(data.byAccount)}</section>
    </div>
    <section class="card table-card"><div class="card-head"><div><h3>Recent transactions</h3><span>${transactions.length} matching entries</span></div><button class="view-all" data-go="transactions" type="button">View all →</button></div>${transactionTable(transactions.slice(0, 7))}</section>`;
  $("[data-go='transactions']")?.addEventListener("click", () => { state.view = "transactions"; render(); });
}

function monthlyData(transactions) {
  const months = new Map();
  transactions.forEach(txn => {
    const month = txn.date.slice(0, 7);
    if (!months.has(month)) months.set(month, { income: 0, expense: 0 });
    relevantPostings(txn).forEach(posting => {
      const type = accountType(posting.account);
      if (type === "income" || type === "expense") months.get(month)[type] += naturalAmount(posting);
    });
  });
  return [...months.entries()].sort(([a], [b]) => a.localeCompare(b)).slice(-8);
}
function lineChart(transactions) {
  const data = monthlyData(transactions);
  if (!data.length) return `<div class="empty">No income or expense activity for this view.</div>`;
  const width = 640, height = 200, padX = 35, padY = 20;
  const max = Math.max(1, ...data.flatMap(([, item]) => [item.income, item.expense]));
  const x = index => data.length === 1 ? width / 2 : padX + index * (width - padX * 2) / (data.length - 1);
  const y = value => height - padY - value / max * (height - padY * 2);
  const points = key => data.map(([, item], index) => `${x(index)},${y(item[key])}`).join(" ");
  const grid = [0, .25, .5, .75, 1].map(ratio => `<line class="chart-grid" x1="${padX}" y1="${y(max * ratio)}" x2="${width - padX}" y2="${y(max * ratio)}"/>`).join("");
  const labels = data.map(([month], index) => `<text class="chart-label" x="${x(index)}" y="198" text-anchor="middle">${new Date(month + "-02").toLocaleDateString("en", { month: "short" })}</text>`).join("");
  const dots = key => data.map(([, item], index) => `<circle class="chart-dot" cx="${x(index)}" cy="${y(item[key])}" r="3" fill="${key === "income" ? "#2d7455" : "#eb765d"}"/>`).join("");
  return `<svg class="chart" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" role="img" aria-label="Monthly income and expenses chart"><defs><linearGradient id="areaFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9bc4a8"/><stop offset="1" stop-color="#9bc4a8" stop-opacity="0"/></linearGradient></defs>${grid}<polyline class="chart-income" points="${points("income")}"/><polyline class="chart-expense" points="${points("expense")}"/>${dots("income")}${dots("expense")}${labels}</svg>`;
}
function expenseAccounts(byAccount) {
  return [...byAccount].filter(([name, value]) => accountType(name) === "expense" && value > 0).sort((a, b) => b[1] - a[1]);
}
function breakdownHtml(byAccount) {
  const expenses = expenseAccounts(byAccount).slice(0, 6);
  const max = expenses[0]?.[1] || 1;
  if (!expenses.length) return `<div class="empty">No expenses in this selection.</div>`;
  return `<div class="breakdown">${expenses.map(([name, amount], index) => `<div class="breakdown-row"><div class="breakdown-label"><i style="background:${colors[index % colors.length]}"></i>${escapeHtml(friendlyAccount(name))}</div><div class="breakdown-amount">${formatMoney(amount)}</div><div class="breakdown-bar"><i style="width:${amount / max * 100}%;background:${colors[index % colors.length]}"></i></div></div>`).join("")}</div>`;
}

function transactionTable(transactions) {
  if (!transactions.length) return `<div class="empty">No transactions match these filters.</div>`;
  return `<div class="table-wrap"><table><thead><tr><th>Date</th><th>Transaction</th><th>Postings</th><th>Tags</th></tr></thead><tbody>${transactions.map(txn => `<tr>
    <td class="date-cell">${escapeHtml(formatDate(txn.date))}</td>
    <td><div class="transaction-title">${escapeHtml(txn.narration)}</div>${txn.note ? `<div class="transaction-note">${escapeHtml(txn.note)}</div>` : ""}${txn.id ? `<div class="transaction-note">ID · ${escapeHtml(txn.id)}</div>` : ""}</td>
    <td class="posting-list">${txn.postings.map(posting => `<div class="posting ${posting.direction}"><span>${escapeHtml(friendlyAccount(posting.account))}</span><strong>${escapeHtml(formatPosting(posting))}</strong></div>`).join("")}</td>
    <td class="tags-cell">${txn.tags.map(tag => `<span class="mini-tag">#${escapeHtml(tag)}</span>`).join("") || "—"}</td>
  </tr>`).join("")}</tbody></table></div>`;
}
function formatPosting(posting) {
  const amount = new Intl.NumberFormat("en", { minimumFractionDigits: 2, maximumFractionDigits: 8 }).format(posting.amount);
  return `${amount} ${posting.commodity || "?"}${posting.valuation ? ` @ ${posting.valuation.amount} ${posting.valuation.commodity}` : ""}`;
}
function renderTransactions() {
  const transactions = filteredTransactions();
  $("#content").innerHTML = `<div class="section-head"><div><h2>Journal activity</h2><p>Every matching entry, newest first.</p></div><small>${transactions.length} OF ${state.journal.transactions.length} TRANSACTIONS</small></div><section class="card">${transactionTable(transactions)}</section>`;
}

function allAccountBalances() {
  const transactions = filteredTransactions();
  const values = new Map(state.journal.accounts.map(account => [account.name, 0]));
  transactions.forEach(txn => txn.postings.forEach(posting => {
    if (posting.commodity !== state.commodity || !accountMatchesFilter(posting.account)) return;
    values.set(posting.account, (values.get(posting.account) || 0) + naturalAmount(posting));
  }));
  return [...values].filter(([name]) => accountMatchesFilter(name)).sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]));
}
function renderAccounts() {
  const balances = allAccountBalances();
  const active = balances.filter(([, amount]) => amount !== 0);
  const assets = active.filter(([name]) => accountType(name) === "asset").reduce((sum, [, value]) => sum + value, 0);
  const liabilities = active.filter(([name]) => accountType(name) === "liability").reduce((sum, [, value]) => sum + value, 0);
  $("#content").innerHTML = `<div class="account-summary"><div class="summary-tile"><span>Active accounts</span><strong>${active.length}</strong></div><div class="summary-tile"><span>Total assets</span><strong>${formatMoney(assets)}</strong></div><div class="summary-tile"><span>Total liabilities</span><strong>${formatMoney(liabilities)}</strong></div></div>
  <section class="card"><div class="card-head"><div><h3>Account balances</h3><span>Natural accounting sign · ${state.commodity}</span></div></div><div class="table-wrap"><table><thead><tr><th>Account</th><th>Type</th><th style="text-align:right">Balance</th></tr></thead><tbody>${balances.map(([name, amount]) => `<tr><td class="account-name">${escapeHtml(name)}</td><td><span class="account-type">${escapeHtml(accountType(name))}</span>${escapeHtml(friendlyAccount(name))}</td><td class="${amount < 0 ? "balance-negative" : "balance-positive"}">${formatMoney(amount)}</td></tr>`).join("")}</tbody></table></div></section>`;
}

function renderReports() {
  const transactions = filteredTransactions();
  const data = reportData(transactions);
  const expenses = expenseAccounts(data.byAccount);
  const expenseTotal = expenses.reduce((sum, [, amount]) => sum + amount, 0);
  let cursor = 0;
  const gradient = expenses.length ? expenses.map(([, amount], index) => { const start = cursor; cursor += amount / expenseTotal * 100; return `${colors[index % colors.length]} ${start}% ${cursor}%`; }).join(",") : "#dfe1d7 0 100%";
  const rowsFor = type => [...data.byAccount].filter(([name]) => accountType(name) === type).sort((a,b) => Math.abs(b[1])-Math.abs(a[1])).map(([name, amount]) => `<div class="statement-row"><span>${escapeHtml(friendlyAccount(name))}</span><strong>${formatMoney(amount)}</strong></div>`).join("") || `<div class="statement-row"><span>No ${type} activity</span><strong>—</strong></div>`;
  $("#content").innerHTML = `<div class="section-head"><div><h2>Financial reports</h2><p>Calculated in-browser from ${transactions.length} matching transactions.</p></div><small>COMMODITY · ${state.commodity}</small></div>
    <div class="report-grid">
      <section class="card"><div class="card-head"><div><h3>Income statement</h3><span>Revenue and spending</span></div></div><div class="report-statement"><small>INCOME</small>${rowsFor("income")}<div class="statement-row"><span>Total income</span><strong>${formatMoney(data.totals.income)}</strong></div><br><small>EXPENSES</small>${rowsFor("expense")}<div class="statement-row"><span>Total expenses</span><strong>${formatMoney(data.totals.expense)}</strong></div><div class="statement-row total"><span>Net income</span><strong>${formatMoney(data.totals.income - data.totals.expense)}</strong></div></div></section>
      <section class="card"><div class="card-head"><div><h3>Balance sheet</h3><span>Assets and obligations</span></div></div><div class="report-statement"><small>ASSETS</small>${rowsFor("asset")}<div class="statement-row"><span>Total assets</span><strong>${formatMoney(data.totals.asset)}</strong></div><br><small>LIABILITIES</small>${rowsFor("liability")}<div class="statement-row"><span>Total liabilities</span><strong>${formatMoney(data.totals.liability)}</strong></div><div class="statement-row total"><span>Net position</span><strong>${formatMoney(data.totals.asset - data.totals.liability)}</strong></div></div></section>
      <section class="card"><div class="card-head"><div><h3>Expense composition</h3><span>Share of total spending</span></div></div><div class="donut-section"><div class="donut" style="background:conic-gradient(${gradient})"><div class="donut-center"><strong>${formatMoney(expenseTotal, true)}</strong><small>Total</small></div></div><div class="legend-list">${expenses.slice(0,7).map(([name, amount], index) => `<div class="legend-item"><i style="background:${colors[index % colors.length]}"></i><span>${escapeHtml(friendlyAccount(name))}</span><strong>${expenseTotal ? Math.round(amount / expenseTotal * 100) : 0}%</strong></div>`).join("") || "No expenses"}</div></div></section>
      <section class="card"><div class="card-head"><div><h3>Monthly trend</h3><span>Income vs expenses</span></div></div><div class="chart-wrap">${lineChart(transactions)}</div></section>
    </div>`;
}

function showWelcome() { $("#dashboard").hidden = true; $("#welcome").hidden = false; $("#file-input").value = ""; $("#journal-file-input").value = ""; }
let toastTimer;
function showToast(message, duration = 3500) { const toast = $("#toast"); toast.textContent = message; toast.classList.add("show"); clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.classList.remove("show"), duration); }

const dropZone = $("#drop-zone");
dropZone.addEventListener("click", event => {
  if (event.target === $("#file-input") || event.target === $("#journal-file-input")) return;
  if (!event.target.closest("button") || event.target.closest(".primary-button")) $("#file-input").click();
});
dropZone.addEventListener("keydown", event => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); $("#file-input").click(); } });
["dragenter", "dragover"].forEach(type => dropZone.addEventListener(type, event => { event.preventDefault(); dropZone.classList.add("dragging"); }));
["dragleave", "drop"].forEach(type => dropZone.addEventListener(type, event => { event.preventDefault(); dropZone.classList.remove("dragging"); }));
dropZone.addEventListener("drop", async event => {
  try { await openFiles(await filesFromDrop(event.dataTransfer)); }
  catch (error) { showToast(`Could not read that folder: ${error.message}`, 6500); }
});
$("#file-input").addEventListener("change", event => openFiles(event.target.files));
$("#journal-file-input").addEventListener("change", event => openFiles(event.target.files));
$(".file-link").addEventListener("click", event => { event.stopPropagation(); $("#journal-file-input").click(); });
$("#demo-button").addEventListener("click", () => { try { loadJournal(combineDocuments([parseDocument(DEMO_JOURNAL, "sample.fiscus")])); } catch (error) { showToast(error.message); } });
$("#open-new").addEventListener("click", showWelcome);
$("#replace-file").addEventListener("click", () => $("#file-input").click());
$$(".nav-item").forEach(button => button.addEventListener("click", () => { state.view = button.dataset.view; render(); }));
$("#account-filter").addEventListener("change", event => { state.account = event.target.value; render(); });
$("#commodity-filter").addEventListener("change", event => { state.commodity = event.target.value; render(); });
$("#tag-chips").addEventListener("click", event => { const button = event.target.closest("[data-tag]"); if (!button) return; state.tag = button.dataset.tag; $$(".tag-chip").forEach(chip => chip.classList.toggle("active", chip === button)); render(); });
$("#search-input").addEventListener("input", event => { state.search = event.target.value; if (state.view === "overview" || state.view === "transactions") render(); });
$("#clear-filters").addEventListener("click", () => { state.account = ""; state.tag = ""; state.search = ""; $("#account-filter").value = ""; $("#search-input").value = ""; $$(".tag-chip").forEach(chip => chip.classList.toggle("active", chip.dataset.tag === "")); render(); });
document.addEventListener("keydown", event => { if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); $("#search-input").focus(); } });
