# **create-imagesetconfigfile.sh**
### Description: 
- This script creates an imageSetConfiguration file for a specific catalog
  with selected operators
- The configuration file will contain each selected operator with the default
  channel and the latest release as "minVersion"
  
### Instructions
Edit the script and follow the instruction

1.  Specify the version of oc-mirror that you are using<br>
    ex: OCMIRRORVER=v2<br>
    <br>
2.  Specify the version<br>
    ex: 4.12 or 4.13 or 4.14<br>
    OCP_VERSION=4.18<br>
    <br>
3.  keep "uncomment" only the catalogs where the operator belong
  ~~~
  CATALOGS["redhat"]="registry.redhat.io/redhat/redhat-operator-index:v$OCP_VERSION"
  #CATALOGS["certified"]="registry.redhat.io/redhat/certified-operator-index:v$OCP_VERSION"
  #CATALOGS["community"]="registry.redhat.io/redhat/community-operator-index:v$OCP_VERSION"
  #CATALOGS["marketplace"]="registry.redhat.io/redhat/redhat-marketplace-index:v$OCP_VERSION"
  ~~~
4.  Specify the operators - modify this list as required<br>
  - Split each operator using "|"<br>
  ex: KEEP="elasticsearch-operator|kiali-ossm|servicemeshoperator|openshift-pipelines-operator-rh"<br>
  <br>
5. save and run the script
  Ex:<br>
  ./create-imagesetconfigfile.sh<br>
  Ouput:<br>
  - imageset configuration file<br>
    "$catalog-op-v<ocp version>-config-<ocmirror version>-<date>.yaml"

