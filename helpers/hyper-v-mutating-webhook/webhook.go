// based on https://github.com/kubernetes-sigs/controller-runtime/tree/master/examples/builtins
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

// +kubebuilder:webhook:path=/mutate-v1-pod,mutating=true,failurePolicy=fail,groups="",resources=pods,verbs=create;update,versions=v1,name=mpod.kb.io

var (
	webhookLogger = ctrl.Log.WithName("webhook")
	windows2019   = "windows-2019"
	windows2004   = "windows-2004"
)

// podUpdater updates Pods
type podUpdater struct {
	Client  client.Client
	decoder *admission.Decoder
}

// podUpdater looks for pods with a nodeSelector kubernetes.io/os=windows and updates them by
// - adding a runtimeClassName
// - updating container image fields to make them target single-arch images
func (a *podUpdater) Handle(ctx context.Context, req admission.Request) admission.Response {
	pod := &corev1.Pod{}

	err := a.decoder.Decode(req, pod)
	if err != nil {
		return admission.Errored(http.StatusBadRequest, err)
	}

	podName := pod.Name

	// e2e.test does not add nodeSelector fields to pods it schedules so this will
	// update image fields for ALL pods scheduled to the cluster.
	webhookLogger.Info(fmt.Sprintf("Adding '%s' runtimeClass to containers in pod '%s'", windows2004, podName))
	pod.Spec.RuntimeClassName = &windows2004

	containers := []corev1.Container{}
	for _, c := range pod.Spec.Containers {
		c.Image = c.Image + "-windows-amd64-2004"
		containers = append(containers, c)
	}
	pod.Spec.Containers = containers

	containers = []corev1.Container{}
	for _, c := range pod.Spec.InitContainers {
		c.Image = c.Image + "-windows-amd64-2004"
		containers = append(containers, c)
	}
	pod.Spec.InitContainers = containers

	marshaledPod, err := json.Marshal(pod)
	if err != nil {
		return admission.Errored(http.StatusInternalServerError, err)
	}

	return admission.PatchResponseFromRaw(req.Object.Raw, marshaledPod)
}

// podUpdater implements admission.DecoderInjector.
// A decoder will be automatically injected.

// InjectDecoder injects the decoder.
func (a *podUpdater) InjectDecoder(d *admission.Decoder) error {
	a.decoder = d
	return nil
}
