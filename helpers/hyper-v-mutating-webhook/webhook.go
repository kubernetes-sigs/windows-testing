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

	corev1 "k8s.io/api/core/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

// +kubebuilder:webhook:path=/mutate-v1-pod,mutating=true,failurePolicy=fail,groups="",resources=pods,verbs=create;update,versions=v1,name=mpod.kb.io,admissionReviewVersions={v1},sideEffects=None

var (
	webhookLogger    = ctrl.Log.WithName("webhook")
	runtimeClassName = "runhcs-wcow-hypervisor"
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

	mutatePod := true

	// Don't apply hyper-v runtime class to hostProcess pods
	if isHostProcessPod(pod) {
		mutatePod = false
	}
	
	// Don't apply hyper-v runtime class for linux pods that are explicitly labeled, as this is a windows only supported runtimeclass
	if osLabel, ok := pod.Spec.NodeSelector["kubernetes.io/os"]; ok && osLabel == "linux" {
		mutatePod = false
	}

	if mutatePod {
		podName := pod.Name
		webhookLogger.Info(fmt.Sprintf("Pod %s is being mutated", podName))

		if pod.Annotations == nil {
			pod.Annotations = make(map[string]string)
		}

		pod.Annotations["hyperv-runtimeclass-mutating-webhook"] = "mutated"

		// e2e.test does not add nodeSelector fields to pods it schedules so this will
		// add the hyperv runtime class to ALL pods scheduled to the cluster.
		if pod.Spec.RuntimeClassName == nil {
			pod.Spec.RuntimeClassName = &runtimeClassName
		}
	}

	marshaledPod, err := json.Marshal(pod)
	if err != nil {
		return admission.Errored(http.StatusInternalServerError, err)
	}

	return admission.PatchResponseFromRaw(req.Object.Raw, marshaledPod)
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
