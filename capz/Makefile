.PHONY: install-kustomize
install-kustomize:
	rm ./kustomize || true
	curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash 

.PHONY: generate-templates
generate-templates: install-kustomize
	./kustomize build --load-restrictor LoadRestrictionsNone templates/ci/ > templates/windows-ci.yaml
	./kustomize build --load-restrictor LoadRestrictionsNone templates/pr/ > templates/windows-pr.yaml
	./kustomize build --load-restrictor LoadRestrictionsNone templates/gmsa/ci/ > templates/gmsa-ci.yaml
	./kustomize build --load-restrictor LoadRestrictionsNone templates/gmsa/pr/ > templates/gmsa-pr.yaml
	./kustomize build --load-restrictor LoadRestrictionsNone templates/sig > templates/shared-image-gallery-ci.yaml
