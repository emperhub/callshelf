import { writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const CONTRIBUTORS_PER_PAGE = 100;
const MAX_AVATAR_BYTES = 256 * 1024;
const AVATAR_CONTENT_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

export async function fetchContributors(repository, token, fetchImpl = fetch) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) {
    throw new Error('GITHUB_REPOSITORY must use owner/repository format');
  }
  if (!token) {
    throw new Error('GITHUB_TOKEN is required');
  }

  const contributors = [];
  for (let page = 1; ; page += 1) {
    const url = new URL(`https://api.github.com/repos/${repository}/contributors`);
    url.searchParams.set('per_page', String(CONTRIBUTORS_PER_PAGE));
    url.searchParams.set('page', String(page));

    const response = await fetchImpl(url, {
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28',
      },
    });
    if (!response.ok) {
      throw new Error(`GitHub contributors API returned HTTP ${response.status}`);
    }

    const data = await response.json();
    if (!Array.isArray(data)) {
      throw new Error('GitHub contributors API returned an invalid response');
    }
    contributors.push(...data);
    if (data.length < CONTRIBUTORS_PER_PAGE) {
      return contributors;
    }
  }
}

export function renderContributorsSvg(contributors) {
  if (!Array.isArray(contributors)) {
    throw new TypeError('contributors must be an array');
  }
  if (contributors.length === 0) {
    return [
      '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="80" viewBox="0 0 300 80" role="img" aria-labelledby="title">',
      '<title id="title">Repository contributors</title>',
      '<text x="12" y="44">No contributors yet</text>',
      '</svg>',
      '',
    ].join('\n');
  }

  const columns = Math.min(8, contributors.length);
  const rows = Math.ceil(contributors.length / columns);
  const size = 64;
  const gap = 12;
  const padding = 12;
  const width = padding * 2 + columns * size + (columns - 1) * gap;
  const height = padding * 2 + rows * size + (rows - 1) * gap;
  const avatars = contributors.map((contributor, index) => {
    if (typeof contributor.login !== 'string' || contributor.login.length === 0) {
      throw new TypeError('Contributor login must be a nonempty string');
    }
    const profileUrl = validateGitHubUrl(contributor.html_url, 'github.com', 'profile');
    validateGitHubUrl(
      contributor.avatar_url,
      'avatars.githubusercontent.com',
      'avatar',
    );
    const avatarDataUrl = validateAvatarDataUrl(contributor.avatar_data_url);
    const label = escapeXml(contributor.login);
    const x = padding + (index % columns) * (size + gap);
    const y = padding + Math.floor(index / columns) * (size + gap);

    return [
      `<clipPath id="avatar-${index}"><circle cx="${x + size / 2}" cy="${y + size / 2}" r="${size / 2}"/></clipPath>`,
      `<a href="${escapeXml(profileUrl)}" aria-label="${label}">`,
      `<image href="${escapeXml(avatarDataUrl)}" x="${x}" y="${y}" width="${size}" height="${size}" clip-path="url(#avatar-${index})"/>`,
      `<title>${label}</title>`,
      '</a>',
    ].join('');
  });

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title">`,
    '<title id="title">Repository contributors</title>',
    ...avatars,
    '</svg>',
    '',
  ].join('\n');
}

function escapeXml(value) {
  return value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&apos;',
  })[character]);
}

function validateGitHubUrl(value, hostname, type) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new TypeError(`Contributor ${type} URL must be a valid GitHub URL`);
  }
  if (
    url.protocol !== 'https:' ||
    url.hostname !== hostname ||
    url.port ||
    url.username ||
    url.password
  ) {
    throw new TypeError(`Contributor ${type} URL must use https://${hostname}`);
  }
  return url.href;
}

function validateAvatarDataUrl(value) {
  if (!/^data:image\/(?:jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(value ?? '')) {
    throw new TypeError('Contributor avatar must be an embedded raster image');
  }
  return value;
}

async function fetchAvatarDataUrl(avatarUrl, fetchImpl) {
  const url = new URL(validateGitHubUrl(
    avatarUrl,
    'avatars.githubusercontent.com',
    'avatar',
  ));
  url.searchParams.set('s', '64');
  const response = await fetchImpl(url, {
    headers: { Accept: 'image/jpeg,image/png,image/webp' },
  });
  if (!response.ok) {
    throw new Error(`GitHub avatar request returned HTTP ${response.status}`);
  }

  const contentType = response.headers.get('content-type')?.split(';', 1)[0].trim().toLowerCase();
  if (!AVATAR_CONTENT_TYPES.has(contentType)) {
    throw new Error('GitHub avatar response used an unsupported content type');
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length === 0 || bytes.length > MAX_AVATAR_BYTES) {
    throw new Error('GitHub avatar response had an invalid size');
  }
  return `data:${contentType};base64,${Buffer.from(bytes).toString('base64')}`;
}

export async function updateContributorsSvg(outputPath, repository, token, fetchImpl = fetch) {
  const contributors = await fetchContributors(repository, token, fetchImpl);
  const contributorsWithAvatars = [];
  for (const contributor of contributors) {
    if (typeof contributor.login !== 'string' || contributor.login.length === 0) {
      throw new TypeError('Contributor login must be a nonempty string');
    }
    validateGitHubUrl(contributor.html_url, 'github.com', 'profile');
    contributorsWithAvatars.push({
      ...contributor,
      avatar_data_url: await fetchAvatarDataUrl(contributor.avatar_url, fetchImpl),
    });
  }
  const svg = renderContributorsSvg(contributorsWithAvatars);
  await writeFile(outputPath, svg, 'utf8');
}

async function main() {
  const repository = process.env.GITHUB_REPOSITORY;
  const token = process.env.GITHUB_TOKEN;
  if (!repository || !token) {
    throw new Error('GITHUB_REPOSITORY and GITHUB_TOKEN are required');
  }

  const outputPath = fileURLToPath(new URL('../docs/contributors.svg', import.meta.url));
  await updateContributorsSvg(outputPath, repository, token);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(`Failed to update contributors image: ${error.message}`);
    process.exitCode = 1;
  });
}
