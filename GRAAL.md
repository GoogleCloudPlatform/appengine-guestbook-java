# GraalVM JDK 25 Support for App Engine Jakarta APIs

This project supports building a GraalVM Native Image for the Jakarta EE 11 App Engine runtime using JDK 25.

## Prerequisites

- **GraalVM JDK 25**: Download and install GraalVM with JDK 25 support.
- **Native Image**: Ensure the `native-image` tool is available in your GraalVM distribution.
- **Maven**: Standard Maven build environment.

## Project Structure

- `jakarta_apis/pom.xml`: Contains the `native` profile which automates the build and test process.
- `jakarta_apis/build_native.sh`: The core script for generating reflection/resource config, building the image, and preparing deployment.
- `jakarta_apis/cloudbuild.yaml`: Automated build and deployment for Google Cloud Build.
- `jakarta_apis/Dockerfile`: Build environment for local Docker-based Linux builds.
- `.github/workflows/graalvm-jdk25.yml`: Automated CI pipeline for producing the Linux binary.

## Local Build & Test

The build process is fully integrated into Maven. To build the native image locally:

1. **Set your environment**:
   ```bash
   export JAVA_HOME=/path/to/graalvm-jdk-25
   export PATH=$JAVA_HOME/bin:$PATH
   ```

2. **Run the full build sequence**:
   ```bash
   cd jakarta_apis
   mvn clean package appengine:stage install -Pnative -DskipTests
   ```

The `install` phase with the `-Pnative` profile will automatically trigger `build_native.sh`, which compiles and tests the binary.

## Building on macOS / Windows (Docker)

If you are on macOS or Windows and want to produce a **Linux-native binary**, you can use Docker.

1.  **Build the GraalVM JDK 25 Image**:
    ```bash
    cd jakarta_apis
    docker build -t appengine-graal-build .
    ```

2.  **Run the Build Container**:
    Mount the current directory to `/app` inside the container. The final binary will be written back to your local `target/` directory.
    ```bash
    docker run --rm -v "$(pwd)":/app appengine-graal-build
    ```

After the container finishes, the binary will be at `jakarta_apis/target/appengine-native-image`.

## Google Cloud Build & Deploy

You can automate the entire build and deployment process using Google Cloud Build. This process is **dynamic** and uses your `pom.xml` as the single source of truth for deployment parameters (`projectId`, `version`, `promote`).

1.  **Prerequisites**:
    -   Install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install).
    -   Ensure the Cloud Build and App Engine Admin APIs are enabled in your project.
    -   Authenticate and set your project:
        ```bash
        gcloud auth login
        gcloud config set project [YOUR_PROJECT_ID]
        ```

2.  **Submit the Build**: From the **project root**, run:
    ```bash
    gcloud builds submit jakarta_apis --config jakarta_apis/cloudbuild.yaml
    ```

Cloud Build will automatically:
-   Spin up a high-CPU build worker (40-minute timeout).
-   Parse your `projectId`, `version`, and `promote` settings from `pom.xml`.
-   Build the Linux-native binary using GraalVM JDK 25.
-   Inject the native entrypoint into `app.yaml`.
-   Deploy the resulting binary to App Engine using the extracted parameters.

## How it Works

1. **Staging**: The `appengine:stage` command generates `target/appengine-staging/WEB-INF/quickstart-web.xml`. This file contains a pre-scanned list of all servlets, initializers, and JSP classes.
2. **Deep Reflection Discovery**: `build_native.sh` uses a multi-layered discovery process to build the `reflect-config.json`:
   - **Deep XML Parsing**: Uses `perl` to extract not just main classes, but also classes hidden in `interested`, `applicable`, and `annotated` arrays within the Jetty `ContainerInitializers`.
   - **Full Runtime & SDK Discovery**: Automatically extracts **every class** from the three essential runtime jars AND the user-facing `appengine-api-1.0-sdk` jar.
   - **Legacy Filtering**: Automatically filters out classes related to `.ee8.` and `javax.servlet.` namespaces, as well as specific legacy utility classes.
   - **Full Access Registration**: All discovered classes are registered with `allDeclaredConstructors`, `allDeclaredMethods`, and `allDeclaredFields` set to `true`.
3. **Resource Discovery**: Automatically scans the jars for all `.xml`, `.properties`, `.dtd`, `.xsd`, and `.txt` files. These are registered in `resource-config.json` to ensure configuration like `catalog-ee11.xml` is available inside the binary.
4. **Runtime Assembly**: The script unpacks the `runtime-deployment` zip and keeps only the **3 essential jars**: `runtime-main.jar`, `runtime-impl-jetty121.jar`, and `runtime-shared-jetty121-ee11.jar`.
5. **Native Compilation**: GraalVM's `native-image` compiles the application using `com.google.apphosting.runtime.JavaRuntimeMainWithDefaults` as the entry point. It includes **G1GC** (`--gc=G1`) and broad build-time initialization for `org.slf4j`, `org.eclipse.jetty`, and App Engine packages.
6. **Verification**: The script automatically starts the binary with `GAE_PARTITION=dev` and verifies that it reaches the "JavaRuntime starting..." state without fatal errors.
7. **Deployment Preparation**: The script parses `pom.xml` to extract deployment settings and generates a `target/appengine-staging/deploy.sh` script. It also injects the native entrypoint into the staged `app.yaml`.

## Production Deployment

The resulting binary (`appengine-native-image`) is a standalone Linux executable. 

- **Environment Variables**: The runtime environment provides variables like `PORT` and `GAE_PARTITION`. 
- **Heap Management**: The binary respects standard flags like `-Xmx`. By default, App Engine Java runtimes target a heap size of ~80% of available instance memory.
- **Execution**: To run manually in a production-like environment:
  ```bash
  ./appengine-native-image -Xmx512m --fixed_application_path=/path/to/staged/app /path/to/runtime
  ```

## Troubleshooting

- **Grep on macOS**: The script uses `perl` for pattern extraction to avoid incompatibilities with the default macOS `grep`.
- **Cloud SDK hang**: The `appengine-maven-plugin` is configured to use a local `cloudSdkHome` and has `downloadCloudSdk` set to `false`.
- **Classpath Errors**: If `ClassNotFoundException` occurs, ensure the class is added to the `ALL_CLASSES_WITH_RUNTIME` list in `build_native.sh`.

## Application-Specific Customization

The App Engine runtime itself is now fully configured. Any remaining tasks are **web application specific**. If your app uses additional libraries (like Hibernate or Jackson), you may need to add those classes to the reflection configuration in `build_native.sh`.
