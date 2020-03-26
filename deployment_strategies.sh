#!/bin/bash

# deployment strategies supported
# docker/docker-compose
# kubernetes
# pm2
# docker-swarm

echo "deployment strategies:"
printenv
echo "--------------------------------------------------------------------------------"

if [[ -z "${DEPLOYMENT_STRATEGY}" ]]
then
    echo "No Deployment strategy found! Exiting"
    exit
fi

function deploy_docker_strategy(){
    echo "gonna deploy via docker strategy"
    apk add --update --no-cache bash git openssh
    # Install ssh-agent if not already installed, it is required by Docker.
    # (change apt-get to yum if you use a CentOS-based image)
    which ssh-agent || ( apk add --update openssh )
    # Run ssh-agent (inside the build environment)
    eval "$(ssh-agent -s)"
    # Add the SSH key stored in SSH_PRIVATE_KEY variable to the agent store
    echo "$SSH_STAGING_PRIVATE_KEY_DEPLOYER" | ssh-add -
    ssh "$SSH_USERNAME_STAGING_SERVER"@"$SSH_HOSTNAME_STAGING_SERVER" -o StrictHostKeyChecking=no  '
    echo "changing directory to docker compose folder",$STAGING_DOCKER_COMPOSE_FOLDER;
    cd $STAGING_DOCKER_COMPOSE_FOLDER;
    echo "pull docker file to latest version";
    docker-compose pull $CI_PROJECT_NAME;
    echo "restarting $CI_PROJECT_NAME docker service";
    docker-compose up -d --no-deps $CI_PROJECT_NAME;
    '
}

function deploy_kubernetes_strategy(){
    echo "gonna deploy via kubernete strategy"
    mkdir -p /root/.kube
    if [ "$CI_COMMIT_REF_NAME" == "staging" ]
    then
        cp "$KUBE_CONFIG_STAGING" /root/.kube/config
    else
        cp "$KUBE_CONFIG_PRODUCTION" /root/.kube/config
    fi
    kubectl get pods --all-namespaces
    ls && pwd
    helm init --service-account tiller --history-max 100
    helm delete --debug --purge "$CI_PROJECT_NAME"

    if [ "$CI_COMMIT_REF_NAME" == "staging" ]
    then
        helm upgrade --install "$CI_PROJECT_NAME" ./charts/"$CI_PROJECT_NAME" --namespace "$CI_COMMIT_REF_NAME" --debug --set image.repotag="$CI_COMMIT_REF_NAME"
    else
        helm upgrade --install "$CI_PROJECT_NAME" ./charts/"$CI_PROJECT_NAME" --namespace prod --debug --set image.repotag="$CI_BUILD_TAG"
    fi
    # [ ! -z "$CI_BUILD_TAG" ]
}

function deploy_pm2_strategy(){
    echo "gonna deploy via pm2 strategy"
}

function deploy_swarm_strategy(){
    echo "gonna deploy via docker swarm strategy"
}

if [ "$DEPLOYMENT_STRATEGY" == "docker" ]
then
    deploy_docker_strategy
elif [ "$DEPLOYMENT_STRATEGY" == "kubernetes" ]
then
    deploy_kubernetes_strategy
elif [ "$DEPLOYMENT_STRATEGY" == "pm2" ]
then
    deploy_pm2_strategy
elif [ "$DEPLOYMENT_STRATEGY" == "docker-swarm" ]
then
    deploy_swarm_strategy
else
    echo "No such strategy supported!"
#  notify somewhere
fi
