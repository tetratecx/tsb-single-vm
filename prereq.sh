#!/usr/bin/env bash

ACTION=${1}
K8S_VERSION=${2}
TSB_VERSION=${3}
ISTIO_VERSION=${4}

if [[ ${ACTION} = "check" ]]; then

  DEPENDENCIES=( tctl minikube expect docker kubectl jq awk curl )

  # check necessary dependencies are installed
  for dep in "${DEPENDENCIES[@]}"
  do
    if ! command -v ${dep} &> /dev/null
    then
      echo "Dependency ${dep} could not be found, please install this on your local system first" ;
      exit 1
    fi
  done

  # check if the expected tctl version is installed
  if ! [[ "$(tctl version --local-only)" =~ "${TSB_VERSION}" ]]
  then
    echo "wrong version of tctl, please install version ${TSB_VERSION} first" ;
    exit 2
  fi

  echo "All dependency installed : ok"

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
  curl -Lo /tmp/istioctl.tar.gz "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz" ;
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