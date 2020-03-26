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
    # Install ssh-agent if not already installed, it is required by Docker.
    # (change apt-get to yum if you use a CentOS-based image)
    'which ssh-agent || ( apk add --update openssh )'
    # Run ssh-agent (inside the build environment)
    eval "$(ssh-agent -s)"
    # Add the SSH key stored in SSH_PRIVATE_KEY variable to the agent store
    echo "$SSH_PRIVATE_KEY_PM2_DEPLOY_WEBSITE" | ssh-add -

    # For Docker builds disable host key checking. Be aware that by adding that
    # you are suspectible to man-in-the-middle attacks.
    # WARNING: Use this only with the Docker executor, if you use it with shell
    # you will overwrite your user's SSH config.
    mkdir -p ~/.ssh
    '[[ -f /.dockerenv ]] && echo -e "Host *\n\tStrictHostKeyChecking no\n\n" > ~/.ssh/config'
    # In order to properly check the server's host key, assuming you created the
    # SSH_SERVER_HOSTKEYS variable previously, uncomment the following two lines
    # instead.
    # - mkdir -p ~/.ssh
    # - '[[ -f /.dockerenv ]] && echo "$SSH_SERVER_HOSTKEYS" > ~/.ssh/known_hosts'
    ssh "$SSH_USERNAME_STAGING_SERVER"@"$SSH_HOSTNAME_STAGING_SERVER" <<"EOF"
    cd $STAGING_DOCKER_COMPOSE_FOLDER
    docker-compose pull $CI_PROJECT_NAME
    docker-compose up -d --no-deps $CI_PROJECT_NAME
EOF

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
