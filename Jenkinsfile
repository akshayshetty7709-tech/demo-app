// DEMO deploy pipeline (runs on the DevOps Jenkins, deploys to EC2-A over SSH).
// Same pattern as the Bikerz pipeline: clone -> build -> swap -> health check -> rollback,
// then an optional trigger of the QA job on the SEPARATE QA Jenkins.
pipeline {
    agent any

    parameters {
        string(name: 'BRANCH', defaultValue: 'main', description: 'Git branch to deploy')
        string(name: 'HEALTH_URL', defaultValue: 'http://localhost:8085/health', description: 'URL checked ON THE SERVER after deploy')
        string(name: 'QA_JENKINS_URL', defaultValue: 'http://13.203.156.69:8080', description: 'Base URL of the SEPARATE QA Jenkins (EC2-B). Replace QA-EC2-IP with the real IP. Do NOT use localhost.')
        string(name: 'QA_JOB_NAME', defaultValue: 'demo-qa-job', description: 'Exact job name on the QA Jenkins')
        string(name: 'APP_URL', defaultValue: 'http://13.203.196.213:8085', description: 'Public URL of the demo app (replace EC2-A-IP) - the QA job tests this')
        booleanParam(name: 'TRIGGER_QA', defaultValue: false, description: 'Trigger the QA job on the QA Jenkins after a successful deploy')
    }

    environment {
        // The deploy server is THIS machine (EC2-A). Jenkins logs in to it over SSH, exactly like it would to a remote server.
        SERVER   = 'ubuntu@13.203.196.213'
        APP_DIR  = '/home/ubuntu/demo-app'
        // TODO: replace <YOUR-GITHUB-USER> with your GitHub username (public repo, so no key is needed to clone)
        REPO     = 'https://github.com/akshayshetty7709-tech/demo-app.git'
        // The server key must be in the jenkins user's known_hosts (setup-devops-ec2.sh does this)
        SSH_OPTS = '-o StrictHostKeyChecking=yes'
    }

    options {
        timeout(time: 20, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {
        stage('Check settings') {
            steps {
                sh '''
                    case "$REPO" in
                      *"akshayshetty7709-tech"*) echo "Set REPO in the Jenkinsfile to your real GitHub repo URL"; exit 1 ;;
                    esac
                    echo "Deploying branch $BRANCH from $REPO to $SERVER:$APP_DIR"
                '''
            }
        }

        stage('Clone new release') {
            steps {
                sshagent(['demo-server-ssh']) {
                    sh '''
ssh $SSH_OPTS $SERVER "APP_DIR=$APP_DIR REPO=$REPO BRANCH=$BRANCH bash -s" <<'EOF2'
set -e
rm -rf "${APP_DIR}_new"
git clone --depth 1 -b "$BRANCH" "$REPO" "${APP_DIR}_new"
cd "${APP_DIR}_new"
test -f docker-compose.yml
test -f server.js
EOF2
                    '''
                }
            }
        }

        stage('Build and switch') {
            steps {
                sshagent(['demo-server-ssh']) {
                    sh '''
ssh $SSH_OPTS $SERVER "APP_DIR=$APP_DIR HEALTH_URL=$HEALTH_URL bash -s" <<'EOF2'
set -e

# 1. Validate and build the new version BEFORE touching the running one
cd "${APP_DIR}_new"
docker compose config -q
docker compose build

# 2. Stop the old version and swap folders (old one kept for rollback)
if [ -d "$APP_DIR" ]; then
  (cd "$APP_DIR" && docker compose down) || true
  rm -rf "${APP_DIR}_old"
  mv "$APP_DIR" "${APP_DIR}_old"
fi
mv "${APP_DIR}_new" "$APP_DIR"

# 3. Start the new version
cd "$APP_DIR"
docker compose up -d --remove-orphans

# 4. Health check (retry for up to ~60s); roll back if it never responds
ok=0
for i in $(seq 1 12); do
  if curl -fsS "$HEALTH_URL" > /dev/null; then ok=1; break; fi
  sleep 5
done

if [ "$ok" -ne 1 ]; then
  echo "Health check failed. Rolling back..."
  docker compose logs --tail=50 || true
  docker compose down || true
  if [ -d "${APP_DIR}_old" ]; then
    rm -rf "$APP_DIR"
    mv "${APP_DIR}_old" "$APP_DIR"
    # --build: the image tag was overwritten by the new build, so rebuild the old code
    cd "$APP_DIR" && docker compose up -d --build
  fi
  exit 1
fi

docker compose ps
docker image prune -f
EOF2
                    '''
                }
            }
        }

        stage('Trigger QA Automation') {
            when { expression { params.TRIGGER_QA } }
            steps {
                // The app is already live and healthy here, so a failed trigger only marks the build UNSTABLE.
                // This stage only STARTS the QA job on the other Jenkins; it does not wait for the result.
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'demo-qa-api',
                            usernameVariable: 'QA_USER',
                            passwordVariable: 'QA_TOKEN'
                        )
                    ]) {
                        sh '''
                            set -e
                            case "$QA_JENKINS_URL" in
                              *localhost*|*127.0.0.1*|*13.203.156.69*|*example.com*)
                                echo "QA_JENKINS_URL is not set to the real QA Jenkins address: $QA_JENKINS_URL"
                                exit 1 ;;
                            esac
                            case "$APP_URL" in
                              *13.203.196.213*) echo "APP_URL still contains the placeholder EC2-A-IP"; exit 1 ;;
                            esac

                            BASE="${QA_JENKINS_URL%/}"
                            # Encode each path segment; folder jobs are given as folder/job
                            JOB_PATH=$(printf '%s' "$QA_JOB_NAME" | awk -F/ '{
                              for (i=1; i<=NF; i++) { printf "job/%s%s", $i, (i<NF ? "/" : "") }
                            }' | sed 's/ /%20/g')
                            URL="$BASE/$JOB_PATH/buildWithParameters"

                            echo "Triggering QA job: $URL (APP_URL=$APP_URL)"
                            # Credentials are passed via stdin config so they never appear in the process list or logs
                            printf 'user = "%s:%s"\\n' "$QA_USER" "$QA_TOKEN" | \\
                              curl -fsS --max-time 30 -X POST -K - --data-urlencode "APP_URL=$APP_URL" \\
                                -o /dev/null -w 'QA Jenkins responded with HTTP %{http_code}\\n' "$URL"
                            echo "QA trigger request submitted."
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Demo app deployed (branch: ${params.BRANCH}). Open ${params.APP_URL}"
        }
        unstable {
            echo 'Deployment succeeded, but the QA trigger failed. Check the "Trigger QA Automation" stage (QA_JENKINS_URL, credential demo-qa-api, security group of EC2-B, job name).'
        }
        failure {
            echo 'Demo deployment failed. Read the console log above (the failing stage is shown in red).'
        }
    }
}
