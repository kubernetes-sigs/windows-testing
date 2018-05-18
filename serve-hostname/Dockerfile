ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
COPY serve_hostname.exe /
EXPOSE 9376
ENTRYPOINT ["/serve_hostname.exe"]
