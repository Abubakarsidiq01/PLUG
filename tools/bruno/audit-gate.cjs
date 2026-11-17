// Fail on any high or critical npm advisory except the documented exception.
// Exception and review date: docs/maintenance/dependency-updates.md.
const ALLOWED = new Set(['GHSA-fc5q-39xc-vjpf']);
const BLOCKING = new Set(['high', 'critical']);

function blockingAdvisories(report) {
  if (!report || typeof report.vulnerabilities !== 'object' || report.error) {
    throw new Error('npm audit did not return a vulnerability report');
  }
  const found = new Map();
  for (const vuln of Object.values(report.vulnerabilities)) {
    for (const via of vuln.via) {
      // String entries point at another package; its own advisories are checked there.
      if (typeof via !== 'object') continue;
      const id = String(via.url || via.source).split('/').pop();
      if (!ALLOWED.has(id) && BLOCKING.has(via.severity)) found.set(id, `${id} ${via.severity} ${via.name}: ${via.title}`);
    }
  }
  return [...found.values()];
}

if (require.main === module) {
  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => { input += chunk; });
  process.stdin.on('end', () => {
    try {
      const blocking = blockingAdvisories(JSON.parse(input));
      if (blocking.length) {
        console.error(`Blocking advisories:\n${blocking.join('\n')}`);
        process.exit(1);
      }
      console.log(`No high or critical advisories outside: ${[...ALLOWED].join(', ')}`);
    } catch (error) {
      console.error(error.message);
      process.exit(1);
    }
  });
}

module.exports = { blockingAdvisories };
