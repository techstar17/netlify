#!/usr/bin/env bash
# Install the pinned CLI; verify its SHA-256 against HashiCorp's HTTPS manifest.
set -euo pipefail
version=1.12.2
install_dir="${TERRAFORM_INSTALL_DIR:-$HOME/.local/bin}"
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo 'Supported platforms: Linux amd64 and arm64' >&2; exit 1 ;;
esac
[ "$(uname -s)" = Linux ] || { echo 'This helper supports Linux only.' >&2; exit 1; }
task_tmp="$(mktemp -d)"
trap 'rm -rf "$task_tmp"' EXIT
artifact="terraform_${version}_linux_${arch}.zip"
base="https://releases.hashicorp.com/terraform/${version}"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$base/$artifact" -o "$task_tmp/$artifact"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$base/terraform_${version}_SHA256SUMS" -o "$task_tmp/SHA256SUMS"
python3 - "$task_tmp" "$artifact" "$install_dir" <<'PY'
import hashlib, pathlib, sys, zipfile
root, name, dest = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
expected = next(line.split()[0] for line in (root / 'SHA256SUMS').read_text().splitlines() if line.split()[-1] == name)
actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit('Terraform checksum mismatch; refusing to install')
dest.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(root / name) as archive:
    (dest / 'terraform').write_bytes(archive.read('terraform'))
(dest / 'terraform').chmod(0o755)
print(f'Checksum verified. Installed {dest / "terraform"}')
PY
"$install_dir/terraform" version
