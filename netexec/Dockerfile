FROM atuvenie/busybox:1.24
ADD netexec.exe /netexec.exe
EXPOSE 8080
EXPOSE 8081
RUN mkdir uploads
ENTRYPOINT ["/netexec.exe"]
