pipeline {
    agent { label 'master' }
      parameters {
        string(name: 'enterpriseToken', defaultValue: '', description: 'The MariaDB Enterprise token required to build')
      }
    stages {
        stage('Packer Validate') {
            steps {
                script {
                    COMMIT = env.GIT_COMMIT
                    sh "packer validate " +
                        "-var \'COMMIT=${COMMIT}\' " +
                        "-var \'TOKEN=${enterpriseToken}\' " +
                        "packer.json"
                }
            }
        }
        stage('Packer Build') {
            steps {
                script {
                    COMMIT = env.GIT_COMMIT
                    sh "packer build " +
                        "-var \'COMMIT=${COMMIT}\' " +
                        "-var \'TOKEN=${enterpriseToken}\' " +
                        "packer.json"
                }
            }
        }
    }
}
