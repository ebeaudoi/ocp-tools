
# **- create-imagesetconfigfile.sh**
### Description: 
- This script creates an imageSetConfiguration file for a specific catalog
  with selected operators
- The configuration file will contain each selected operator with the default
  channel and the latest release as "minVersion" and as "maxVersion"
  
### Instructions
Edit the script and follow the instruction

1.  Specify the version, ex: 4.12 or 4.13 or 4.14
2.  keep "uncomment" only the catalogs where the operator belong
3.  Specify the operators - modify this list as required
4.  save and run the script

Ex:

./create-imagesetconfigfile.sh

Ouput:

\- imageset configuration file


#**findoperatorsreleasedetails.sh**

### Description: 
- This script lists all the operators for a specific catalog
  including their default channel and the software release for
  that channel

### Instructions

run the script with OCP release as parameter.

A menu will show up asking to choose the Operator.

Ex:

./findoperatorsreleasedetails.sh 4.13

Ouput:

\- Text file with operator, default channel and default channel’s releases

#**findpruneoperatorsreleasedetails.sh**

### Description: 
- This script will list the default channel and the software release for
  selected operators for a specific catalog


### Instructions
Edit the script and follow the instruction

1.  Specify the version, ex: 4.12 or 4.13 or 4.14
2.  keep "uncomment" only the catalogs where the operator belong
3.  Specify the operators - modify this list as required
4.  save and run the script

Ex:

./findpruneoperatorsreleasedetails.sh

Output:

\- Text file with Specific operator, default channel and default channel’s releases


#**ocmirror-generate-imagesetconfigurationyamlfile.sh**

### Description: 
- This script creates an imageSetConfiguration file for a specific catalog
  with selected operators
- The configuration file will contain each selected operator with the default
  channel and the latest release as "minVersion" and as "maxVersion"

  Note: This script use “oc-mirror” command is much slower

### Instructions
Edit the script and update the variables:

**OPERATORFROM**: “From which registry the Operators are coming from”

**CVERSION**: “The OCP Version”

**CREGIS**: “The Catalog being used”

**KEEP**: “All the operators that you want for that specific catalog”

Run the script:

./ocmirror-generate-imagesetconfigurationyamlfile.sh

Output:

imageset configuration file
