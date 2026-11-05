'use strict';
// Zero-network, repeatable UX reliability gate. Every AsyncPanel must retry
// with a new request, never an already-started Future from the parent build.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..', 'lib');
function walk(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(entry => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(full) : entry.name.endsWith('.dart') ? [full] : [];
  });
}
let total = 0;
const violations = [];
for (const file of walk(root)) {
  if (file === path.join(root, 'widgets', 'async_panel.dart')) continue;
  const content = fs.readFileSync(file, 'utf8');
  const starts = [...content.matchAll(/\bAsyncPanel\s*\(/g)];
  for (const found of starts) {
    const body = content.slice(found.index + found[0].length);
    const builder = body.search(/\n\s*builder:\s*/);
    const head = builder < 0 ? '' : body.slice(0, builder);
    total++;
    if (!/\n\s*loader:\s*\(\)\s*=>/.test(head) ||
        /\n\s*future:\s*/.test(head)) {
      violations.push(path.relative(root, file) + ':' + content.slice(0, found.index).split('\n').length);
    }
  }
}
const widget = fs.readFileSync(path.join(root, 'widgets', 'async_panel.dart'), 'utf8');
if (!widget.includes('required this.loader') ||
    !widget.includes('Future<dynamic>.sync(widget.loader)') ||
    !widget.includes('void _retry() {') ||
    !widget.includes('setState(() {') ||
    widget.includes('() => _future = Future<dynamic>.sync(widget.loader)')) {
  violations.push('widgets/async_panel.dart: request factory / retry invariant');
}
// The original 42-callsite audit included two independent employee loads in
// Team Operations (Hierarchy + Employees). Both now share ONE authorised
// Team Directory request; this intentional consolidation reduces the audited
// census by exactly one without weakening any loader/retry invariant.
const team = fs.readFileSync(path.join(root, 'screens', 'organization', 'team_screen.dart'), 'utf8');
const teamEmployeeCalls = [...team.matchAll(/ApiPaths\.employees/g)].length;
if (teamEmployeeCalls !== 1 ||
    !team.includes("ValueKey('canonical-team-directory')") ||
    !team.includes('onOpenEmployee: _employeeDesignations')) {
  violations.push('Team Directory consolidation must preserve one authorised employee loader and existing detail action');
}
if (total < 41) violations.push('AsyncPanel census below audited 41 screen callsites after duplicate Team employee panel consolidation: ' + total);
if (violations.length) {
  console.error('FAIL async panel reliability: ' + violations.join(', '));
  process.exit(1);
}
console.log('PASS: ' + total + ' AsyncPanel screen instances use fresh-request loaders and retry is real');
