ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
USER ContainerAdministrator
EXPOSE 8080
ADD controller.exe controller
ENTRYPOINT ["/controller"]
