
# App Engine Java Guestbook

Copyright (C) 2010-2022 Google Inc.

Original Google App Engine Java sample, created in 2009, supporting Google App Engine Standard with Java8, Java11, and Java17 using Bundled Services
like App Engine Datastore API,and App Engine Users API.
By changine the <runtime> field in the appengine-web.xml, you can select with Java version to use to execute this Java EE Web App, using Servlet and JSP.
It demonstrates that code written back in 2009 with Google App Engine can still serve today with different JVMs.

[ae-docs]: https://cloud.google.com/appengine/docs/java/

## Prerequisites

### Download Maven

These samples use the [Apache Maven][maven] build system. Before getting
started, be sure to [download][maven-download] and [install][maven-install] it.
When you use Maven as described here, it will automatically download the needed
client libraries.

[maven]: https://maven.apache.org
[maven-download]: https://maven.apache.org/download.cgi
[maven-install]: https://maven.apache.org/install.html

### Create a Project in the Google Cloud Platform Console

If you haven't already created a project, create one now. Projects enable you to
manage all Google Cloud Platform resources for your app, including deployment,
access control, billing, and services.

1. Open the [Cloud Platform Console][cloud-console].
1. In the drop-down menu at the top, select **Create a project**.
1. Give your project a name.
1. Make a note of the project ID, which might be different from the project
   name. The project ID is used in commands and in configurations.

[cloud-console]: https://console.cloud.google.com/


### Setup

Use either:

* `gcloud init`
* `gcloud auth application-default login`

### Google Cloud Shell, Open JDK 11 setup:

To switch to an Open JDK 11 in a Cloud shell session, you can use:

```
   sudo update-alternatives --config java
   # And select the usr/lib/jvm/java-11-openjdk-amd64/bin/java version.
   # Also, set the JAVA_HOME variable for Maven to pick the correct JDK:
   export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
```


## Development differences between App Engine Java8 and Java11 Bundled Services

The only difference between a Java8 application and a Java11/Java17 application is in the `appengine-web.xml` file
where you need to define the Java11 runtime and declare you need the App Engine APIs:

```XML
<appengine-web-app xmlns="http://appengine.google.com/ns/1.0">
    <runtime>java11</runtime> <!-- or java17-->
    <app-engine-apis>true</app-engine-apis>
</appengine-web-app>
```

While the Java17 runtime is in Beta, in order to deploy the application, you can use the `beta` value for the `gcloudMode` Cloud SDK parameter like:

```shell
 mvn appengine:deploy -Dapp.deploy.gcloudMode=beta
```


Everything else should remain the same in terms of App Engine APIs access, WAR project packaging, and deployment.
This way, it should  be easy to migrate your existing GAE Java8 applications to GAE Java11.

## Maven
### Running locally

```shell
    mvn appengine:run
```

### Deploying

```shell
    mvn clean package appengine:deploy  -Dapp.deploy.gcloudMode=beta -Ddeploy.projectId=XXX
```
