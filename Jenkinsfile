pipeline {
  agent any
  
  stages {
    stage("Create Azure Resource Group") {
      steps {
        sh "/usr/bin/terraform apply --auto-approve"
      }
    } 
  }
}