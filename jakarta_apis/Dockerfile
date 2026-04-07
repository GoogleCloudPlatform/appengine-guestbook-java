# Use Oracle GraalVM for JDK 25
# (Ensure this matches the available image or use a generic Ubuntu and install manually)
FROM container-registry.oracle.com/graalvm/native-image:21 AS build

# Since we need JDK 25, we download it manually if not yet in the official image
RUN microdnf install -y tar gzip && \
    curl -L https://download.oracle.com/graalvm/25/latest/graalvm-jdk-25_linux-x64_bin.tar.gz -o graalvm.tar.gz && \
    mkdir -p /opt/graalvm && \
    tar -xzf graalvm.tar.gz -C /opt/graalvm --strip-components=1 && \
    rm graalvm.tar.gz

ENV JAVA_HOME=/opt/graalvm
ENV PATH=$JAVA_HOME/bin:$PATH

# Install Maven
RUN microdnf install -y maven

WORKDIR /app

# The build script expects target/appengine-staging and target/runtime to exist
# So we run the maven staging separately or mount the already-staged dir.
CMD ["/bin/bash", "-c", "mvn clean package appengine:stage install -Pnative -DskipTests"]
