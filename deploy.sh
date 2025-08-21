#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo "[ERROR] $(basename "$0") failed at line $LINENO while running: $BASH_COMMAND" >&2' ERR

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Required command not found: $1" >&2
		exit 127
	fi
}

main() {
	require_cmd terraform

	export TF_IN_AUTOMATION=1

	log "Initializing Terraform..."
	terraform init -input=false

	# Detect if there are existing Terraform-managed resources (show output)
	resources_exist=0
	log "Checking current Terraform resources (if any)..."
	state_tmp="$(mktemp)"
	set +e
	set +o pipefail
	terraform state list | tee "$state_tmp"
	state_rc=$?
	set -o pipefail
	set -e
	if [ $state_rc -eq 0 ] && [ -s "$state_tmp" ]; then
		resources_exist=1
	fi
	rm -f "$state_tmp"

	if [ "$resources_exist" -eq 1 ]; then
		log "Existing resources detected. Destroying before fresh apply..."
		time terraform destroy -auto-approve
		log "Destroy complete."
	fi

	log "Planning..."
	terraform plan -input=false

	log "Applying..."
	time terraform apply -auto-approve

	if command -v ansible-playbook >/dev/null 2>&1; then
		log "Running Ansible provisioning..."
		ansible-playbook provision.yml
	else
		log "Ansible not found. To provision, run: ansible-playbook provision.yml"
	fi

	log "Done."
}

main "$@"
