#!/usr/bin/env bash
BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;

ACTION=${1} ;

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]" ;
  echo "Commands:" ;
  echo "  --check : check if all prerequisites are installed" ;
  echo "  --install : install all prerequisites" ;
}

# This function checks if all prerequisites are installed.
#
function check_prereq() {

  local dependencies=( tctl kubectl istioctl helm awk curl docker expect jq k3d kind minikube nc ) ;
  local istioctl_version; istioctl_version=$(get_tsb_istio_version) ;
  local k8s_version; k8s_version=$(get_mp_k8s_version) ;
  local tsb_version; tsb_version=$(get_tsb_version) ;

  # check necessary dependencies are installed
  echo "Checking if all software dependencies installed : ok" ;
  for dep in "${dependencies[@]}" ; do
    if ! command -v "${dep}" &> /dev/null ; then
      echo "Dependency ${dep} could not be found, please install this on your local system first" ;
      exit 1 ;
    fi
  done

  # check if the expected versions are installed
  extracted_tctl_version=$(timeout 1s tctl version --local-only | grep -oP 'TCTL version: v\K[0-9]+\.[0-9]+\.[0-9]+') ;
  if [[ "${extracted_tctl_version}" != "${tsb_version}" ]]; then
    print_error "Wrong version '${extracted_tctl_version}' of tctl, please install version ${tsb_version} first" ;
  fi
  extracted_kubectl_version=$(kubectl version --client=true -o json | jq -r ".clientVersion.gitVersion" | tr -d "v") ;
  if [[ "${extracted_kubectl_version}" != "${k8s_version}" ]]; then
    print_error "Wrong version '${extracted_kubectl_version}' of kubectl, please install version ${k8s_version} first" ;
  fi
  extracted_istioctl_version=$(istioctl version --remote=false) ;
  if [[ "${extracted_istioctl_version}" != "${istioctl_version}" ]]; then
    print_error "Wrong version '${extracted_istioctl_version}' of istioctl, please install version ${istioctl_version} first" ;
  fi

  print_info "Prerequisites checks OK."
  echo "- tctl version: ${extracted_tctl_version}" ;
  echo "- kubectl version: ${extracted_kubectl_version}" ;
  echo "- istioctl version: ${extracted_istioctl_version}" ;
  print_info "You have configured scenario \"$(get_scenario)\" on topology \"$(get_topology)\"" ;
}


# This function installs all prerequisites.
#
function install_prereq() {
  local architecture; architecture=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm64\|aarch64/arm64/') ;
  local istioctl_version; istioctl_version=$(get_tsb_istio_version) ;
  local k8s_version; k8s_version=$(get_mp_k8s_version) ;
  local tsb_version; tsb_version=$(get_tsb_version) ;

  print_info "Installing apt packages" ;
  sud apt-get -y update ; sudo NEEDRESTART_MODE=a apt-get -y upgrade ;
  sudo apt-get -y install curl docker.io expect httpie jq make net-tools nmap traceroute tree ;
  sudo systemctl enable docker ;
  sudo systemctl start docker ;
  sudo usermod -aG docker "${USER}" ;
  print_info "Log out of this session and log back in to have docker access" ;

  print_info "Installing kubectl" ;
  curl -Lo /tmp/kubectl "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${architecture}/kubectl" ;
  chmod +x /tmp/kubectl ;
  sudo install /tmp/kubectl /usr/local/bin/kubectl ;
  rm -f /tmp/kubectl ;

  print_info "Installing k9s" ;
  curl -Lo /tmp/k9s.tar.gz "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${architecture}.tar.gz" ;
  tar xvfz /tmp/k9s.tar.gz -C /tmp ;
  chmod +x /tmp/k9s ;
  sudo install /tmp/k9s /usr/local/bin/k9s ;
  rm -f /tmp/k9s* ;

  print_info "Installing minikube" ;
  curl -Lo /tmp/minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${architecture}" ;
  chmod +x /tmp/minikube ;
  sudo install /tmp/minikube /usr/local/bin/minikube ;
  rm -f /tmp/minikube ;

  print_info "Installing kind" ;
  curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/latest/kind-linux-${architecture}" ;
  chmod +x /tmp/kind ;
  sudo install /tmp/kind /usr/local/bin/kind ;
  rm -f /tmp/kind ;

  print_info "Installing k3d" ;
  local latest_k3d_release; latest_k3d_release=$(curl --silent https://api.github.com/repos/k3d-io/k3d/releases/latest | grep -i "tag_name" | awk -F '"' '{print $4}') ;
  curl -Lo /tmp/k3d "https://github.com/k3d-io/k3d/releases/download/${latest_k3d_release}/k3d-linux-${architecture}" ;
  chmod +x /tmp/k3d ;
  sudo install /tmp/k3d /usr/local/bin/k3d ;
  rm -f /tmp/k3d ;

  print_info "Installing istioctl" ;
  curl -Lo /tmp/istioctl.tar.gz "https://github.com/istio/istio/releases/download/${istioctl_version}/istioctl-${istioctl_version}-linux-${architecture}.tar.gz" ;
  tar xvfz /tmp/istioctl.tar.gz -C /tmp ;
  chmod +x /tmp/istioctl ;
  sudo install /tmp/istioctl /usr/local/bin/istioctl ;
  rm -f /tmp/istioctl* ;

  print_info "Installing tctl" ;
  curl -Lo /tmp/tctl "https://binaries.dl.tetrate.io/public/raw/versions/linux-${architecture}-${tsb_version}/tctl" ;
  chmod +x /tmp/tctl ;
  sudo install /tmp/tctl /usr/local/bin/tctl ;
  rm -f /tmp/tctl ;

  print_info "Installing helm" ;
  local latest_helm_release; latest_helm_release=$(curl --silent https://api.github.com/repos/helm/helm/releases/latest | grep -i "tag_name" | awk -F '"' '{print $4}') ;
  curl -Lo /tmp/helm.tar.gz "https://get.helm.sh/helm-${latest_helm_release}-linux-${architecture}.tar.gz" ;
  tar xvfz /tmp/helm.tar.gz -C /tmp ;
  chmod +x /tmp/linux-${architecture}/helm ;
  sudo install /tmp/linux-${architecture}/helm /usr/local/bin/helm ;
  rm -rf /tmp/linux-${architecture} ;

  print_info "Installing argocd" ;
  curl -Lo /tmp/argocd "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${architecture}" ;
  chmod +x /tmp/argocd ;
  sudo install /tmp/argocd /usr/local/bin/argocd ;
  rm -f /tmp/argocd ;

  print_info "Configuring command completion for all CLIs" ;
  sudo bash -c "argocd completion bash > /etc/bash_completion.d/argocd" ;
  sudo bash -c "helm completion bash > /etc/bash_completion.d/helm" ;
  sudo bash -c "istioctl completion bash > /etc/bash_completion.d/istioctl" ;
  sudo bash -c "k3d completion bash > /etc/bash_completion.d/k3d" ;
  sudo bash -c "k9s completion bash > /etc/bash_completion.d/k9s" ;
  sudo bash -c "kind completion bash > /etc/bash_completion.d/kind" ;
  sudo bash -c "kubectl completion bash > /etc/bash_completion.d/kubectl" ;
  sudo bash -c "minikube completion bash > /etc/bash_completion.d/minikube" ;
  sudo bash -c "tctl completion bash > /etc/bash_completion.d/tctl" ;

  # shellcheck disable=SC2002
  if ! cat "${HOME}/.bashrc" | grep "# Added by prereq.sh" &>/dev/null ; then
    print_info "Enabling bash completion and add some alias" ;
    tee -a  "${HOME}/.bashrc" << END

# Added by prereq.sh
source /etc/bash_completion
export EDITOR=vim
alias k=kubectl
complete -F __start_kubectl k
END
  fi

  # shellcheck source=/dev/null
  source "${HOME}/.bashrc" ;

  print_info "All prerequisites have been installed" ;
}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --check)
    print_stage "Going to check if all prerequisites are installed" ;
    start_time=$(date +%s); check_prereq; elapsed_time=$(( $(date +%s) - start_time )) ;
    print_stage "Checked prerequisites in ${elapsed_time} seconds" ;
    ;;
  --install)
    print_stage "Going to install all prerequisites" ;
    start_time=$(date +%s); install_prereq; elapsed_time=$(( $(date +%s) - start_time )) ;
    print_stage "Installed prerequisites in ${elapsed_time} seconds" ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac