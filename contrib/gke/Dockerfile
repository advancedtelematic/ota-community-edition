FROM alpine

COPY install-deps.sh /tmp/

RUN apk --no-cache add openssh-client curl jq httpie python && \
	/tmp/install-deps.sh && rm /tmp/install-deps.sh
