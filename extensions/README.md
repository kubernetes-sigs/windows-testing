Extensions used for Windows Release Test Clusters.

Master extension: used to taint master node after provision.

Agent node extension: used to create missing dirs ( c:/temp ) that some tests require
as well as pull all required test images. Pulling of images is necessary as
a way to reduce test flakes due to timeouts (Pods may not spawn in the required 5 minutes).

