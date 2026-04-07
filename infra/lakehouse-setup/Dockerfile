FROM alpine/terragrunt:1.7.0

RUN apk add --no-cache postgresql-client curl openjdk17-jre-headless && \
    curl -L https://repo1.maven.org/maven2/io/trino/trino-cli/451/trino-cli-451-executable.jar -o /usr/local/bin/trino && \
    chmod +x /usr/local/bin/trino