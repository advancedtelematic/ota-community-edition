FROM alpine

COPY install-deps.sh /tmp/

RUN apk --no-cache add bash coreutils curl make openssh-client openssl jq httpie python zip && \
	/tmp/install-deps.sh && rm /tmp/install-deps.sh
