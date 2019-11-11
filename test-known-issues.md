The intention of this document is to track Conformance tests that are temporarily exluded from test runs and 
to document the reason behind this.

08/22/2019

* [sig-cli] Kubectl client [k8s.io] Guestbook application should create and stop a working application [Conformance]
  * Reason: https://github.com/kubernetes/kubernetes/issues/80534
  * Proposed fix: TBD

07/28/2019

Excluded from all master runs:
* ~~[sig-cli] Kubectl client [k8s.io] Kubectl logs should be able to retrieve and filter logs [Conformance]~~
  * Reason: https://github.com/kubernetes/kubernetes/issues/80265
  * Proposed fix: https://github.com/kubernetes/kubernetes/pull/80516
  * Short summary of fix: Changing the test to use a image that is works well for both Linux and Windows.
  * NOTE: Fix merged, no longer excluded
* [sig-cli] Kubectl client [k8s.io] Guestbook application should create and stop a working application [Conformance]
  * Reason: https://github.com/kubernetes/kubernetes/issues/80534
  * Proposed fix: TBD
