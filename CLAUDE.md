# data-viking-public-dev-images

Docker base images for the DataViking development environment. Includes:
- `ai-dev-base` — AI/ML development base image
- `dbt-postgres` — dbt + PostgreSQL tooling
- `godot-game-dev` — Godot Engine game development image

## Environment Gotchas

### macOS `sed -i` — ALWAYS use `sed -i ''`
On macOS, `sed -i` without the empty-string argument silently corrupts files
(appends to the same line instead of inserting a new one). Always write:
```bash
sed -i '' 's/old/new/' file   # correct on macOS
sed -i 's/old/new/' file      # WRONG on macOS — corrupts the file silently
```
When editing multiple files, prefer Python's `str.replace()` or the Edit tool.

### Godot uses SHA512-SUMS.txt — NOT per-file .sha256 files
Godot 4.x does NOT publish per-file `.sha256` checksum files. The URL pattern
`https://github.com/godotengine/godot/releases/download/<ver>/Godot_<ver>_linux.x86_64.zip.sha256`
returns a 404 (silently via `wget -q`), leaving your checksum variable empty.

The correct checksum file is `SHA512-SUMS.txt` using SHA512:
```
https://github.com/godotengine/godot/releases/download/<ver>/SHA512-SUMS.txt
```

In Dockerfiles, use `sha512sum` (not `sha256sum`) and grep the correct filename
from `SHA512-SUMS.txt`:
```dockerfile
RUN wget -q "https://.../${GODOT_VERSION}/SHA512-SUMS.txt" -O /tmp/SHA512-SUMS.txt \
    && EXPECTED=$(grep "Godot_v${GODOT_VERSION}_linux.x86_64.zip$" /tmp/SHA512-SUMS.txt | cut -d' ' -f1) \
    && echo "${EXPECTED}  /tmp/godot.zip" | sha512sum -c -
```

### Decorated branch refs (`@suffix`) — always push to the exact tracked ref
Gas Town polecats use decorated branch refs (e.g., `polecat/furiosa/dv-h8y@mmzzulgs`).
If you commit a fix locally on the short branch name (`polecat/furiosa/dv-h8y`) and
push to that, the PR's CI will NOT re-run. Always get the tracked ref first:
```bash
gh pr view <N> --repo DataViking-Tech/data-viking-public-dev-images --json headRefName
# then push to that exact ref:
git push origin HEAD:<headRefName>
```
