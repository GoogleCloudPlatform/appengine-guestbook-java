
# App Engine Java Guestbook

Copyright (C) 2010-2026 Google Inc.

Original Google App Engine Java sample, created in 2009, supporting Google App Engine Standard with Java8, Java11, Java17, Java21 and Java25using Bundled Services
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

```

## Development differences between App Engine Java8/11/17/21/25 Bundled Services

The only difference between a Java8/11/17/21 application and a Java25 application is in the `appengine-web.xml` file
where you need to define the Java25 runtime, use EE8 javax APIs and declare you need the App Engine APIs:

```XML
<appengine-web-app xmlns="http://appengine.google.com/ns/1.0">
    <runtime>java25</runtime>
    <app-engine-apis>true</app-engine-apis>
    <system-properties>
        <property name="appengine.use.EE8" value="true"/>
    </system-properties>
</appengine-web-app>
```

For a Java25 usage with the new  jakarta.servlet API,
you need to define the Java25 runtime which default to Jakarta EE11, declare you need the App Engine APIs:

```XML
<appengine-web-app xmlns="http://appengine.google.com/ns/1.0">
    <runtime>java25</runtime>
    <app-engine-apis>true</app-engine-apis>
    <system-properties>
        <property name="java.util.logging.config.file" value="WEB-INF/logging.properties"/>
    </system-properties>
</appengine-web-app>
```



Everything else should remain the same in terms of App Engine APIs access, WAR project packaging, and deployment.
This way, it should  be easy to migrate your existing GAE Java8 applications to GAE Java11 or Java17 or Java21 or Java25.

## Maven
### Running locally

```shell
    mvn appengine:run
```

### Deploying

```shell
    mvn clean package appengine:deploy  -Ddeploy.projectId=XXXX
```
