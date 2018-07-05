ARG BASE_IMAGE=e2eteam/java:openjdk-8-jre
FROM $BASE_IMAGE

# download the Kubernetes Hazelcast bootstrapper.
ADD https://github.com/pires/hazelcast-kubernetes-bootstrapper/releases/download/3.8_1/hazelcast-kubernetes-bootstrapper-3.8_1.jar /bootstrapper.jar

# expose port for Hazelcast.
EXPOSE 5701/tcp

ENTRYPOINT ["java", "-jar", "/bootstrapper.jar"]
