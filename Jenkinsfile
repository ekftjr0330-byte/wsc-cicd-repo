pipeline {
    agent any

    environment {
        AWS_REGION = 'us-west-2'
        ECR_REPO = 'wsc-cicd-ecr'

        ECS_CLUSTER_NAME = 'wsc-cicd-ecs-cluster'
        ECS_SERVICE_NAME = 'wsc-cicd-ecs-svc'
        ECS_TASKDEF_NAME = 'wsc-cicd-ecs-taskdef'
        ECS_CONTAINER_NAME = 'wsc-cicd-ecs-cnt'

        GITHUB_CRED_ID = 'github'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Get AWS Account ID') {
            steps {
                script {
                    def accountId = sh(
                        script: "aws sts get-caller-identity --query Account --output text",
                        returnStdout: true
                    ).trim()
                    
                    env.AWS_ACCOUNT_ID = accountId
                    env.ECR_REGISTRY = "${accountId}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                    echo "AWS Account ID: ${env.AWS_ACCOUNT_ID}"
                }
            }
        }

        stage('Determine Next Image Tag') {
            steps {
                script {
                    def stdout = sh(
                        script: "aws ecr list-images --region ${env.AWS_REGION} --repository-name ${env.ECR_REPO} --query 'imageIds[*].imageTag' --output text",
                        returnStdout: true
                    ).trim()

                    if (!stdout || stdout == 'None' || stdout == 'null' || stdout.isEmpty()) {
                        env.IMAGE_TAG = 'v1.0.0'
                    } else {
                        def existingTags = stdout.split(/\s+/)
                        def semverPattern = /^v\d+\.\d+\.\d+$/
                        def versions = existingTags.findAll { it ==~ semverPattern }

                        if (versions) {
                            def maxVersion = [0,0,0]
                            versions.each { ver ->
                                def parts = ver.replaceAll('v','').split('\\.').collect { it.toInteger() }
                                for (int i=0; i<3; i++) {
                                    if (parts[i] > maxVersion[i]) {
                                        maxVersion = parts
                                        break
                                    } else if (parts[i] < maxVersion[i]) {
                                        break
                                    }
                                }
                            }
                            maxVersion[2] += 1
                            env.IMAGE_TAG = "v${maxVersion.join('.')}"
                        } else {
                            env.IMAGE_TAG = 'v1.0.0'
                        }
                    }

                    env.DOCKER_IMAGE = "${env.ECR_REGISTRY}/${env.ECR_REPO}:${env.IMAGE_TAG}"
                    echo "Next Docker Image Tag: ${env.IMAGE_TAG}"
                }
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    sh """
                    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                    docker build -t ${DOCKER_IMAGE} .
                    docker push ${DOCKER_IMAGE}
                    """
                }
            }
        }

        stage('Register New Definition') {
            steps {
                script {

                    sh """
                        aws ecs describe-task-definition --region ${env.AWS_REGION} --task-definition ${env.ECS_TASKDEF_NAME} --query taskDefinition > raw_taskdef.json
                        jq --arg IMAGE "${env.DOCKER_IMAGE}" 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) | .containerDefinitions[0].image = \\$IMAGE' raw_taskdef.json > taskdef.json
                        aws ecs register-task-definition --region ${env.AWS_REGION} --cli-input-json file://taskdef.json --query "taskDefinition.taskDefinitionArn" --output text > new_task_arn.txt
                    """
                }
            }
        }

        stage('Update ECS Service') {
            steps {
                script {

                    def newTaskArn = sh(
                        script: 'cat new_task_arn.txt',
                        returnStdout: true
                    ).trim()

                    if (!newTaskArn) {
                        error('New Task Definition ARN is empty.')
                    }

                    sh """
                        aws ecs update-service --region ${env.AWS_REGION} --cluster ${env.ECS_CLUSTER_NAME} --service ${env.ECS_SERVICE_NAME} --task-definition ${newTaskArn} --force-new-deployment
                    """
                }
            }
        }

        stage('Verify Deployment Status') {
            steps {
                script {
                    sh """
                        aws ecs describe-services --region ${env.AWS_REGION} --cluster ${env.ECS_CLUSTER_NAME} --services ${env.ECS_SERVICE_NAME} --query 'services[0].deployments[*].[status,rolloutState,taskDefinition,desiredCount,runningCount]' --output table
                    """
                }
            }
        }
    }


    post {
        success {
            echo "Successfully deployed ${env.DOCKER_IMAGE}"
        }
        always {
            sh "docker rmi ${env.DOCKER_IMAGE} || true"
            cleanWs()
        }
    }
}