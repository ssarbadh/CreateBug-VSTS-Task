# CreateBug-VSTS-Task

Dynamically creates a bug (work item) in current or custom defined area & iteration path for the team project in VSTS on release failure with details like repro steps, errors, description, title, priority, severity & assigns it to the person who triggered the release.

## Requirements

The task requires access to OAuth token in order to get error details for a release and create a bug in VSTS.

* Please enable "Allow scripts to access OAuth token" flag in in Agent Phase -> Additional options (as shown below).

![alt text](Screenshots/AllowOAuth.PNG)

## How to use

The task can be added at any step in the release pipeline but In order to make the best out of the same it is recommended to have a 2-Phase release pipeline where the Run This Phase setting for the second phase (containing the task) is set to "Only when a previous phase has failed". This way the task will be able to get error details for all failed environments.

In a multi environment release definition the same strategy can be applied to all release definitions so that the bug for each failure has consolidated report of error logs from all failed environments up-to that point.

1. Add the task

![alt text](Screenshots/AddTask.PNG)

2. Configure the task

3. Stand-alone step

4. Multi-Phase configuration (recommended)
