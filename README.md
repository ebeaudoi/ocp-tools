**See below how to use the script:**

\-----------------------------------------------

**\- create-imagesetconfigfile.sh**

Edit the script and follow the instruction

1.  Specify the version, ex: 4.12 or 4.13 or 4.14
2.  keep "uncomment" only the catalogs where the operator belong
3.  Specify the operators - modify this list as required
4.  save and run the script

Ex:

./create-imagesetconfigfile.sh 4.13

Ouput:

\- imageset configuration file

\-----------------------------------------------

  

**findoperatorsreleasedetails.sh**

run the script with OCP release as parameter.

A menu will show up asking to choose the Operator.

Ex:

./findoperatorsreleasedetails.sh 4.13

Ouput:

\- Text file with operator, default channel and default channel’s releases

\-----------------------------------------------

  

**findpruneoperatorsreleasedetails.sh**

Edit the script and follow the instruction

1.  Specify the version, ex: 4.12 or 4.13 or 4.14
2.  keep "uncomment" only the catalogs where the operator belong
3.  Specify the operators - modify this list as required
4.  save and run the script

Ex:

./findpruneoperatorsreleasedetails.sh

Output:

\- Text file with Specific operator, default channel and default channel’s releases

\-----------------------------------------------

  

**ocmirror-generate-imagesetconfigurationyamlfile.sh**

Note: This script use “oc-mirror” command is much slower

Edit the script and update the variables:

**OPERATORFROM**: “From which registry the Operators are coming from”

**CVERSION**: “The OCP Version”

**CREGIS**: “The Catalog being used”

**KEEP**: “All the operators that you want for that specific catalog”

Run the script:

./ocmirror-generate-imagesetconfigurationyamlfile.sh

Output:

imageset configuration file
