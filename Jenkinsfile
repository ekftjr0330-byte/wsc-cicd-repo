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
                    def accountId = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
                    env.AWS_ACCOUNT_ID = accountId
                    env.ECR_REGISTRY = "${accountId}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"

                    echo "AWS Account ID: ${env.AWS_ACCOUNT_ID}"
                    echo "AWS Region: ${env.AWS_REGION}"
                }
            }
        }

        stage('Verify ECS Resources') {
            steps {
                script {
                    sh """
                        echo "=== ECS Cluster ==="
                        aws ecs describe-clusters --region ${env.AWS_REGION} --clusters ${env.ECS_CLUSTER_NAME} --query 'clusters[*].[clusterName,status]' --output table

                        echo "=== ECS Service ==="
                        aws ecs describe-services --region ${env.AWS_REGION} --cluster ${env.ECS_CLUSTER_NAME} --services ${env.ECS_SERVICE_NAME} --query 'services[*].[serviceName,status,taskDefinition]' --output table

                        echo "=== Task Definitions ==="
                        aws ecs list-task-definitions --region ${env.AWS_REGION} --family-prefix ${env.ECS_TASKDEF_NAME} --query 'taskDefinitionArns[*]' --output table
                    """
                }
            }
        }

        stage('Determine Next Image Tag') {
            steps {
                script {
                    def stdout = sh(script: "aws ecr list-images --region ${env.AWS_REGION} --repository-name ${env.ECR_REPO} --query 'imageIds[*].imageTag' --output text", returnStdout: true).trim()

                    if (!stdout || stdout == 'None' || stdout == 'null' || stdout.isEmpty()) {
                        env.IMAGE_TAG = 'v1.0.0'
                    } else {
                        def existingTags = stdout.split(/\\s+/)
                        def semverPattern = /^v\\d+\\.\\d+\\.\\d+$/
                        def versions = existingTags.findAll { it ==~ semverPattern }

                        if (versions) {
                            def maxVersion = [0, 0, 0]

                            versions.each { ver ->
                                def parts = ver.replace('v', '').split('\\.').collect { it.toInteger() }

                                for (int i = 0; i < 3; i++) {
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
                    echo "Docker Image: ${env.DOCKER_IMAGE}"
                }
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    sh """
                        aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${env.ECR_REGISTRY}
                        docker build -t ${env.DOCKER_IMAGE} .
                        docker push ${env.DOCKER_IMAGE}
                    """
                }
            }
        }

        stage('Register New Definition & Update ECS Service') {
            steps {
                script {
                    sh """
                        echo "=== Get Current Task Definition ==="
                        aws ecs describe-task-definition --region ${env.AWS_REGION} --task-definition ${env.ECS_TASKDEF_NAME} --query taskDefinition > raw_taskdef.json

                        echo "=== Create New Task Definition ==="
                        jq --arg IMAGE "${env.DOCKER_IMAGE}" 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) | .containerDefinitions[0].image = \\$IMAGE' raw_taskdef.json > taskdef.json

                        echo "=== Register New Task Definition ==="
                        aws ecs register-task-definition --region ${env.AWS_REGION} --cli-input-json file://taskdef.json --query "taskDefinition.taskDefinitionArn" --output text > new_task_arn.txt

                        echo "=== New Task Definition ==="
                        cat new_task_arn.txt

                        echo "=== Update ECS Service ==="
                        NEW_TASK_ARN=\\$(cat new_task_arn.txt)
                        aws ecs update-service --region ${env.AWS_REGION} --cluster ${env.ECS_CLUSTER_NAME} --service ${env.ECS_SERVICE_NAME} --task-definition \\$NEW_TASK_ARN --force-new-deployment
                    """
                }
            }
        }

        stage('Verify Deployment Status') {
            steps {
                script {
                    sh """
                        echo "=== ECS Deployment Status ==="
                        aws ecs describe-services --region ${env.AWS_REGION} --cluster ${env.ECS_CLUSTER_NAME} --services ${env.ECS_SERVICE_NAME} --query 'services[0].deployments[*].[status,rolloutState,taskDefinition]' --output table
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