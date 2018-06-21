ARG BASE_IMAGE=e2eteam/busybox:1.24
FROM $BASE_IMAGE

# this might take a while. fetching Java takes longer since it's hosted on github.
ENV JAVA_URL "http://github.com/ojdkbuild/ojdkbuild/releases/download/1.8.0.171-1/java-1.8.0-openjdk-1.8.0.171-1.b10.ojdkbuild.windows.x86_64.zip"
ADD $JAVA_URL /

RUN mkdir C:\java
RUN powershell -Command "Expand-Archive -Path C:\java-1.8.0-openjdk-1.8.0.171-1.b10.ojdkbuild.windows.x86_64.zip -DestinationPath C:\java -Force" &&\
powershell -Command "Rename-Item -Path C:\java\java-1.8.0-openjdk-1.8.0.171-1.b10.ojdkbuild.windows.x86_64 -NewName C:\java\java-1.8.0" &&\
del C:\java-1.8.0-openjdk-1.8.0.171-1.b10.ojdkbuild.windows.x86_64.zip

# set Java related env variables.
USER ContainerAdministrator
RUN setx /M PATH "C:\java\java-1.8.0\bin;%PATH%"
ENV _JAVA_OPTIONS "-Xmx512M -Xms512m"
ENV JAVA_HOME "C:\java\java-1.8.0"
USER ContainerUser
