# GraalVM JDK 25 Support for App Engine Jakarta APIs

This project supports building a GraalVM Native Image for the Jakarta EE 11 App Engine runtime using JDK 25.

## Prerequisites

- **GraalVM JDK 25**: Download and install GraalVM with JDK 25 support.
- **Native Image**: Ensure the `native-image` tool is available in your GraalVM distribution.
- **Maven**: Standard Maven build environment.

## Project Structure

- `jakarta_apis/pom.xml`: Contains the `native` profile which automates the build and test process.
- `jakarta_apis/build_native.sh`: The core script for generating reflection config, building the image, and verifying it.
- `.github/workflows/graalvm-jdk25.yml`: Automated CI/CD pipeline for producing the Linux binary.

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

## How it Works

1. **Staging**: The `appengine:stage` command generates `target/appengine-staging/WEB-INF/quickstart-web.xml`. This file contains a pre-scanned list of all servlets, initializers, and JSP classes.
2. **Deep Reflection Discovery**: `build_native.sh` uses a multi-layered discovery process to build the `reflect-config.json`:
   - **Deep XML Parsing**: Uses `perl` to extract not just main classes, but also classes hidden in `interested`, `applicable`, and `annotated` arrays within the Jetty `ContainerInitializers`.
   - **Full Runtime Discovery**: Automatically extracts **every class** from the three essential runtime jars. This ensures that internal App Engine and Jetty classes (like `PathSpecSet`) that are loaded via reflection are fully accessible.
   - **Legacy Filtering**: Automatically filters out classes related to `.ee8.` and `javax.servlet.` namespaces. These are legacy components not used in the Jakarta EE 11 runtime, and filtering them prevents build-time warnings and reduces the reflection map size.
   - **Full Access Registration**: All discovered classes are registered with `allDeclaredConstructors`, `allDeclaredMethods`, and `allDeclaredFields` set to `true` to prevent "missing method" errors at runtime.
3. **Resource Discovery**: Automatically scans the essential jars for all `.xml`, `.properties`, and `.dtd` files. These are registered in `resource-config.json` to ensure the Jetty/App Engine configuration (like `catalog-ee11.xml`) is available inside the binary.
4. **Runtime Assembly**: The script unpacks the `runtime-deployment` zip and keeps only the **3 essential jars**:
   - `runtime-main.jar`
   - `runtime-impl-jetty121.jar`
   - `runtime-shared-jetty121-ee11.jar`
4. **Native Compilation**: GraalVM's `native-image` compiles the application into a standalone binary using `com.google.apphosting.runtime.JavaRuntimeMainWithDefaults` as the entry point. It also includes several SLF4J classes in the build-time initialization list.
5. **Verification**: The script automatically starts the binary with `GAE_PARTITION=dev` and verifies that it reaches the "JavaRuntime starting..." state without fatal errors.
6. **Output**: The final binary is moved to the `target/` directory for consistency across build platforms.

## Troubleshooting

- **Grep on macOS**: The script uses `perl` for pattern extraction to avoid incompatibilities with the default macOS `grep`.
- **Cloud SDK hang**: The `appengine-maven-plugin` is configured to use a local `cloudSdkHome` and has `downloadCloudSdk` set to `false` to prevent stalls during staging.
- **Classpath Errors**: If `ClassNotFoundException` occurs, ensure the class is added to the `ALL_CLASSES_WITH_RUNTIME` list in `build_native.sh`.

## GitHub Actions

The CI pipeline automatically builds and tests the native image on every push to the `main` branch. The resulting Linux binary is uploaded as a workflow artifact.
## Application-Specific Customization

The App Engine runtime itself is now fully configured for GraalVM. Any remaining tasks are **web application specific**, not App Engine specific. This means that if your application uses additional libraries (like Hibernate, Jackson, or custom reflection-based logic), you may need to add those classes to the reflection configuration.

### How to Handle Custom Application Behavior

If you find that your native binary fails at runtime with a `ClassNotFoundException` or `NoSuchMethodException` related to your own code or your dependencies, follow these steps:

1.  **Identify the Class**: Look at the stack trace to find the class that failed to load.
2.  **Update `build_native.sh`**: Add the class name to the `ALL_CLASSES_WITH_RUNTIME` list in the `jakarta_apis/build_native.sh` script.
    ```bash
    # Example: Adding a custom model class or a library-specific adapter
    ALL_CLASSES_WITH_RUNTIME="$ALL_CLASSES com.example.MyModel com.thirdparty.Adapter"
    ```
3.  **Rebuild**: Run the `mvn install -Pnative` command again. The script will automatically update the `reflect-config.json` and rebuild the binary.

### Using the Build-Time Initialization

If you encounter an `UnsupportedFeatureException` during compilation (similar to the SLF4J errors we resolved), you can add the class to the `--initialize-at-build-time` list in `build_native.sh`. This is typically needed for classes that initialize static state that GraalVM needs to capture at build time.

---

## High-Level Compiler Configuration

The GraalVM native image configuration is designed to bridge the gap between a dynamic web container and a static native binary.

### Compilation Strategy (`native-image`)

The compilation process is configured to be **strictly non-fallback** (`--no-fallback`), ensuring the resulting binary is a true standalone executable. The strategy focuses on:

1.  **Selective Build-Time Initialization**: Several core logging and utility classes (specifically from SLF4J like `LoggerFactory`, `NOPMDCAdapter`, and `BasicMDCAdapter`) are initialized at **build time**. This embeds their pre-computed state into the binary, which is essential for performance and avoiding complex runtime class-loading issues.
2.  **Dynamic Reflection Mapping**: Since web containers like Jetty rely heavily on reflection to instantiate servlets and filters, the compiler is provided with a dynamically generated `reflect-config.json`. This "map" tells the compiler exactly which classes must be kept and remain reflectively accessible, even if they aren't explicitly referenced in the code's static call tree.
3.  **Refined Runtime Classpath**: The compiler uses a minimalist runtime assembly. By unpacking the full App Engine `runtime-deployment` and discarding everything except the three essential jars (`runtime-main`, `runtime-impl-jetty121`, and `runtime-shared-jetty121-ee11`), we reduce the "noise" and analysis time for the GraalVM compiler.

### Important Classes

The successful execution of the native binary depends on the inclusion and proper configuration of several critical classes:

*   **Entry Point (`JavaRuntimeMainWithDefaults`)**: This is the heart of the executable. It's responsible for parsing environment variables (like `PORT` and `GAE_PARTITION`) and bootstrapping the App Engine environment with sensible production defaults.
*   **Runtime Factories**:
    *   **`JavaRuntimeFactory`**: The core factory that the entry point uses to instantiate the App Engine runtime environment.
    *   **`JettyServletEngineAdapter`**: The specific adapter that hooks the App Engine runtime into the Jetty 12.1 engine. Both of these are loaded via reflection, making their presence in the `reflect-config.json` mandatory.
*   **Web Components (The "Dynamic" Set)**:
    *   **Servlets**: Application-specific classes like `GuestbookServlet` and `SignGuestbookServlet`.
    *   **Initializers**: Container-level classes like `JettyJasperInitializer` (for JSP support) and `TldScanner`.
    *   **Generated JSP Classes**: Classes like `org.apache.jsp.guestbook_jsp` that are generated by the Jetty Quickstart generator during the staging phase.
