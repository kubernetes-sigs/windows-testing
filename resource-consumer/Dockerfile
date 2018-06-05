ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
USER ContainerAdministrator
EXPOSE 8080
ADD ./consume-memory/consume-memory.exe ./consume-memory/consume-memory.exe
ADD ./consume-cpu/consume_cpu_windows.exe ./consume-cpu/consume-cpu.exe
ADD resource_consumer.exe resource-consumer
ENTRYPOINT ["/resource-consumer"]
