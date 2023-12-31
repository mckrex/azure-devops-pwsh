# azure_devops_pwsh

  .Net Core use .json files for external app configuration (typically appsettings.json). The standard means to transform a settings file
  deploying to various environments is to overlay some or all of a base settings file with a file matched to an environemnr. For example, when 
  deploying to QA, at startup, the application can overlay appsettings.json with a file called appsettings.QA.json, then load those settings 
  into memory.

  For various reasons, an organization may need to employ logic more similar to that used for transforming XML configuration files. This script 
  fulfills that goal, producing a single file that can be copied to the server before application startup. It is specifically created for use in
  Azure DevOps release pipelines and is constructed to be called by a PowerShell pipeline task.

  The script uses a pipe character in the json property name to indicate the transformation action. The available actions are defined in the 
  TransformType enum.
