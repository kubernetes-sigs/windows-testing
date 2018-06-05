ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
ADD main.exe webhook.exe
ENTRYPOINT ["/webhook.exe"]
