/*
Copyright 2023.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	corev1 "k8s.io/api/core/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

// +kubebuilder:webhook:path=/mutate-v1-pod,mutating=true,failurePolicy=fail,groups="",resources=pods,verbs=create;update,versions=v1,name=mpod.kb.io,admissionReviewVersions={v1},sideEffects=None

var (
	webhookLogger    = ctrl.Log.WithName("webhook")
	runtimeClassName = getRuntimeClassName()
)

type podUpdater struct {
	Client  client.Client
	decoder admission.Decoder
}

func (pu *podUpdater) Handle(ctx context.Context, req admission.Request) admission.Response {
	pod := &corev1.Pod{}
	err := pu.decoder.Decode(req, pod)
	if err != nil {
		return admission.Errored(http.StatusBadRequest, err)
	}

	if !shouldMutatePod(pod) {
		return admission.Allowed("")
	}

	webhookLogger.Info(fmt.Sprintf("Pod %s is being mutated", pod.Name))

	marshaledPod, err := mutatePodRaw(req.Object.Raw, runtimeClassName)
	if err != nil {
		return admission.Errored(http.StatusInternalServerError, err)
	}

	return admission.PatchResponseFromRaw(req.Object.Raw, marshaledPod)
}

// shouldMutatePod reports whether the hyper-v runtime class should be injected
// into the given pod. It returns false for pods that are incompatible with
// Hyper-V isolation (hostProcess, hostNetwork), explicitly Linux pods, and pods
// carrying a custom nodeSelector with no kubernetes.io/os key (likely test
// fixtures whose resource accounting would break if overhead were injected).
func shouldMutatePod(pod *corev1.Pod) bool {
	// Don't apply hyper-v runtime class to hostProcess pods
	if isHostProcessPod(pod) {
		return false
	}

	// Don't apply hyper-v runtime class to hostNetwork pods, as Hyper-V
	// isolation runs containers inside a utility VM with its own network
	// namespace which is incompatible with host networking
	if pod.Spec.HostNetwork {
		return false
	}

	// Don't apply hyper-v runtime class for linux pods that are explicitly labeled, as this is a windows only supported runtimeclass
	if osLabel, ok := pod.Spec.NodeSelector["kubernetes.io/os"]; ok && osLabel == "linux" {
		return false
	}

	// Don't apply hyper-v runtime class for pods that have custom nodeSelectors
	// but no kubernetes.io/os selector. These are likely test fixture pods
	// (e.g., ResourceQuota tests with unsatisfiable selectors) that are not
	// intended to run as Windows workloads. Injecting overhead into them would
	// break resource accounting in those tests.
	if _, hasOS := pod.Spec.NodeSelector["kubernetes.io/os"]; !hasOS && len(pod.Spec.NodeSelector) > 0 {
		return false
	}

	return true
}

// mutatePodRaw injects the hyper-v mutation annotation and, when unset, the
// runtimeClassName into the raw pod JSON, preserving all other fields. It
// operates on the raw request bytes rather than a re-marshaled typed Pod so that
// fields newer than the vendored k8s.io/api (e.g. container-level
// restartPolicyRules) are not dropped.
func mutatePodRaw(rawObject []byte, runtimeClassName string) ([]byte, error) {
	raw := map[string]interface{}{}
	if err := json.Unmarshal(rawObject, &raw); err != nil {
		return nil, err
	}

	metadata, _ := raw["metadata"].(map[string]interface{})
	if metadata == nil {
		metadata = map[string]interface{}{}
		raw["metadata"] = metadata
	}
	annotations, _ := metadata["annotations"].(map[string]interface{})
	if annotations == nil {
		annotations = map[string]interface{}{}
		metadata["annotations"] = annotations
	}
	annotations["hyperv-runtimeclass-mutating-webhook"] = "mutated"

	spec, _ := raw["spec"].(map[string]interface{})
	if spec == nil {
		spec = map[string]interface{}{}
		raw["spec"] = spec
	}
	// e2e.test does not add nodeSelector fields to pods it schedules so this
	// will add the hyperv runtime class to ALL pods scheduled to the cluster.
	if v, ok := spec["runtimeClassName"]; !ok || v == nil || v == "" {
		spec["runtimeClassName"] = runtimeClassName
	}

	return json.Marshal(raw)
}

// InjectDecoder injects a decoder into the podUpdater
func (pu *podUpdater) InjectDecoder(d admission.Decoder) error {
	pu.decoder = d
	return nil
}

func isHostProcessPod(p *corev1.Pod) bool {
	// Check if hostProcess is set at pod level
	if p.Spec.SecurityContext != nil && p.Spec.SecurityContext.WindowsOptions != nil && p.Spec.SecurityContext.WindowsOptions.HostProcess != nil {
		return *p.Spec.SecurityContext.WindowsOptions.HostProcess
	}

	// Check if hostProcess is set for any containers
	if p.Spec.Containers != nil {
		for _, c := range p.Spec.Containers {
			if c.SecurityContext != nil && c.SecurityContext.WindowsOptions != nil && c.SecurityContext.WindowsOptions.HostProcess != nil && *c.SecurityContext.WindowsOptions.HostProcess {
				return true
			}
		}
	}

	// Check if hostProcess is set for any init containers
	if p.Spec.InitContainers != nil {
		for _, c := range p.Spec.InitContainers {
			if c.SecurityContext != nil && c.SecurityContext.WindowsOptions != nil && c.SecurityContext.WindowsOptions.HostProcess != nil && *c.SecurityContext.WindowsOptions.HostProcess {
				return true
			}
		}
	}

	return false
}

func getRuntimeClassName() string {
	if v := os.Getenv("RUNTIME_CLASS_NAME"); v != "" {
		return v
	}
	return "runhcs-wcow-hypervisor"
}
