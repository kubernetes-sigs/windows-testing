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
	"encoding/json"
	"testing"

	corev1 "k8s.io/api/core/v1"
)

const testRuntimeClass = "runhcs-wcow-hypervisor"

// decodeRaw unmarshals mutated pod bytes into a generic map for path assertions.
func decodeRaw(t *testing.T, b []byte) map[string]interface{} {
	t.Helper()
	out := map[string]interface{}{}
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("failed to unmarshal mutated pod: %v", err)
	}
	return out
}

// mapAt returns the nested map at raw[keys[0]][keys[1]]... or nil if absent.
func mapAt(m map[string]interface{}, keys ...string) map[string]interface{} {
	cur := m
	for _, k := range keys {
		next, ok := cur[k].(map[string]interface{})
		if !ok {
			return nil
		}
		cur = next
	}
	return cur
}

func TestMutatePodRaw(t *testing.T) {
	const annKey = "hyperv-runtimeclass-mutating-webhook"

	t.Run("injects annotation and runtimeClassName on a minimal pod", func(t *testing.T) {
		in := []byte(`{"metadata":{"name":"p1"},"spec":{"containers":[{"name":"c","image":"busybox"}]}}`)
		out, err := mutatePodRaw(in, testRuntimeClass)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		raw := decodeRaw(t, out)

		ann := mapAt(raw, "metadata", "annotations")
		if ann == nil || ann[annKey] != "mutated" {
			t.Errorf("expected annotation %q=mutated, got %v", annKey, ann)
		}
		spec := mapAt(raw, "spec")
		if spec["runtimeClassName"] != testRuntimeClass {
			t.Errorf("expected runtimeClassName=%q, got %v", testRuntimeClass, spec["runtimeClassName"])
		}
	})

	t.Run("injects runtimeClassName when present but empty", func(t *testing.T) {
		in := []byte(`{"metadata":{"name":"p1"},"spec":{"runtimeClassName":"","containers":[]}}`)
		out, err := mutatePodRaw(in, testRuntimeClass)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		spec := mapAt(decodeRaw(t, out), "spec")
		if spec["runtimeClassName"] != testRuntimeClass {
			t.Errorf("expected empty runtimeClassName to be set to %q, got %v", testRuntimeClass, spec["runtimeClassName"])
		}
	})

	t.Run("does not overwrite an existing runtimeClassName", func(t *testing.T) {
		in := []byte(`{"metadata":{"name":"p1"},"spec":{"runtimeClassName":"custom-rc","containers":[]}}`)
		out, err := mutatePodRaw(in, testRuntimeClass)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		spec := mapAt(decodeRaw(t, out), "spec")
		if spec["runtimeClassName"] != "custom-rc" {
			t.Errorf("expected runtimeClassName to remain custom-rc, got %v", spec["runtimeClassName"])
		}
	})

	t.Run("preserves container-level restartPolicyRules", func(t *testing.T) {
		// restartPolicyRules (KEP-5307) is unknown to the vendored typed API;
		// this guards against the regression where re-marshaling a typed Pod
		// dropped it. mutatePodRaw must leave it intact.
		in := []byte(`{
			"metadata":{"name":"p1"},
			"spec":{
				"restartPolicy":"Never",
				"containers":[{
					"name":"main-container",
					"image":"busybox",
					"restartPolicy":"Never",
					"restartPolicyRules":[{"action":"Restart","exitCodes":{"operator":"In","values":[42]}}]
				}]
			}
		}`)
		out, err := mutatePodRaw(in, testRuntimeClass)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		raw := decodeRaw(t, out)
		containers, ok := mapAt(raw, "spec")["containers"].([]interface{})
		if !ok || len(containers) != 1 {
			t.Fatalf("expected 1 container, got %v", mapAt(raw, "spec")["containers"])
		}
		c0 := containers[0].(map[string]interface{})
		rules, ok := c0["restartPolicyRules"].([]interface{})
		if !ok || len(rules) != 1 {
			t.Fatalf("restartPolicyRules not preserved: %v", c0["restartPolicyRules"])
		}
		rule := rules[0].(map[string]interface{})
		if rule["action"] != "Restart" {
			t.Errorf("expected rule action Restart, got %v", rule["action"])
		}
		// mutation still applied alongside preservation
		if spec := mapAt(raw, "spec"); spec["runtimeClassName"] != testRuntimeClass {
			t.Errorf("expected runtimeClassName=%q, got %v", testRuntimeClass, spec["runtimeClassName"])
		}
	})

	t.Run("preserves existing annotations and labels while adding ours", func(t *testing.T) {
		in := []byte(`{"metadata":{"name":"p1","labels":{"app":"x"},"annotations":{"keep":"me"}},"spec":{"containers":[]}}`)
		out, err := mutatePodRaw(in, testRuntimeClass)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		raw := decodeRaw(t, out)
		ann := mapAt(raw, "metadata", "annotations")
		if ann["keep"] != "me" {
			t.Errorf("expected existing annotation keep=me to be preserved, got %v", ann["keep"])
		}
		if ann[annKey] != "mutated" {
			t.Errorf("expected annotation %q=mutated, got %v", annKey, ann[annKey])
		}
		labels := mapAt(raw, "metadata", "labels")
		if labels["app"] != "x" {
			t.Errorf("expected label app=x to be preserved, got %v", labels)
		}
	})

	t.Run("creates missing metadata and spec", func(t *testing.T) {
		in := []byte(`{}`)
		out, err := mutatePodRaw(in, testRuntimeClass)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		raw := decodeRaw(t, out)
		ann := mapAt(raw, "metadata", "annotations")
		if ann == nil || ann[annKey] != "mutated" {
			t.Errorf("expected annotation to be created, got %v", ann)
		}
		spec := mapAt(raw, "spec")
		if spec == nil || spec["runtimeClassName"] != testRuntimeClass {
			t.Errorf("expected spec.runtimeClassName to be created, got %v", spec)
		}
	})

	t.Run("returns error on invalid JSON", func(t *testing.T) {
		if _, err := mutatePodRaw([]byte(`{not json`), testRuntimeClass); err == nil {
			t.Error("expected an error for invalid JSON input, got nil")
		}
	})
}

func boolPtr(b bool) *bool { return &b }

func TestShouldMutatePod(t *testing.T) {
	tests := []struct {
		name string
		pod  *corev1.Pod
		want bool
	}{
		{
			name: "default pod is mutated",
			pod:  &corev1.Pod{},
			want: true,
		},
		{
			name: "windows nodeSelector is mutated",
			pod: &corev1.Pod{Spec: corev1.PodSpec{
				NodeSelector: map[string]string{"kubernetes.io/os": "windows"},
			}},
			want: true,
		},
		{
			name: "pod-level hostProcess is skipped",
			pod: &corev1.Pod{Spec: corev1.PodSpec{
				SecurityContext: &corev1.PodSecurityContext{
					WindowsOptions: &corev1.WindowsSecurityContextOptions{HostProcess: boolPtr(true)},
				},
			}},
			want: false,
		},
		{
			name: "container-level hostProcess is skipped",
			pod: &corev1.Pod{Spec: corev1.PodSpec{
				Containers: []corev1.Container{{
					Name: "c",
					SecurityContext: &corev1.SecurityContext{
						WindowsOptions: &corev1.WindowsSecurityContextOptions{HostProcess: boolPtr(true)},
					},
				}},
			}},
			want: false,
		},
		{
			name: "init-container-level hostProcess is skipped",
			pod: &corev1.Pod{Spec: corev1.PodSpec{
				InitContainers: []corev1.Container{{
					Name: "init",
					SecurityContext: &corev1.SecurityContext{
						WindowsOptions: &corev1.WindowsSecurityContextOptions{HostProcess: boolPtr(true)},
					},
				}},
			}},
			want: false,
		},
		{
			name: "hostNetwork is skipped",
			pod:  &corev1.Pod{Spec: corev1.PodSpec{HostNetwork: true}},
			want: false,
		},
		{
			name: "linux nodeSelector is skipped",
			pod: &corev1.Pod{Spec: corev1.PodSpec{
				NodeSelector: map[string]string{"kubernetes.io/os": "linux"},
			}},
			want: false,
		},
		{
			name: "custom nodeSelector without os key is skipped",
			pod: &corev1.Pod{Spec: corev1.PodSpec{
				NodeSelector: map[string]string{"disktype": "ssd"},
			}},
			want: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := shouldMutatePod(tc.pod); got != tc.want {
				t.Errorf("shouldMutatePod() = %v, want %v", got, tc.want)
			}
		})
	}
}
