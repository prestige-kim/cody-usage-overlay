#!/bin/zsh
set -uo pipefail

PACKAGE_DIR=${0:A:h}
if [[ -x "$PACKAGE_DIR/scripts/doctor.sh" ]]; then
  "$PACKAGE_DIR/scripts/doctor.sh" || STATUS=$?
else
  "$PACKAGE_DIR/doctor.sh" || STATUS=$?
fi

echo
echo "진단이 끝났습니다. 이 창을 닫아도 됩니다."
read -k 1 "?아무 키나 누르면 종료합니다."
exit ${STATUS:-0}
