#! /bin/sh

set -eux
set -o pipefail

apk update

# Several Alpine releases ship more than one major, and `postgresql-client`
# is only a virtual provide. Pin the package from the image build.
apk add "${PG_CLIENT_PACKAGE:-postgresql-client}"

# gpg for optional encryption, aws-cli for S3, python3 for the Discord webhook.
# aws-cli comes from apk: `pip3 install awscli` fails on Alpine 3.19+ (PEP 668).
apk add gnupg aws-cli python3

# install go-cron
apk add curl
curl -L https://github.com/ivoronin/go-cron/releases/download/v0.0.5/go-cron_0.0.5_linux_${TARGETARCH}.tar.gz -O
tar xvf go-cron_0.0.5_linux_${TARGETARCH}.tar.gz
rm go-cron_0.0.5_linux_${TARGETARCH}.tar.gz
mv go-cron /usr/local/bin/go-cron
chmod u+x /usr/local/bin/go-cron
apk del curl

# cleanup
rm -rf /var/cache/apk/*
