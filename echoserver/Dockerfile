ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
ADD echoserver.exe /echoserver.exe
EXPOSE 9376
ENTRYPOINT ["/echoserver.exe"]