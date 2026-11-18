(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.FiscusConversion = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  function setRate(graph, from, to, rate, date, sequence) {
    if (!from || !to || from === to || !Number.isFinite(rate) || rate <= 0) return;
    if (!graph.has(from)) graph.set(from, new Map());
    const existing = graph.get(from).get(to);
    if (!existing || date > existing.date || (date === existing.date && sequence >= existing.sequence)) {
      graph.get(from).set(to, { rate, date, sequence });
    }
  }

  function buildRateGraph(transactions) {
    const graph = new Map();
    let sequence = 0;
    transactions.forEach(transaction => transaction.postings.forEach(posting => {
      sequence += 1;
      if (!posting.commodity || !posting.valuation) return;
      const rate = posting.valuation.amount / posting.amount;
      setRate(graph, posting.commodity, posting.valuation.commodity, rate, transaction.date, sequence);
      setRate(graph, posting.valuation.commodity, posting.commodity, 1 / rate, transaction.date, sequence);
    }));
    return graph;
  }

  function findRate(graph, from, to) {
    if (from === to) return 1;
    const direct = graph.get(from)?.get(to);
    if (direct) return direct.rate;

    const visited = new Set([from]);
    const queue = [{ commodity: from, rate: 1 }];
    while (queue.length) {
      const current = queue.shift();
      for (const [next, edge] of graph.get(current.commodity) || []) {
        if (visited.has(next)) continue;
        const rate = current.rate * edge.rate;
        if (next === to) return rate;
        visited.add(next);
        queue.push({ commodity: next, rate });
      }
    }
    return null;
  }

  return { buildRateGraph, findRate };
});
