ARG BASE_IMAGE=e2eteam/busybox:1.29
FROM $BASE_IMAGE
ADD netexec.exe /netexec.exe
EXPOSE 8080
EXPOSE 8081
RUN mkdir uploads
ENTRYPOINT ["/netexec.exe"]
