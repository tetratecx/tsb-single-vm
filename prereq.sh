#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

ACTION=${1}
ISTIOCTL_VERSION=$(get_tsb_istio_version) ;
TSB_VERSION=$(get_tsb_version) ;
K8S_VERSION=$(get_k8s_version) ;

TSB_REPO_URL=$(get_tetrate_repo_url) ;
TSB_REPO_USER=$(get_tetrate_repo_user) ;
TSB_REPO_PW=$(get_tetrate_repo_password) ;


if [[ ${ACTION} = "check" ]]; then

  DEPENDENCIES=( tctl minikube expect docker kubectl jq awk curl nc )

  # check necessary dependencies are installed
  echo "Checking if all software dependencies installed : ok"
  for dep in "${DEPENDENCIES[@]}" ; do
    if ! command -v ${dep} &> /dev/null ; then
      echo "Dependency ${dep} could not be found, please install this on your local system first" ;
      exit 1
    fi
  done
  # check if the expected tctl version is installed
  if ! [[ "$(tctl version --local-only)" =~ "${TSB_VERSION}" ]] ; then
    echo "wrong version of tctl, please install version ${TSB_VERSION} first" ;
    exit 2
  fi
  echo "All software dependencies installed : ok"

  # check if docker registry is available and credentials valid
  echo "Checking if docker repo is reachable and credentials valid"
  if echo ${TSB_REPO_URL} | grep ":" &>/dev/null ; then
    TSB_REPO_URL_HOST=$(echo $TSB_REPO_URL_BIS | tr ":" "\n" | head -1)
    TSB_REPO_URL_PORT=$(echo $TSB_REPO_URL_BIS | tr ":" "\n" | tail -1)
  else
    TSB_REPO_URL_HOST=${TSB_REPO_URL}
    TSB_REPO_URL_PORT=443
  fi
  if ! nc -vz -w 3 ${TSB_REPO_URL_HOST} ${TSB_REPO_URL_PORT} 2>/dev/null ; then
    echo "Failed to connect to docker registry at ${TSB_REPO_URL_HOST}:${TSB_REPO_URL_PORT}. Check your network settings (DNS/Proxy)"
    exit 3
  fi
  if ! docker login ${TSB_REPO_URL} --username ${TSB_REPO_USER} --password ${TSB_REPO_PW} 2>/dev/null; then
    echo "Failed to login to docker registry at ${TSB_REPO_URL}. Check your credentials"
    exit 4
  fi
  echo "Docker repo is reachable and credentials valid: ok"
  if ! docker ps 1>/dev/null; then
    echo "Failed to list docker containers, check if you have proper docker permissions and docker daemon is running"
    exit 5
  fi

  print_info "Prerequisites checks OK. You have configured scenario \"$(get_scenario)\" on topology \"$(get_topology)\""
  exit 0
fi

if [[ ${ACTION} = "install" ]]; then

  echo "Installing apt packages"
  sudo apt-get -y update ; sudo apt-get -y upgrade ;
  sudo apt-get -y install curl docker.io jq expect net-tools ;
  sudo systemctl enable docker ;
  sudo systemctl start docker ;
  sudo usermod -aG docker $USER ;
  echo "Log out of this session and log back in to have docker access"

  echo "Installing kubectl"
  curl -Lo /tmp/kubectl "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/kubectl" ;
  chmod +x /tmp/kubectl ;
  sudo install /tmp/kubectl /usr/local/bin/kubectl ;
  rm -f /tmp/kubectl ;

  echo "Installing k9s"
  curl -Lo /tmp/k9s.tar.gz "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz" ;
  tar xvfz /tmp/k9s.tar.gz -C /tmp ;
  chmod +x /tmp/k9s ;
  sudo install /tmp/k9s /usr/local/bin/k9s ;
  rm -f /tmp/k9s* ;

  echo "Installing minikube"
  curl -Lo /tmp/minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64" ;
  chmod +x /tmp/minikube ;
  sudo install /tmp/minikube /usr/local/bin/minikube ;
  rm -f /tmp/minikube ;

  echo "Installing istioctl"
  curl -Lo /tmp/istioctl.tar.gz "https://github.com/istio/istio/releases/download/${ISTIOCTL_VERSION}/istioctl-${ISTIOCTL_VERSION}-linux-amd64.tar.gz" ;
  tar xvfz /tmp/istioctl.tar.gz -C /tmp ;
  chmod +x /tmp/istioctl ;
  sudo install /tmp/istioctl /usr/local/bin/istioctl ;
  rm -f /tmp/istioctl* ;

  echo "Installing tctl"
  curl -Lo /tmp/tctl "https://binaries.dl.tetrate.io/public/raw/versions/linux-amd64-${TSB_VERSION}/tctl"
  chmod +x /tmp/tctl
  sudo install /tmp/tctl /usr/local/bin/tctl ;
  rm -f /tmp/tctl ;

  if ! cat ~/.bashrc | grep "# Autocompletion for tsb-demo-minikube" &>/dev/null ; then
    echo "Enabling bash completion and add some alias"
    tee -a  ~/.bashrc << END

# Autocompletion for tsb-demo-minikube
source <(kubectl completion bash)
source <(istioctl completion bash)
source <(minikube completion bash)
complete -F __start_kubectl k
alias k=kubectl
END
  fi

  echo "All prerequisites have been installed"
  exit 0
fi

echo "Please specify correct action:"
echo "  - check"
echo "  - install"
exit 1