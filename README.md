# A PowerShell Script to Transform JSON Documents
This script is intended to mimic the functionality of Microsoft's Xml Document Transformation (XDT) technology, but for documents using JSON.

## Problem
My organization had a requirement to transform JSON configuration files outside of the built-in substitution logic found in .Net Core applications. Primarily, we needed to transform the configuration files needed for each deployment environment at build time so that all configurations would be finalized and stored alongside compiled code binaries for deployment.  Additionally, we wanted a system to transform settings similar to the XML transformations used in our numerous existing .Net Framework applications. 
## Solution
The solution is a single PowerShell script file, which is intended to be called in some kind of automated build pipeline. It takes as parameters a path to a base file name (`-BaseFileName`) and a folder path (`-FileSource`), The assumption is that a settings file and its transformation files would share a common base name (e.g., “appsettings”) and be stored in a common location. There is a third parameter for an output directory (`-OutputDirectory`).

The most common scenario would include a directory structure that looks like this:

```
appsettings.json
appsettings.PROD.json
appsettings.QA.json
```

However, our organization had directories that stored groups of settings files for different components of a single application, where the directory looked more like this:

```
appsettings.json
appsettings.PROD.json
appsettings.QA.json
appsettings.component1.json
appsettings.component1.PROD.json
appsettings.component1.QA.json
appsettings.component2.json
appsettings.component2.PROD.json
appsettings.component2.QA.json
```

By using a base name (“appsettings “, “appsettings.component1”,  “appsettings.component2”), the pipeline has control over what files are transformed while keeping all deployed configurations in a single location.

The output directory is intended to hold the transformed configuration for each environment. In the above scenario, two folders – QA and PROD – would be created to hold transformed files and would be stored alongside compiled binaries in a deployment artifact. At deployment, the configurations would be copied to a target environment from the appropriate folder. A possible improvement would be to store the transformed files together, keeping the target environment in the file name even after the completed transformation, then copying the appropriate file to the target location with a new name.

Each base file is altered according to the content of a transform file with a new file being saved in the output directory. The process repeats for as many transform files as are found in the source folder. The base and transform files are loaded as `PSCustomObjects`, then the `Edit-SettingsObject` function is called with both objects as parameters named `-baseObject` and `-transformObjec`t respectively. 

In the `Edit-SettingsObject` function, each property of the base file is iterated. If the iterated property can be cast as a PSCustomObject (a complex object), and a complex property with a matching name is found in the transform object, `Edit-SettingsObject` is called recursively using those two properties.

When the iterated property is not a `PSCustomObject`, or a property with a matching name cannot be found, then the `-transformObject` property name is examined. The script looks for a pipe character in the property name. This character is used to supply information in the same way the XDT uses attributes like `xdt:Transform="SetAttributes(value)"`. The property name is split into an array on the pipe character. The last element of the array is the property name to match to the base object; the previous elements are the transformation commands. As an example, this property in the transform object...

`"REPLACE|enabled": true`

...would cause the “enabled” property in the base object to be set to “true”. At this point, only one value is expected before the property name, for an array of length 2.

The allowed command values are REPLACE, MERGE, ADD, and REMOVE.

- REPLACE: replace a property completely, including nested properties
- MERGE: for arrays and objects; merges new values into an existing object
- ADD: adds a property not present in the base object
- REMOVE: removes a property from the base object

All values are case-sensitive

Consider the following JSON as a base object:

```
{
    "object_1": {
        "enabled": false,
        "id": "7f1ae96f-1769-4d58-b636-ca0800c6550b",
        "maximum": 1,
        "minimum": 0.125
    }
}
```

And the following as the transform object:

```
{
    "object_1": {
        "REPLACE|enabled": true,
        "id": "fc23819e-3bd1-436a-9458-c0ed46181c45",
        "REPLACE|maximum": 1.667,
        "REPLACE|minimum": 0.667,
        "ADD|allowOffCycle": true
    },
    "ADD|object_2": {
        "enabled": false,
        "id": "c18359fb-30d0-4c6d-a73f-69d1ffca73e1",
        "maximum": 2,
        "minimum": 0.5
    }
}
```

The function `Edit-SettingsObject` would iterate the base object and find the complex property called “object_1”, and it would also find a matching property in the transform object. Therefore, the function would call itself recursively with these objects as parameters. 

In the recursion, the function would not find any complex objects in the base property, so to would turn to examine the transform object. It would find three properties with the `REPLACE` command, and one with the ADD command. The values in the base object would be overwritten by the values in the transform object, and one property would be added. Th “id” property would be ignored, even thought the value is different in both properties.

The recursion would return to the parent, and, not finding any more properties in the base object, the function will iterate the original transform object. The first property in the transform object, “object_1”, would be ignored since it does not contain pipe character. The second object, “object_2”, would be examined because the name does contain the pipe character. Since the command is `ADD`, the property and all it’s values would be added to the base object. The resulting output would look like this:

```
{
    "object_1": {
        "enabled": true,
        "id": "7f1ae96f-1769-4d58-b636-ca0800c6550b",
        "maximum": 1.667,
        "minimum": 0.667,
        "allowOffCycle": true
    },
    "object_2": {
        "enabled": false,
        "id": "c18359fb-30d0-4c6d-a73f-69d1ffca73e1",
        "maximum": 2,
        "minimum": 0.5
    }
}
```

