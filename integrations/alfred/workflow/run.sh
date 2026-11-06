#!/bin/zsh
# Stage One for Alfred (SO-092): runs what the `st` Script Filter picked.
# The argument is "<verb><TAB><value>", e.g. "restore<TAB>Deep work".
arg="$1"
verb="${arg%%$'\t'*}"
value="${arg#*$'\t'}"
for p in /usr/local/bin/stage /opt/homebrew/bin/stage "/Applications/Stage One.app/Contents/Helpers/stage"; do
  [[ -x "$p" ]] && { stage="$p"; break; }
done
[[ -z "$stage" ]] && { echo "Stage One's stage command isn't installed"; exit 1; }
case "$verb" in
  restore) "$stage" restore "$value" ;;
  save)    "$stage" save "$value" ;;
  layout)  "$stage" layout "$value" ;;
  rewind)  "$stage" rewind --to "$value" ;;
  group)   "$stage" group "$value" ;;
  *)       echo "Unknown action: $verb"; exit 1 ;;
esac
