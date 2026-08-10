#!/bin/zsh
set -euo pipefail

PACKAGE_DIR=${0:A:h}
"$PACKAGE_DIR/scripts/uninstall.sh" "${1:-}"

echo
echo "삭제가 완료되었습니다. 설정과 로그는 보존되었습니다."
