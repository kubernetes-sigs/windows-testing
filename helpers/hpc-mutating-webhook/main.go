/*
Copyright 2026 The Kubernetes Authors.

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
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"

	"github.com/urfave/cli/v2"

	jsonpatch "gomodules.xyz/jsonpatch/v2"
	admissionv1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"k8s.io/klog/v2"
)

// agnhostCmdRegex matches "agnhost" followed by whitespace or end of string
var agnhostCmdRegex = regexp.MustCompile(`^agnhost(\s+|$)`)

type Flags struct {
	certFile string
	keyFile  string
	port     int
}

func main() {
	if err := newApp().Run(os.Args); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func newApp() *cli.App {
	flags := &Flags{}
	cliFlags := []cli.Flag{
		&cli.StringFlag{
			Name:        "tls-cert-file",
			Usage:       "File containing the default x509 Certificate for HTTPS. (CA cert, if any, concatenated after server cert).",
			Destination: &flags.certFile,
			Required:    true,
		},
		&cli.StringFlag{
			Name:        "tls-private-key-file",
			Usage:       "File containing the default x509 private key matching --tls-cert-file.",
			Destination: &flags.keyFile,
			Required:    true,
		},
		&cli.IntFlag{
			Name:        "port",
			Usage:       "Secure port that the webhook listens on",
			Value:       443,
			Destination: &flags.port,
		},
	}
	// Additional flags can be added here if needed

	app := &cli.App{
		Name:            "hpc-mutating-webhook",
		Usage:           "hpc-mutating-webhook implements a mutating admission webhook for HPC containers.",
		ArgsUsage:       " ",
		HideHelpCommand: true,
		Flags:           cliFlags,
		Before: func(c *cli.Context) error {
			if c.Args().Len() > 0 {
				return fmt.Errorf("arguments not supported: %v", c.Args().Slice())
			}
			return nil
		},
		Action: func(c *cli.Context) error {
			server := &http.Server{
				Handler: newMux(),
				Addr:    fmt.Sprintf(":%d", flags.port),
			}
			klog.Infof("starting webhook server on %s", server.Addr)
			return server.ListenAndServeTLS(flags.certFile, flags.keyFile)
		},
	}

	return app
}

func newMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/mutate", serveHPCPodMutation)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, req *http.Request) {
		_, err := w.Write([]byte("ok"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, req *http.Request) {
		_, err := w.Write([]byte("ok"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	})
	return mux
}

func serveHPCPodMutation(w http.ResponseWriter, r *http.Request) {
	serve(w, r, mutateHPCPod)
}

// serve handles the http portion of a request prior to handing to an admit
// function.
func serve(w http.ResponseWriter, r *http.Request, admit func(admissionv1.AdmissionReview) *admissionv1.AdmissionResponse) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		klog.Error(err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// verify the content type is accurate
	contentType := r.Header.Get("Content-Type")
	if contentType != "application/json" {
		msg := fmt.Sprintf("contentType=%s, expected application/json", contentType)
		klog.Error(msg)
		http.Error(w, msg, http.StatusUnsupportedMediaType)
		return
	}

	klog.V(2).Infof("handling request: %s", body)

	requestedAdmissionReview, err := readAdmissionReview(body)
	if err != nil {
		msg := fmt.Sprintf("failed to read AdmissionReview from request body: %v", err)
		klog.Error(msg)
		http.Error(w, msg, http.StatusBadRequest)
		return
	}
	responseAdmissionReview := &admissionv1.AdmissionReview{}
	responseAdmissionReview.SetGroupVersionKind(requestedAdmissionReview.GroupVersionKind())
	responseAdmissionReview.Response = admit(*requestedAdmissionReview)
	if responseAdmissionReview.Response == nil {
		responseAdmissionReview.Response = &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: "internal error: admission handler returned nil response",
				Reason:  metav1.StatusReasonInternalError,
			},
		}
	}
	responseAdmissionReview.Response.UID = requestedAdmissionReview.Request.UID

	klog.V(2).Infof("sending response: %v", responseAdmissionReview)
	respBytes, err := json.Marshal(responseAdmissionReview)
	if err != nil {
		klog.Error(err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if _, err := w.Write(respBytes); err != nil {
		klog.Error(err)
	}
}

func readAdmissionReview(data []byte) (*admissionv1.AdmissionReview, error) {
	review := &admissionv1.AdmissionReview{}
	if err := json.Unmarshal(data, review); err != nil {
		klog.Errorf("failed to unmarshal AdmissionReview: %v", err)
		return nil, fmt.Errorf("failed to unmarshal AdmissionReview: %w", err)
	}

	if review.Request == nil {
		klog.Errorf("admission review request is nil")
		return nil, fmt.Errorf("admission review request is nil")
	}

	return review, nil
}

// mutateHPCPod mutates pod specifications for HPC containers
func mutateHPCPod(ar admissionv1.AdmissionReview) *admissionv1.AdmissionResponse {
	klog.V(2).Info("processing HPC pod mutation")

	// Only handle Pod resources
	if ar.Request.Resource.Group != "" || ar.Request.Resource.Resource != "pods" {
		return &admissionv1.AdmissionResponse{
			Allowed: true,
		}
	}

	pod, err := extractPod(ar)
	if err != nil {
		klog.Error(err)
		return &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: err.Error(),
				Reason:  metav1.StatusReasonBadRequest,
			},
		}
	}

	// Check if this is an HPC container that needs mutation
	if !shouldMutateHPCPod(pod) {
		klog.V(2).Info("Pod does not require HPC mutations")
		return &admissionv1.AdmissionResponse{
			Allowed: true,
		}
	}

	klog.V(2).Infof("Mutating HPC pod: %s/%s", pod.Namespace, pod.Name)

	// Apply HPC-specific mutations
	mutatedPod := pod.DeepCopy()
	applyHPCMutations(mutatedPod)

	// Create the patch
	originalBytes, err := json.Marshal(pod)
	if err != nil {
		klog.Error(err)
		return &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: fmt.Sprintf("failed to marshal original pod: %v", err),
				Reason:  metav1.StatusReasonInternalError,
			},
		}
	}

	mutatedBytes, err := json.Marshal(mutatedPod)
	if err != nil {
		klog.Error(err)
		return &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: fmt.Sprintf("failed to marshal mutated pod: %v", err),
				Reason:  metav1.StatusReasonInternalError,
			},
		}
	}

	// Create JSON patch operations using the library
	patch, err := jsonpatch.CreatePatch(originalBytes, mutatedBytes)
	if err != nil {
		klog.Error(err)
		return &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: fmt.Sprintf("failed to create JSON patch: %v", err),
				Reason:  metav1.StatusReasonInternalError,
			},
		}
	}

	patchBytes, err := json.Marshal(patch)
	if err != nil {
		klog.Error(err)
		return &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: fmt.Sprintf("failed to marshal JSON patch: %v", err),
				Reason:  metav1.StatusReasonInternalError,
			},
		}
	}

	klog.V(2).Infof("Generated JSON patch: %s", string(patchBytes))

	// Use proper JSON Patch type
	// Only include patch if there are actual operations (not just empty array "[]")
	if len(patch) == 0 {
		return &admissionv1.AdmissionResponse{
			Allowed: true,
		}
	}

	pt := admissionv1.PatchTypeJSONPatch
	return &admissionv1.AdmissionResponse{
		Allowed:   true,
		Patch:     patchBytes,
		PatchType: &pt,
	}
}

// extractPod extracts a Pod object from the admission review
func extractPod(ar admissionv1.AdmissionReview) (*corev1.Pod, error) {
	if ar.Request.Object.Raw == nil {
		return nil, fmt.Errorf("no object provided in admission request")
	}

	pod := &corev1.Pod{}
	if err := json.Unmarshal(ar.Request.Object.Raw, pod); err != nil {
		return nil, fmt.Errorf("failed to unmarshal pod: %v", err)
	}

	return pod, nil
}

// shouldMutateHPCPod determines if a pod should be mutated for HPC
func shouldMutateHPCPod(pod *corev1.Pod) bool {
	// Check for hostProcess and hostNetwork configuration
	hasHostProcess := false
	hasHostNetwork := pod.Spec.HostNetwork

	// Check if hostProcess is set at pod level
	if pod.Spec.SecurityContext != nil &&
		pod.Spec.SecurityContext.WindowsOptions != nil &&
		pod.Spec.SecurityContext.WindowsOptions.HostProcess != nil {
		hasHostProcess = *pod.Spec.SecurityContext.WindowsOptions.HostProcess
	}

	// If not found at pod level, check container level
	if !hasHostProcess {
		for _, container := range pod.Spec.Containers {
			if container.SecurityContext != nil &&
				container.SecurityContext.WindowsOptions != nil &&
				container.SecurityContext.WindowsOptions.HostProcess != nil &&
				*container.SecurityContext.WindowsOptions.HostProcess {
				hasHostProcess = true
				break
			}
		}
	}

	// Check if any container is a valid agnhost container
	hasValidAgnhostContainer := false
	for _, container := range pod.Spec.Containers {
		if isAgnhostContainer(&container) {
			hasValidAgnhostContainer = true
			break
		}
	}

	// Only mutate if all conditions are met:
	// 1. Pod is targeting Windows nodes
	// 2. hostProcess is true (at pod or container level)
	// 3. hostNetwork is true
	// 4. at least one container uses agnhost image
	return hasHostProcess && hasHostNetwork && hasValidAgnhostContainer

}

// matchesAgnhostCommand checks if command starts with "agnhost" followed by whitespace or is exactly "agnhost"
func matchesAgnhostCommand(command string) bool {
	return agnhostCmdRegex.MatchString(command)
}

// isAgnhostContainer checks if a container is an agnhost container that should be mutated
func isAgnhostContainer(container *corev1.Container) bool {
	// Check if container uses agnhost image
	if !strings.Contains(container.Image, "agnhost") {
		return false
	}

	// Check if command is null/empty or contains "agnhost"
	if len(container.Command) == 0 {
		return true
	}

	// Check if first command matches agnhost pattern
	return matchesAgnhostCommand(container.Command[0])
}

// applyHPCMutations applies HPC-specific mutations to the pod
func applyHPCMutations(pod *corev1.Pod) {
	// Initialize annotations if nil
	if pod.Annotations == nil {
		pod.Annotations = make(map[string]string)
	}

	// Apply mutations to each agnhost container
	for i := range pod.Spec.Containers {
		container := &pod.Spec.Containers[i]

		// Only mutate agnhost containers
		if !isAgnhostContainer(container) {
			continue
		}

		// Modify command format for HPC workloads
		container.Command, container.Args = wrapHPCCommand(container.Command, container.Args)

		// Add annotation to track that this pod was mutated
		pod.Annotations["hpc.kubernetes.io/mutated"] = "true"
	}

	klog.V(2).Infof("Applied HPC mutations to pod %s/%s", pod.Namespace, pod.Name)
}

// wrapHPCCommand wraps commands for HPC optimization, converting agnhost to PowerShell wrapper
func wrapHPCCommand(originalCmd []string, originalArgs []string) ([]string, []string) {
	// Build the agnhost arguments string
	var agnhostArgs string

	// If no command specified, agnhostArgs == originalArgs
	if len(originalCmd) == 0 {
		if len(originalArgs) > 0 {
			agnhostArgs = strings.Join(originalArgs, " ")
		} else {
			agnhostArgs = ""
		}
	} else {
		// Remove "agnhost" from originalCmd[0] if it exists and combine with remaining
		var allArgs []string

		// Process the first command, removing "agnhost" prefix if present
		if len(originalCmd) > 0 {
			firstCmd := originalCmd[0]
			// Remove "agnhost" prefix if it exists (with optional trailing space)
			if strings.HasPrefix(firstCmd, "agnhost ") {
				firstCmd = strings.TrimPrefix(firstCmd, "agnhost ")
			} else if firstCmd == "agnhost" {
				firstCmd = ""
			}

			// Add the cleaned first command if it's not empty
			if firstCmd != "" {
				allArgs = append(allArgs, firstCmd)
			}
		}

		// Add remaining command parts
		if len(originalCmd) > 1 {
			allArgs = append(allArgs, originalCmd[1:]...)
		}

		// Add original args
		allArgs = append(allArgs, originalArgs...)

		if len(allArgs) > 0 {
			agnhostArgs = strings.Join(allArgs, " ")
		} else {
			agnhostArgs = ""
		}
	}

	// Create PowerShell command that copies and runs agnhost
	powershellScript := fmt.Sprintf("Copy-Item c:\\hpc\\agnhost -Destination c:\\hpc\\agnhost.exe; c:\\hpc\\agnhost.exe %s", agnhostArgs)

	// Return PowerShell wrapper command
	newCmd := []string{"powershell", "-Command"}
	newArgs := []string{powershellScript}

	return newCmd, newArgs
}
