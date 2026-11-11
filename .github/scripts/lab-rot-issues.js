module.exports = async function updateLabRotIssue({
  github,
  context,
  core,
  findings,
  fingerprint,
}) {
  if (!findings || !fingerprint) {
    throw new Error('Findings and fingerprint are required to update a lab-rot issue.');
  }

  const { owner, repo } = context.repo;
  const marker = `<!-- lab-rot-fingerprint:${fingerprint} -->`;
  const labelName = 'lab-rot';

  try {
    await github.rest.issues.getLabel({ owner, repo, name: labelName });
  } catch (error) {
    if (error.status !== 404) {
      throw error;
    }
    await github.rest.issues.createLabel({
      owner,
      repo,
      name: labelName,
      color: 'FBCA04',
      description: 'Weekly lab drift findings (static checks)',
    });
  }

  const openIssues = await github.paginate(github.rest.issues.listForRepo, {
    owner,
    repo,
    state: 'open',
    labels: labelName,
    per_page: 100,
  });
  const matching = openIssues.find(
    issue => !issue.pull_request && (issue.body || '').includes(marker)
  );
  if (matching) {
    core.info(`Issue #${matching.number} already covers these findings; no update needed.`);
    return;
  }

  const runUrl = `https://github.com/${owner}/${repo}/actions/runs/${context.runId}`;
  const date = new Date().toISOString().slice(0, 10);
  const body = [
    marker,
    '',
    'Static-analysis drift signals were detected in this lab repository.',
    '',
    '## Findings checklist',
    findings,
    '',
    `Run: ${runUrl}`,
  ].join('\n');
  const created = await github.rest.issues.create({
    owner,
    repo,
    title: `Lab rot watch findings (${date})`,
    body,
    labels: [labelName],
  });
  core.info(`Opened issue #${created.data.number}`);
};
