const assert = require('node:assert/strict');
const test = require('node:test');
const updateLabRotIssue = require('../scripts/lab-rot-issues.js');

function harness({ issues = [], labelError } = {}) {
  const calls = { labels: [], issues: [], messages: [], queries: [] };
  const github = {
    rest: {
      issues: {
        getLabel: async () => {
          if (labelError) throw labelError;
        },
        createLabel: async params => calls.labels.push(params),
        listForRepo: () => {},
        create: async params => {
          calls.issues.push(params);
          return { data: { number: 42 } };
        },
      },
    },
    paginate: async (_method, params) => {
      calls.queries.push(params);
      return issues;
    },
  };
  return {
    calls,
    args: {
      github,
      context: { repo: { owner: 'owner', repo: 'repo' }, runId: 123 },
      core: { info: message => calls.messages.push(message) },
      findings: '- [ ] A real finding',
      fingerprint: 'stable-fingerprint',
    },
  };
}

test('unchanged findings do not create an issue or a repeat comment', async () => {
  const { calls, args } = harness({
    issues: [{ number: 11, body: '<!-- lab-rot-fingerprint:stable-fingerprint -->' }],
  });
  await updateLabRotIssue(args);
  assert.equal(calls.issues.length, 0);
  assert.match(calls.messages[0], /already covers these findings/);
  assert.equal(calls.queries[0].per_page, 100);
});

test('new findings create an issue with the fingerprint and run link', async () => {
  const { calls, args } = harness();
  await updateLabRotIssue(args);
  assert.equal(calls.issues.length, 1);
  assert.match(calls.issues[0].body, /lab-rot-fingerprint:stable-fingerprint/);
  assert.match(calls.issues[0].body, /A real finding/);
  assert.match(calls.issues[0].body, /https:\/\/github\.com\/owner\/repo\/actions\/runs\/123/);
  assert.deepEqual(calls.issues[0].labels, ['lab-rot']);
});

test('a pull request with the same marker does not suppress an issue', async () => {
  const { calls, args } = harness({
    issues: [{
      number: 9,
      body: '<!-- lab-rot-fingerprint:stable-fingerprint -->',
      pull_request: {},
    }],
  });
  await updateLabRotIssue(args);
  assert.equal(calls.issues.length, 1);
});

test('a missing lab-rot label is created', async () => {
  const { calls, args } = harness({ labelError: { status: 404 } });
  await updateLabRotIssue(args);
  assert.equal(calls.labels.length, 1);
  assert.equal(calls.labels[0].name, 'lab-rot');
});

test('GitHub errors other than a missing label are surfaced', async () => {
  const error = { status: 403 };
  const { calls, args } = harness({ labelError: error });
  await assert.rejects(updateLabRotIssue(args), received => received === error);
  assert.equal(calls.issues.length, 0);
});

test('missing scan output is rejected', async () => {
  const { args } = harness();
  args.fingerprint = '';
  await assert.rejects(updateLabRotIssue(args), /Findings and fingerprint are required/);
});
