#!/bin/bash
set -e

# Configuration
RUNTIME_DIR="target/runtime"
STAGING_DIR="target/appengine-staging"
QUICKSTART_WEB_XML="$STAGING_DIR/WEB-INF/quickstart-web.xml"
IMAGE_NAME="appengine-native-image"
REFLECT_CONFIG="reflect-config.json"

# Check for native-image
if ! command -v native-image &> /dev/null; then
    if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/native-image" ]; then
        export PATH="$JAVA_HOME/bin:$PATH"
    else
        echo "Error: native-image not found in PATH and JAVA_HOME is not set correctly."
        echo "Please set JAVA_HOME to your GraalVM directory or add it to your PATH."
        exit 1
    fi
fi

echo "Using native-image from: $(command -v native-image)"
native-image --version

# Discover jars early as they are needed for reflection config generation
echo "=== 0. Locating Runtime Jars ==="
MAIN_JAR_PATH=$(find "$RUNTIME_DIR" -name "runtime-main.jar" | head -n 1)
JETTY_IMPL_JAR_PATH=$(find "$RUNTIME_DIR" -name "runtime-impl-jetty121.jar" | head -n 1)
JETTY_SHARED_JAR_PATH=$(find "$RUNTIME_DIR" -name "runtime-shared-jetty121-ee11.jar" | head -n 1)

if [ -z "$MAIN_JAR_PATH" ] || [ -z "$JETTY_IMPL_JAR_PATH" ] || [ -z "$JETTY_SHARED_JAR_PATH" ]; then
    echo "Error: Could not find all 3 essential jars in $RUNTIME_DIR"
    exit 1
fi

echo "=== 1. Parsing $QUICKSTART_WEB_XML for classes ==="
if [ ! -f "$QUICKSTART_WEB_XML" ]; then
    echo "Error: $QUICKSTART_WEB_XML not found. Did you run 'mvn appengine:stage'?"
    exit 1
fi

# Extract from <servlet-class>
# Using perl because macOS grep doesn't support -P
SERVLET_CLASSES=$(perl -ne 'print "$1\n" while /<servlet-class[^>]*>(.*?)<\/servlet-class>/g' "$QUICKSTART_WEB_XML" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)

# Extract from org.eclipse.jetty.containerInitializers context-param
# This captures the main class AND any classes inside the interested=[], applicable=[], etc. arrays
INIT_CLASSES=$(perl -ne 'while (/ContainerInitializer\{(.*?)\}/g) { 
    $inner = $1; 
    # Extract the main class (first element)
    if ($inner =~ /^([^,]+)/) { print "$1\n"; }
    # Extract any classes inside brackets [class1,class2]
    while ($inner =~ /\[(.*?)\]/g) {
        @classes = split(/,/, $1);
        foreach $c (@classes) {
            $c =~ s/^\s+|\s+$//g;
            print "$c\n" if $c;
        }
    }
}' "$QUICKSTART_WEB_XML" | sort -u || true)

# Combine, clean up, and remove duplicates
ALL_CLASSES=$(echo -e "$SERVLET_CLASSES\n$INIT_CLASSES" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort -u)

echo "Found classes: "
echo "$ALL_CLASSES"

echo "=== 2. Generating $REFLECT_CONFIG ==="
echo "[" > "$REFLECT_CONFIG"
FIRST=true

# Dynamically discover all classes in the essential jars
# This ensures that both com.google.apphosting.runtime and any internal Jetty classes
# used by the adapter are properly registered for reflection.
# We filter out specific classes that are not used in EE11 and cause warnings due to missing legacy dependencies.
RUNTIME_CLASSES=""
for JAR in "$MAIN_JAR_PATH" "$JETTY_IMPL_JAR_PATH" "$JETTY_SHARED_JAR_PATH"; do
  # Strip leading slash if present, remove .class extension, and convert / to .
  JAR_CLASSES=$(jar tf "$JAR" | grep "\.class$" | sed 's/^\///;s/\.class$//;s/\//./g' | \
    grep -v "\.ee8\." | \
    grep -v "javax\.servlet\." | \
    grep -v "com\.google\.apphosting\.utils\.remoteapi\.RemoteApiServlet" | \
    grep -v "com\.google\.apphosting\.utils\.servlet\.DeferredTaskServlet" | \
    grep -v "com\.google\.apphosting\.utils\.servlet\.JdbcMySqlConnectionCleanupFilter" || true)
  RUNTIME_CLASSES="$RUNTIME_CLASSES\n$JAR_CLASSES"
done
RUNTIME_CLASSES=$(echo -e "$RUNTIME_CLASSES" | sort -u)

# Combine discovered classes with those from quickstart-web.xml
ALL_CLASSES_TO_REGISTER=$(echo -e "$ALL_CLASSES\n$RUNTIME_CLASSES" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort -u)

for CLASS in $ALL_CLASSES_TO_REGISTER; do
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo "," >> "$REFLECT_CONFIG"
  fi
  cat <<EOF >> "$REFLECT_CONFIG"
  {
    "name": "$CLASS",
    "allDeclaredConstructors": true,
    "allPublicConstructors": true,
    "allDeclaredMethods": true,
    "allPublicMethods": true,
    "allDeclaredFields": true,
    "allPublicFields": true,
    "allDeclaredClasses": true
  }
EOF
done
echo "]" >> "$REFLECT_CONFIG"

echo "=== 3. Cleaning Runtime and Constructing Classpath ==="
# Create a temporary directory to hold the keepers
TEMP_RUNTIME="target/runtime_temp"
mkdir -p "$TEMP_RUNTIME"
cp "$MAIN_JAR_PATH" "$JETTY_IMPL_JAR_PATH" "$JETTY_SHARED_JAR_PATH" "$TEMP_RUNTIME/"

# Wipe original runtime dir and move keepers back
rm -rf "$RUNTIME_DIR"
mv "$TEMP_RUNTIME" "$RUNTIME_DIR"

# Define the 3 jars for the CP
MAIN_JAR="$RUNTIME_DIR/runtime-main.jar"
JETTY_IMPL_JAR="$RUNTIME_DIR/runtime-impl-jetty121.jar"
JETTY_SHARED_JAR="$RUNTIME_DIR/runtime-shared-jetty121-ee11.jar"

STAGED_CLASSES="$STAGING_DIR/WEB-INF/classes"
STAGED_LIBS=$(find "$STAGING_DIR/WEB-INF/lib" -name "*.jar" | tr '\n' ':')

CP="$MAIN_JAR:$JETTY_IMPL_JAR:$JETTY_SHARED_JAR:$STAGED_CLASSES:$STAGED_LIBS"

echo "Classpath contains essential jars and staged app components."

echo "=== 4. Building Native Image ==="
# Find all XML, properties, and DTD files in the runtime jars to include them as resources
RESOURCE_CONFIG="resource-config.json"
echo '{"resources":{"includes":[' > "$RESOURCE_CONFIG"
FIRST_RES=true
for JAR in "$MAIN_JAR" "$JETTY_IMPL_JAR" "$JETTY_SHARED_JAR"; do
  JAR_RESOURCES=$(jar tf "$JAR" | grep -E "\.(xml|properties|dtd)$" || true)
  for RES in $JAR_RESOURCES; do
    if [ "$FIRST_RES" = true ]; then
      FIRST_RES=false
    else
      echo "," >> "$RESOURCE_CONFIG"
    fi
    echo "{\"pattern\":\"$(echo $RES | sed 's/^\///')\"}" >> "$RESOURCE_CONFIG"
  done
done
echo ']}}' >> "$RESOURCE_CONFIG"

native-image --no-fallback \
  -cp "$CP" \
  -H:Name="$IMAGE_NAME" \
  -H:ReflectionConfigurationFiles="$REFLECT_CONFIG" \
  -H:ResourceConfigurationFiles="$RESOURCE_CONFIG" \
  --initialize-at-build-time=org.slf4j \
  -H:+ReportExceptionStackTraces \
  --enable-url-protocols=http,https \
  -Djava.awt.headless=true \
  com.google.apphosting.runtime.JavaRuntimeMainWithDefaults

echo "=== 5. Testing Native Binary ==="
export GAE_PARTITION=dev
./"$IMAGE_NAME" --fixed_application_path="$STAGING_DIR" "$RUNTIME_DIR" > runtime.log 2>&1 &
RUN_PID=$!

echo "Waiting for 'INFO: JavaRuntime starting...' in logs..."
SUCCESS=false
# Wait up to 60 seconds
for i in {1..60}; do
  if grep -q "INFO: JavaRuntime starting..." runtime.log; then
    echo "Successfully detected start log!"
    SUCCESS=true
    break
  fi
  # Check for fatal errors
  if grep -i "fatal" runtime.log; then
    echo "Fatal error detected in logs!"
    cat runtime.log
    kill $RUN_PID || true
    exit 1
  fi
  # Check if process is still running
  if ! kill -0 $RUN_PID 2>/dev/null; then
    echo "Runtime process exited unexpectedly!"
    cat runtime.log
    exit 1
  fi
  sleep 1
done

kill $RUN_PID || true

if [ "$SUCCESS" = false ]; then
  echo "Timeout: Start log not found within 60 seconds"
  cat runtime.log
  exit 1
fi

echo "Native binary test passed!"

# Move to target for consistency
mv "$IMAGE_NAME" target/
echo "Final binary is available at: target/$IMAGE_NAME"
