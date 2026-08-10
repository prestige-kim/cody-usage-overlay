#!/bin/zsh
set -euo pipefail

PACKAGE_DIR=${0:A:h}
"$PACKAGE_DIR/scripts/install.sh"

echo
echo "설치가 완료되었습니다. 이 창을 닫아도 됩니다."
