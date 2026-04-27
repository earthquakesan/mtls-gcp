TF_DIR := terraform

.PHONY: plan apply init destroy

init:
	terraform -chdir=$(TF_DIR) init

plan: init
	terraform -chdir=$(TF_DIR) plan

apply: init
	terraform -chdir=$(TF_DIR) apply -auto-approve

destroy: init
	terraform -chdir=$(TF_DIR) destroy -auto-approve
