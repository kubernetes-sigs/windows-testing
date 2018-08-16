ARG BASE_IMAGE=e2eteam/busybox:1.29
FROM $BASE_IMAGE
ADD net.exe /net
USER ContainerAdministrator
RUN powershell -Command \
mkdir /dev/null; \
cp /curl/CURL.exe /busybox/curl.exe; \
cp /curl/CURL.LIC /busybox/CURL.LIC;\
rm /curl/CURL.exe;rm /curl/CURL.LIC
USER ContainerUser
