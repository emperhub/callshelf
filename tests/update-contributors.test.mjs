import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  fetchContributors,
  renderContributorsSvg,
  updateContributorsSvg,
} from '../scripts/update-contributors.mjs';

test('fetches contributors across pages', async () => {
  const requests = [];
  const firstPage = Array.from({ length: 100 }, (_, index) => ({ login: `user-${index}` }));
  const secondPage = [{ login: 'user-100' }];
  const fetchImpl = async (url, options) => {
    requests.push({ url: String(url), options });
    const data = requests.length === 1 ? firstPage : secondPage;
    return { ok: true, json: async () => data };
  };

  const contributors = await fetchContributors('emperhub/callshelf', 'test-token', fetchImpl);

  assert.equal(contributors.length, 101);
  assert.match(requests[0].url, /page=1$/);
  assert.match(requests[1].url, /page=2$/);
  assert.equal(requests[0].options.headers.Authorization, 'Bearer test-token');
});

test('renders a valid empty-state SVG', () => {
  const svg = renderContributorsSvg([]);

  assert.match(svg, /<svg[^>]+width="[^"]+"/);
  assert.match(svg, /<svg[^>]+height="[^"]+"/);
  assert.match(svg, /No contributors yet/);
});

test('escapes contributor labels and rejects unsafe profile/avatar URLs', () => {
  const contributor = {
    login: 'alice<&"',
    html_url: 'https://github.com/alice',
    avatar_url: 'https://avatars.githubusercontent.com/u/1?v=4',
    avatar_data_url: 'data:image/png;base64,AQID',
    contributions: 3,
  };
  const svg = renderContributorsSvg([contributor]);

  assert.match(svg, /alice&lt;&amp;&quot;/);
  assert.doesNotMatch(svg, /alice<&"/);
  assert.throws(
    () => renderContributorsSvg([{ ...contributor, html_url: 'javascript:alert(1)' }]),
    /profile URL/,
  );
  assert.throws(
    () => renderContributorsSvg([{ ...contributor, avatar_url: 'https://example.com/avatar.png' }]),
    /avatar URL/,
  );
});

test('renders identical output for identical contributor data', () => {
  const contributor = {
    login: 'alice',
    html_url: 'https://github.com/alice',
    avatar_url: 'https://avatars.githubusercontent.com/u/1',
    avatar_data_url: 'data:image/png;base64,AQID',
    contributions: 3,
  };

  assert.equal(renderContributorsSvg([contributor]), renderContributorsSvg([contributor]));
});

test('does not overwrite SVG when contributor fetch fails', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'contributors-test-'));
  const outputPath = join(directory, 'contributors.svg');
  const failures = [
    [
      async () => ({ ok: false, status: 503 }),
      /HTTP 503/,
    ],
    [
      async () => {
        throw new Error('network unavailable');
      },
      /network unavailable/,
    ],
    [
      async () => ({
        ok: true,
        json: async () => {
          throw new SyntaxError('invalid JSON');
        },
      }),
      /invalid JSON/,
    ],
    [
      async () => ({ ok: true, json: async () => ({ message: 'invalid payload' }) }),
      /invalid response/,
    ],
  ];

  try {
    for (const [fetchImpl, expectedError] of failures) {
      await writeFile(outputPath, 'existing-svg');
      await assert.rejects(
        updateContributorsSvg(outputPath, 'emperhub/callshelf', 'test-token', fetchImpl),
        expectedError,
      );
      assert.equal(await readFile(outputPath, 'utf8'), 'existing-svg');
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('embeds avatar bytes in SVG instead of relying on external images', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'contributors-avatar-test-'));
  const outputPath = join(directory, 'contributors.svg');
  const avatarBytes = Uint8Array.from([1, 2, 3]).buffer;
  const avatarRequests = [];
  const fetchImpl = async (input, options) => {
    const url = new URL(input);
    if (url.hostname === 'api.github.com') {
      return {
        ok: true,
        json: async () => [{
          login: 'alice',
          html_url: 'https://github.com/alice',
          avatar_url: 'https://avatars.githubusercontent.com/u/1?v=4',
          contributions: 3,
        }],
      };
    }
    avatarRequests.push({ url, options });
    return {
      ok: true,
      headers: { get: (name) => name === 'content-type' ? 'image/png' : null },
      arrayBuffer: async () => avatarBytes,
    };
  };

  try {
    await updateContributorsSvg(outputPath, 'emperhub/callshelf', 'test-token', fetchImpl);
    const svg = await readFile(outputPath, 'utf8');

    assert.match(svg, /href="data:image\/png;base64,AQID"/);
    assert.doesNotMatch(svg, /<image[^>]+https:\/\/avatars\.githubusercontent\.com/);
    assert.equal(avatarRequests[0].url.searchParams.get('s'), '64');
    assert.equal(avatarRequests[0].options.headers.Authorization, undefined);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('preserves SVG when avatar fetch or validation fails', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'contributors-avatar-reject-'));
  const outputPath = join(directory, 'contributors.svg');
  const contributor = {
    login: 'alice',
    html_url: 'https://github.com/alice',
    avatar_url: 'https://avatars.githubusercontent.com/u/1',
    contributions: 3,
  };
  const invalidAvatars = [
    { type: 'image/svg+xml', bytes: Uint8Array.from([1, 2, 3]) },
    { type: 'image/png', bytes: new Uint8Array(256 * 1024 + 1) },
    { status: 503 },
  ];

  try {
    for (const avatar of invalidAvatars) {
      await writeFile(outputPath, 'existing-svg');
      const fetchImpl = async (input) => {
        const url = new URL(input);
        if (url.hostname === 'api.github.com') {
          return { ok: true, json: async () => [contributor] };
        }
        if (avatar.status) {
          return { ok: false, status: avatar.status };
        }
        return {
          ok: true,
          headers: { get: (name) => name === 'content-type' ? avatar.type : null },
          arrayBuffer: async () => avatar.bytes.buffer,
        };
      };

      await assert.rejects(
        updateContributorsSvg(outputPath, 'emperhub/callshelf', 'test-token', fetchImpl),
      );
      assert.equal(await readFile(outputPath, 'utf8'), 'existing-svg');
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('workflow updates contributors on main pushes and manual dispatch', async () => {
  const workflow = await readFile(
    new URL('../.github/workflows/update-contributors.yml', import.meta.url),
    'utf8',
  );

  assert.match(workflow, /^on:\n  push:\n    branches:\n      - main/m);
  assert.match(workflow, /^\s+workflow_dispatch:\s*$/m);
  const permissions = workflow.match(/^permissions:\n((?:  [^\n]+\n)+)/m);
  assert.equal(permissions?.[1].trim(), 'contents: write');
  assert.match(workflow, /node scripts\/update-contributors\.mjs/);
  assert.match(workflow, /GITHUB_TOKEN:\s*\$\{\{\s*secrets\.GITHUB_TOKEN\s*\}\}/);
  assert.doesNotMatch(workflow, /(?:echo|printf)[^\n]*GITHUB_TOKEN/);
});

test('workflow commits only changed SVG', async () => {
  const workflow = await readFile(
    new URL('../.github/workflows/update-contributors.yml', import.meta.url),
    'utf8',
  );

  assert.match(workflow, /git diff --quiet -- docs\/contributors\.svg/);
  assert.match(workflow, /git add docs\/contributors\.svg/);
  assert.match(workflow, /git commit/);
});

test('README embeds the generated image and retains Copilot credit', async () => {
  const readme = await readFile(new URL('../README.md', import.meta.url), 'utf8');

  assert.match(readme, /!\[[^\]]+\]\(docs\/contributors\.svg\)/);
  assert.match(readme, /GitHub Actions/);
  assert.match(readme, /GitHub Copilot/);
});
