// node tools/run_reliability_tests.cjs <Godot console executable>
// Creates a disposable project; never reads real user config/saves or calls a model.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const { spawn } = require('node:child_process');
const godot = process.argv[2];
if (!godot) throw new Error('Provide the Godot console executable path.');
const source = path.resolve(__dirname, '..');
const isolated = fs.mkdtempSync(path.join(os.tmpdir(), 'llm-reliability-'));
const data = path.join(isolated, 'test-data').replaceAll('\\', '/') + '/';
fs.mkdirSync(data);
function copyTree(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const input = path.join(from, entry.name), output = path.join(to, entry.name);
    if (entry.isDirectory()) copyTree(input, output);
    else if (entry.isFile()) fs.writeFileSync(output, fs.readFileSync(input));
  }
}
for (const name of ['scripts', 'tools', 'shaders', 'data']) {
  copyTree(path.join(source, name), path.join(isolated, name));
}
function redirect(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) redirect(file);
    else if (entry.name.endsWith('.gd')) fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replaceAll('user://', data));
  }
}
redirect(path.join(isolated, 'scripts'));
redirect(path.join(isolated, 'tools'));
const counts = {}, bodies = {};
const tool = { id: 'probe', type: 'function', function: { name: 'reliability_probe', arguments: '{}' } };
const text = { choices: [{ message: { role: 'assistant', content: '<content>TEST_REPLY</content>' } }] };
const tools = { choices: [{ message: { role: 'assistant', content: null, tool_calls: [tool] } }] };
const malformed = [null, [], {}, { choices: [] }, { choices: {} }, { choices: [null] }, { choices: [{}] }, { choices: [{ message: [] }] }, { choices: [{ message: { content: 42 } }] }, { choices: [{ message: { content: {}, tool_calls: [] } }] }, { choices: [{ message: { tool_calls: {} } }] }, { choices: [{ message: { tool_calls: [null] } }] }, { choices: [{ message: { tool_calls: [{ function: { name: 'x', arguments: '{}' } }] } }] }, { choices: [{ message: { tool_calls: [tool, { id: 'bad', function: { name: 'x', arguments: '{' } }] } }] }, { choices: [{ message: { tool_calls: [tool, tool] } }] }];
const server = http.createServer((req, res) => {
  let raw = '';
  req.on('data', chunk => { raw += chunk; });
  req.on('end', () => {
    const route = req.url;
    counts[route] = (counts[route] || 0) + 1;
    (bodies[route] ||= []).push(raw);
    fs.writeFileSync(path.join(isolated, 'http-received' + route.replaceAll('/', '_')), 'received');
    let code = 200, reply = text, delay = 0;
    if (route.startsWith('/late')) { reply = tools; delay = 350; }
    if (route === '/slow') delay = 700;
    if (route === '/retry-cancel' || route === '/exhaust' || (route === '/retry-tool' && counts[route] <= 5)) { code = 503; reply = {}; }
    if (route === '/retry-tool' && counts[route] === 6) reply = tools;
    if (route === '/empty-tool' && counts[route] <= 5) reply = { choices: [{ message: { content: '' } }] };
    if (route === '/empty-tool' && counts[route] === 6) reply = tools;
    if (route === '/tool-limit' && counts[route] <= 5) reply = tools;
    if (route === '/plain') reply = { choices: [{ message: { role: 'assistant', content: 'PLAIN_REPLY' } }] };
    if (route.startsWith('/invalid/')) reply = malformed[Number(route.split('/').pop())];
    if (route === '/bad-json') reply = 'NOT_JSON';
    const response = typeof reply === 'string' ? reply : JSON.stringify(reply);
    setTimeout(() => {
      if (!res.destroyed) { res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(response), 'Connection': 'close' }); res.end(response); }
    }, delay);
  });
});
function run(args, timeout = 60000) {
  return new Promise((resolve, reject) => {
    const child = spawn(godot, ['--headless', '--path', isolated, ...args], { windowsHide: true });
    let output = '';
    child.stdout.on('data', chunk => { output += chunk; process.stdout.write(chunk); });
    child.stderr.on('data', chunk => { output += chunk; process.stderr.write(chunk); });
    const timer = setTimeout(() => { child.kill(); reject(new Error('Godot test timeout')); }, timeout);
    child.on('error', reject);
    child.on('exit', code => {
      clearTimeout(timer);
      if (code || /SCRIPT ERROR|❌|Parse Error/.test(output)) reject(new Error(`Test failed (exit ${code})`));
      else resolve();
    });
  });
}
async function main() {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  fs.writeFileSync(path.join(isolated, '.reliability-isolated'), 'test-only');
  fs.writeFileSync(path.join(data, 'config.cfg'), `[llm]\nactive_api="custom"\napi_url="http://127.0.0.1:${port}/text"\napi_key="test-placeholder"\nmodel="offline-test"\n`);
  fs.writeFileSync(path.join(isolated, 'project.godot'), `config_version=5\n[application]\nconfig/name="LLM Reliability Tests"\n[autoload]\n${['ConfigManager','EventBus','SaveManager','DataManager','PromptSchema','LLMToolExecutor','LLMClient'].map(n => `${n}="*res://scripts/${n}.gd"`).join('\n')}\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n`);
  fs.writeFileSync(path.join(isolated, 'tools/reliability_regression_test.tscn'), '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tools/reliability_regression_test.gd" id="1"]\n[node name="Test" type="Node"]\nscript = ExtResource("1")\n');
  fs.writeFileSync(path.join(isolated, 'tools/audit_fix_regression_test.tscn'), '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tools/audit_fix_regression_test.gd" id="1"]\n[node name="Test" type="Node"]\nscript = ExtResource("1")\n');
  console.log('Isolated test directory:', isolated);
  await run(['--editor', '--import', '--quit']);
  await run(['res://tools/reliability_regression_test.tscn']);
  await run(['res://tools/audit_fix_regression_test.tscn']);
  for (const name of ['save_load', 'new_game_clean', 'history_clean', 'rollback_tool', 'timeout', 'busy_state']) {
    await run([`res://tools/${name}_test.tscn`]);
  }
  function check(ok, label) { if (!ok) throw new Error(label); }
  for (const route of ['/late-load', '/late-new', '/late-reset']) {
    check(counts[route] === 1, route + ': cancellation test never reached server');
  }
  check(counts['/retry-cancel'] === 1, 'Canceled retry sent again');
  check(counts['/exhaust'] === 6, 'Network retry limit was not enforced');
  for (const route of ['/retry-tool', '/empty-tool']) {
    check(counts[route] === 7, `${route}: wrong retry/tool request count`);
    check(bodies[route].slice(0, 6).every(body => body === bodies[route][0]), `${route}: retry payload changed`);
    check(bodies[route].every(body => JSON.parse(body).tools), `${route}: retry consumed tools budget`);
  }
  check(counts['/tool-limit'] === 6 && !JSON.parse(bodies['/tool-limit'][5]).tools, 'Actual tool loop limit was not enforced');
  const limitPayloads = bodies['/tool-limit'].map(body => JSON.parse(body));
  check(limitPayloads.slice(0, 5).every(body => !body.messages.some(message => message.role === 'system' && message.content.includes('达到工具调用上限'))), 'Tool limit instruction appeared too early');
  check(limitPayloads[5].messages.some(message => message.role === 'system' && message.content.includes('达到工具调用上限')), 'Final tool request missing limit instruction');
  const plainNext = JSON.parse(bodies['/plain-next'][0]);
  check(plainNext.messages.some(message => message.role === 'system' && message.content.startsWith('[System: Format Correction]')), 'Format correction missing from next request');
  check(plainNext.messages.find(message => message.role === 'assistant' && message.content === 'PLAIN_REPLY'), 'Plain reply changed in transport history');
  check(plainNext.messages.every(message => !Object.hasOwn(message, 'format_error')), 'Local format metadata leaked into API messages');
  fs.writeFileSync(path.join(isolated, 'http-evidence.json'), JSON.stringify({ counts, retry_payloads_identical: true }, null, 2));
  console.log('ALL_RELIABILITY_TESTS_PASSED');
  console.log('Evidence:', isolated);
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());
