ARG BASE_IMAGE=e2eteam/busybox:1.24
FROM $BASE_IMAGE
ADD net.exe /net
USER ContainerAdministrator
RUN powershell -Command \
mkdir /dev/null; \
cp CURL.exe /busybox/curl.exe; \
cp CURL.LIC /busybox/CURL.LIC;\
rm CURL.exe;rm CURL.LIC
USER ContainerUser
