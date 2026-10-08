#!/usr/bin/env bash
# Publishes a desktop build to the downloads site (see downloads.yaml).
# Needs AWS credentials (the deploy user) in the environment.
# Usage: publish-downloads.sh <build-number> <dir with Notchman-Setup.exe, Notchman.dmg, Notchman-Intel.dmg>
set -euo pipefail
BUILD="$1"; DIR="$2"
STACK=notchman-downloads
here="$(cd "$(dirname "$0")" && pwd)"

aws cloudformation deploy --stack-name "$STACK" --template-file "$here/downloads.yaml" --no-fail-on-empty-changeset
output() { aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
BUCKET=$(output BucketName); DIST=$(output DistributionId); URL=$(output DownloadsUrl)

TAG="desktop-$BUILD"; VERSION="0.1.$BUILD"
put() { # file, key, content type, cache-control
  aws s3 cp "$1" "s3://$BUCKET/$2" --content-type "$3" --cache-control "$4" \
    --content-disposition "attachment; filename=\"$(basename "$2")\"" --only-show-errors
}
for name in Notchman-Setup.exe Notchman.dmg Notchman-Intel.dmg; do
  file="$DIR/$name"
  [ -f "$file" ] || { echo "missing $file"; exit 1; }
  case "$name" in *.exe) type=application/vnd.microsoft.portable-executable;; *) type=application/x-apple-diskimage;; esac
  put "$file" "$TAG/$name" "$type" "public, max-age=31536000, immutable"
  put "$file" "latest/$name" "$type" "public, max-age=300"
done

cat > "$DIR/latest.json" <<JSON
{"version":"$VERSION","tag":"$TAG","files":{
"Notchman-Setup.exe":"$URL/$TAG/Notchman-Setup.exe",
"Notchman.dmg":"$URL/$TAG/Notchman.dmg",
"Notchman-Intel.dmg":"$URL/$TAG/Notchman-Intel.dmg"}}
JSON
aws s3 cp "$DIR/latest.json" "s3://$BUCKET/latest.json" --content-type application/json --cache-control "public, max-age=60" --only-show-errors
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/latest/*" "/latest.json" --query Invalidation.Id --output text

echo "Published $VERSION to $URL"
echo "- Windows: $URL/latest/Notchman-Setup.exe"
echo "- Mac (Apple silicon): $URL/latest/Notchman.dmg"
echo "- Mac (Intel): $URL/latest/Notchman-Intel.dmg"
