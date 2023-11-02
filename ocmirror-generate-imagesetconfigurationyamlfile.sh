#!/bin/bash

######################################
## Parameter that need to be changed##

# From which registry the Operators are coming from 
# OPERATORFROM options: redhat,certified, community or marketplace
OPERATORFROM="redhat"

# Red Hat Calalog
# CVERSION options: v4.12, v4.13, v4.14
# CREGIS options: registry.redhat.io/redhat/redhat-operator-index, registry.redhat.io/redhat/certified-operator-index, 
#                 registry.redhat.io/redhat/community-operator-index or registry.redhat.io/redhat/redhat-marketplace-index
CVERSION=v4.13
CREGIS=registry.redhat.io/redhat/redhat-operator-index
CATALOG=$CREGIS:$CVERSION

# List of operators(separated by a space)
# This is the operators that needs to be pruned
# You need to make sure the Operators are included in the Catalog/version 
# the command below can be used to validate:
# $ oc-mirror list operators --catalog=$CATALOG  
KEEP="advanced-cluster-management amq7-interconnect-operator amq-broker-rhel8 amq-online amq-streams ansible-automation-platform-operator ansible-cloud-addons-operator cluster-logging compliance-operator datagrid devspaces"

#######################################################################
## Stage 1 - Create a file with the Operator and the default channel ##
echo "*****************************************************************"
echo "Stage 1/3 - Create a file with the Operator and the default channel"

# remove previous output file for stage 1
if [[ -f stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt ]]
then
  rm -fr stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt
fi
if [[ -f tmp-stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt ]]
then
  rm -fr tmp-stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt
fi
NBOFOPERATORS=$(echo $KEEP|awk '{print NF}')
COUNTOPS=1;

#Create a file with all the selected Operators and their default channel
for OPERATOR in $KEEP;
do 
  echo "$COUNTOPS/$NBOFOPERATORS -- Listing the default channel of the Operator: $OPERATOR"
  oc-mirror list operators --catalog=$CATALOG --package=$OPERATOR>>tmp-stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt;
  ((COUNTOPS++))
done

#Keep only the operators and their default channel
cat tmp-stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt|grep NAME -A1|egrep -v "NAME|--"|awk '{ print $1 "," $NF }' > stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt;

#remove the temporary file
rm tmp-stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt

######################################################################
#Stage 2 - Generate the list of the operator's versions by operator ##
echo "******************************************************************"
echo "Stage 2/3 - Generate the list of the operator's versions by operator"

# remove previous output file for stage 2
if [[ -f stage2-$OPERATORFROM-operators-$CVERSION-versions-default-channel.txt ]]
then
  rm -fr stage2-$OPERATORFROM-operators-$CVERSION-versions-default-channel.txt
fi

# Create a file for each selected Operators with their latest version from the default channel
COUNTOPS=1;
while read -r line;
do 
  OPNAME=$(echo $line|awk -F, '{print $1}'); CHNAME=$(echo $line|awk -F, '{print $2}');
  echo "$COUNTOPS/$NBOFOPERATORS -- Finding all the version of the operator=$OPNAME with channel=$CHNAME"
  echo "::$OPNAME::$CHNAME" >> stage2-$OPERATORFROM-operators-$CVERSION-versions-default-channel.txt;
  oc-mirror list operators --catalog=$CATALOG --package=$OPNAME --channel=$CHNAME |sort -rn|egrep -v ^VERSION >> stage2-$OPERATORFROM-operators-$CVERSION-versions-default-channel.txt;
  ((COUNTOPS++))
done < stage1-$OPERATORFROM-operators-$CVERSION-withchannels.txt;

######################################################
#Stage 3 - Generate the ImageSet configuration file ##
echo "***************************************************************************"
echo "Stage 3/3 - Generate the ImageSetConfiguration with all the Opertaors/version"
COUNTOPS=1;

# Create the header of the ImageSet configuration file
echo "kind: ImageSetConfiguration" >$OPERATORFROM-op-$CVERSION-config.yaml
echo "apiVersion: mirror.openshift.io/v1alpha2" >>$OPERATORFROM-op-$CVERSION-config.yaml
echo "storageConfig:" >>$OPERATORFROM-op-$CVERSION-config.yaml
echo "  local:" >>$OPERATORFROM-op-$CVERSION-config.yaml
echo "    path: ./metadata/$OPERATORFROM-catalogs" >>$OPERATORFROM-op-$CVERSION-config.yaml
echo "mirror:" >>$OPERATORFROM-op-$CVERSION-config.yaml
echo "  operators:" >>$OPERATORFROM-op-$CVERSION-config.yaml
echo "  - catalog: $CATALOG" >>$OPERATORFROM-op-$CVERSION-config.yaml
echo "    targetCatalog: my-$OPERATORFROM-$CVERSION-catalog" >>$OPERATORFROM-op-$CVERSION-config.yaml
echo "    packages:" >>$OPERATORFROM-op-$CVERSION-config.yaml

# Create en entry for each Operator in the ImageSet configuration file including the min/max version
previousline="";
while read -r line;
do
  #Verify if the previous line is an operator name.  If so, add an entry to the ImageSetConfiguration config file
  if [[ -n $previousline && $previousline = ::* ]]
  then
    opname=$(echo $previousline|awk -F'::' '{print $2}')
    opchannel=$(echo $previousline|awk -F'::' '{print $3}')
    opversion=$(echo $line|awk '{ print $1 }')
    echo "$COUNTOPS/$NBOFOPERATORS -- Adding operator=$opname with channel=$opchannel and version $opversion"
    echo "    - name: $opname" >>$OPERATORFROM-op-$CVERSION-config.yaml
    echo "      channels:" >>$OPERATORFROM-op-$CVERSION-config.yaml
    echo "      - name: $opchannel" >>$OPERATORFROM-op-$CVERSION-config.yaml
    echo "        minVersion: '$line'" >>$OPERATORFROM-op-$CVERSION-config.yaml
    echo "        maxVersion: '$line'" >>$OPERATORFROM-op-$CVERSION-config.yaml
  fi
  previousline=$line;
done < stage2-$OPERATORFROM-operators-$CVERSION-versions-default-channel.txt
