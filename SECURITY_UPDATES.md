# Builder image security updates

These changes address the dependency versions in the October 11, 2026 scan of
`quay.io/semoss/smss-node-builder` (37 alerts). They require a new image build,
deployment of its digest, and a rescan before the deployed findings can be
considered resolved.

## Changes

| Component | Scanned version | Branch change |
| --- | --- | --- |
| OpenSSL | 3.5.7-r0 | Alpine 3.24 package upgrades; require openssl, libssl3, and libcrypto3 >= 3.5.9-r0 |
| Multer | 1.4.5-lts.2 | 2.4.0 |
| proxy-addr | 2.0.7 | Override to 2.0.8 |
| Application brace-expansion | 2.0.2 | Override to 2.1.7 |
| lodash | 4.17.23 | Override to 4.18.1 |
| pnpm | 11.9.0 | Pin 11.28.5; its published distribution bundles tar 7.5.22 |
| npm's brace-expansion | 5.0.7 | Replace npm's bundled module with 5.0.12 |
| npm's tar | 7.5.19 | npm 11.21.0 bundles 7.5.22 |
| npm's ip-address | 10.2.0 | npm 11.21.0 bundles 10.5.0 |
| npm's http-cache-semantics | 4.2.0 | Replace with 4.3.0, outside the reported affected range; advisory remains disputed |

Express stays on major version 4, updated to 4.22.3. The service dependencies
are resolved in the regenerated frozen lockfile. Transitive overrides live in
`pnpm-workspace.yaml`, which is also copied into the image before installation.

The AWS ECR Node base uses `24-alpine3.24`. CI pulls the base and disables the
build cache so package upgrades are performed on every image build. The minimum
OpenSSL versions make the build fail if the required patches are unavailable.

## Package manager compatibility

pnpm and npm 11.21.0 are installed globally, accessible to the existing non-root
`builder` user. npm/npx remain available for scripts inside uploaded apps.
Corepack and its root download cache are removed.
`PNPM_CONFIG_PM_ON_FAIL=ignore` keeps ordinary project package-manager pins from
switching back to an older pnpm release. Dependency build scripts remain enabled,
as in the original image.

The local SEMOSS `BuildAndPublishAppReactor` sends the command
`pnpm install --no-frozen-lockfile && pnpm run build`. The standard template's
client build runs `tsc -b && vite build`, but uploaded app scripts can invoke
npm/npx themselves, so the image preserves those commands.

Inspection of the published npm 11.21.0 and 12.2.0 distributions found
brace-expansion 5.0.9 and http-cache-semantics 4.2.0 still bundled. The Docker
build therefore uses `npm ci` with the separate `npm-security/package-lock.json`
to install replacement modules. It copies brace-expansion 5.0.12, its compatible
balanced-match dependency, and http-cache-semantics 4.3.0 into npm's internal
module directory. This is a maintained override of npm's published distribution;
remove it when an upstream npm release bundles acceptable versions.

`scripts/verify-toolchain.mjs` walks both installed CLI distributions, including
nested modules, and fails the image build if any scanned package is below the
configured version floor or is missing. This checks installed package versions,
not exploitability or advisory validity.

The http-cache-semantics advisory lists no patched release and is disputed
upstream. Version 4.3.0 is outside its listed affected range (`<=4.2.0`), but that
alone is not evidence that the reported behavior has been fixed:

- [CVE-2026-93748 advisory](https://github.com/advisories/GHSA-ch52-4w7c-c8xp)
- [Upstream dispute](https://github.com/github/advisory-database/issues/10139)

## Local validation

- Frozen-lockfile installation succeeded using pnpm 11.28.5 in an isolated
  temporary directory, preserving the checkout's existing `node_modules`.
- Before merging main, the service's default install/build flow succeeded for both wrapped `client/`
  ZIPs and ZIPs containing client files at the archive root. Returned ZIP contents
  and the build's pnpm version were checked.
- A fixture pinning pnpm 11.9.0 still built using 11.28.5 with the image setting.
- The compatibility flow uses the reactor's exact command with uploaded app
  scripts invoking `npm run` and `npx --no-install` for a local executable.
- The toolchain version check rejects the unmodified npm distribution's
  brace-expansion 5.0.9 and accepts the overridden distribution.
- Missing files, invalid ZIPs, oversized uploads, and interrupted multipart
  uploads were exercised. The service remained healthy and upload files were
  cleaned up.
- AWS ECR publishes the selected base tag for amd64 and arm64. Alpine's package
  indexes contain OpenSSL/libssl3/libcrypto3 3.5.9-r0 for both architectures.
- Docker was not running locally; the final image has not been built or scanned.

The application audit reports two additional high-severity extract-zip 2.0.1
advisories with no published fix. They were absent from the supplied scan and
remain unresolved; no advisories are suppressed:

- [GHSA-jmr9-qjv8-65gv](https://github.com/advisories/GHSA-jmr9-qjv8-65gv)
- [GHSA-7pqw-9j4j-h8q3](https://github.com/advisories/GHSA-7pqw-9j4j-h8q3)

The merged main branch includes the completed-build work-directory cleanup fix
and extracts uploads into a subdirectory instead of renaming the extracted
directory. These upstream server changes are retained alongside the dependency
updates. The image also preserves main's `PNPM_CONFIG_MINIMUM_RELEASE_AGE=0`
policy.

After merging main, the wrapped `client/` fixture fails: its build writes
`../portals` under the extraction subdirectory, while the server still looks
for `portals` directly under the work directory. This is inherited from main's
ZIP-layout change, not the security dependency updates. `BuildAndPublishApp`
uploads flat ZIP entries relative to the client directory, so its layout is
checked separately: that flow passes with npm/npx, and no completed-build work
directories remain after the upload checks. No server changes are added on top
of main in this branch.

## Image verification

With Docker running, build a local review image:

```bash
docker build --pull --no-cache -t smss-node-builder:security-review .
docker run --rm smss-node-builder:security-review sh -c \
  'node --version && pnpm --version && npm --version && npx --version && openssl version && ! command -v corepack'
```

Run the upload smoke flow against this image and scan its final filesystem for
both amd64 and arm64. Verify the deployed digest after rollout; publishing a new
`latest` tag does not update existing pods.
